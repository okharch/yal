package main

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/jackc/pgx/v4"
	"github.com/jackc/pgx/v4/pgxpool"
	"log"
	"math/rand"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	_ "github.com/lib/pq"
)

const (
	dbConnStr    = "postgresql://postgres@localhost:5433/postgres?sslmode=disable"
	ingestPeriod = 10 * time.Second
)

type Subscription struct {
	ID       int
	Name     string
	ViewName string
}

type FlightTarget struct {
	FlightID      int
	SourceAirport int
	DestAirport   int
}

type ConditionTemplate struct {
	ID         int
	TargetType string
	Threshold  int
	Name       string
}

type alertState struct {
	isOn      bool
	expiresAt time.Time
}

var (
	db                 *sql.DB
	wg                 sync.WaitGroup
	conditionTemplates []ConditionTemplate
	alertStatus        = make(map[string]alertState)
	alertStatusLock    sync.Mutex
)

func main() {

	var err error
	db, err = sql.Open("postgres", dbConnStr)
	if err != nil {
		log.Fatalf("failed to connect to DB: %v", err)
	}
	defer db.Close()

	if err := loadConditionTemplates(); err != nil {
		log.Fatalf("failed to load condition templates: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())

	go ingestAlertCondition(ctx)

	// Handle Ctrl-C
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("Stopping ingestion...")
		cancel()
	}()

	ticker := time.NewTicker(ingestPeriod)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			wg.Wait()
			return
		default:
			runIngestionCycle(ctx)
		}

		select {
		case <-ticker.C:
			continue
		case <-ctx.Done():
			wg.Wait()
			return
		}
	}
}

func loadConditionTemplates() error {
	rows, err := db.Query(`
		SELECT c.id, t.target_type, c.threshold, t.name
		FROM conditions c
		JOIN condition_templates t ON c.template_id = t.id
	`)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var ct ConditionTemplate
		if err := rows.Scan(&ct.ID, &ct.TargetType, &ct.Threshold, &ct.Name); err != nil {
			return err
		}
		conditionTemplates = append(conditionTemplates, ct)
	}
	return nil
}

var everythingFlushed = make(chan struct{})

func runIngestionCycle(ctx context.Context) {
	start := time.Now()
	subs, err := fetchSubscriptions()
	if err != nil {
		log.Printf("error fetching subscriptions: %v", err)
		return
	}
	var counter atomic.Int32
	for _, sub := range subs {
		wg.Add(1)
		go func(sub Subscription) {
			defer wg.Done()
			counter.Add(int32(processSubscription(ctx, sub)))
		}(sub)
	}
	// empty everythingFlushed channel, non-blocking
	select {
	case <-everythingFlushed:
	default:
	}
	wg.Wait()
	// wait for all alert conditions to be flushed
	<-everythingFlushed
	log.Printf("Processed %d flights in %s", counter.Load(), time.Since(start))
}

func fetchSubscriptions() ([]Subscription, error) {
	rows, err := db.Query(`SELECT id, name, view_name FROM subscriptions`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var subs []Subscription
	for rows.Next() {
		var s Subscription
		if err := rows.Scan(&s.ID, &s.Name, &s.ViewName); err != nil {
			return nil, err
		}
		subs = append(subs, s)
	}
	return subs, nil
}

func processSubscription(ctx context.Context, sub Subscription) int {
	//start := time.Now()
	_, _ = db.Exec(`UPDATE subscriptions SET start_update = now() WHERE id = $1`, sub.ID)

	flights, err := fetchFlights(sub.ViewName)
	if err != nil {
		log.Printf("failed to fetch flights for %s: %v", sub.ViewName, err)
		return 0
	}
	var wg sync.WaitGroup
	for _, flight := range flights {
		wg.Add(1)
		go func(f FlightTarget) {
			defer wg.Done()
			processTargets(ctx, flight)
		}(flight)
	}
	wg.Wait()

	finish := time.Now()
	_, _ = db.Exec(`UPDATE subscriptions SET finish_update = $1 WHERE id = $2`, finish, sub.ID)
	//log.Printf("Processed %d flights for subscription %d(%s) in %s", len(flights), sub.ID, sub.Name, finish.Sub(start))
	return len(flights)
}

func fetchFlights(viewName string) ([]FlightTarget, error) {
	rows, err := db.Query(fmt.Sprintf(`SELECT flight_id, source_airport_id, destination_airport_id FROM %s`, viewName))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var flights []FlightTarget
	for rows.Next() {
		var f FlightTarget
		if err := rows.Scan(&f.FlightID, &f.SourceAirport, &f.DestAirport); err != nil {
			return nil, err
		}
		flights = append(flights, f)
	}
	return flights, nil
}

func processTargets(ctx context.Context, f FlightTarget) {
	targets := []struct {
		id   int
		kind string
	}{
		{f.FlightID, "flight"},
		{f.SourceAirport, "airport"},
		{f.DestAirport, "airport"},
	}
	for _, t := range targets {
		generateAlertCondition(ctx, t.id, t.kind)
	}
}

const bufferSize = 70000

// row of                                   condition_id INT NOT NULL REFERENCES conditions(id),
//
//	                      target_id INT NOT NULL, -- ID of flight or airport
//	                      value INT NOT NULL,
//	received_at TIMESTAMPTZ not null,
var alertConditions = make(chan []interface{}, bufferSize*3)

//

func generateAlertCondition(ctx context.Context, targetID int, targetType string) {
	for _, ct := range conditionTemplates {
		if ctx.Err() != nil {
			log.Printf("context done, exiting generateAlertCondition")
			return
		}
		if ct.TargetType != targetType {
			continue
		}
		val := generateStickyMockValue(targetID, targetType, ct)
		alertConditions <- []interface{}{ct.ID, targetID, val, time.Now()}
	}
}
func ingestAlertCondition(ctx context.Context) {
	const flushInterval = 200 * time.Millisecond
	config, err := pgxpool.ParseConfig(dbConnStr)
	if err != nil {
		// ...
	}
	pgxPool, err := pgxpool.ConnectConfig(context.Background(), config)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer pgxPool.Close()

	rows := make([][]interface{}, 0, bufferSize)

	flush := func() {
		if len(rows) == 0 {
			// non blocking send to avoid blocking the main loop
			select {
			case everythingFlushed <- struct{}{}:
			default:
			}
			return
		}
		start := time.Now()
		_, err := pgxPool.CopyFrom(
			ctx,
			pgx.Identifier{"alert_conditions"},
			[]string{"condition_id", "target_id", "value", "received_at"},
			pgx.CopyFromRows(rows),
		)
		if err != nil {
			log.Printf("failed to insert alert conditions: %v", err)
		}
		log.Printf("flushed %d alert conditions in %s", len(rows), time.Since(start))
		rows = rows[:0] // reset buffer
	}

	for {
		select {
		case <-ctx.Done():
			// no flush needed in simulation mode
			log.Printf("context done, exiting ingestAlertCondition")
			return

		case values, ok := <-alertConditions:
			if !ok {
				flush()
				return
			}
			rows = append(rows, values)
			if len(rows) >= bufferSize {
				flush()
			}

		case <-time.After(flushInterval):
			flush()
		}
	}
}

func generateStickyMockValue(targetID int, targetType string, ct ConditionTemplate) int {
	key := fmt.Sprintf("%s:%d:%d", targetType, targetID, ct.ID)
	now := time.Now()
	alertStatusLock.Lock()
	state, ok := alertStatus[key]
	alertStatusLock.Unlock()
	if ok && state.isOn {
		if now.Before(state.expiresAt) {
			return generateValue(ct.Threshold, ct.Name, true)
		}
		alertStatusLock.Lock()
		delete(alertStatus, key)
		alertStatusLock.Unlock()
	}

	if rand.Intn(10) == 0 {
		minutes := 3 + rand.Intn(3)
		alertStatusLock.Lock()
		alertStatus[key] = alertState{
			isOn:      true,
			expiresAt: now.Add(time.Duration(minutes) * time.Minute),
		}
		alertStatusLock.Unlock()
		return generateValue(ct.Threshold, ct.Name, true)
	}

	return generateValue(ct.Threshold, ct.Name, false)
}

func generateValue(threshold int, conditionName string, alertOn bool) int {
	switch conditionName {
	case "fog", "low_altitude", "low_fuel":
		if alertOn {
			return threshold - rand.Intn(50) - 1
		}
		return threshold + rand.Intn(50) + 1
	default:
		if alertOn {
			return threshold + rand.Intn(50) + 1
		}
		return threshold - rand.Intn(50) - 1
	}
}
