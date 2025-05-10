package mock_alerts

import (
	"context"
	"database/sql"
	"fmt"
	"github.com/okharch/yal/ingest_alerts"
	"github.com/okharch/yal/model"
	"log"
	"math/rand"
	"sync"
	"sync/atomic"
	"time"
)

const (
	ingestPeriod = 12 * time.Second
)

type alertState struct {
	isOn      bool
	expiresAt time.Time
}

var (
	db                 *sql.DB
	wg                 sync.WaitGroup
	conditionTemplates []model.ConditionTemplate
	alertStatus        = make(map[string]alertState)
	alertStatusLock    sync.Mutex
)

func GenerateMockAlerts(ctx context.Context, dbConnStr string) {
	var err error
	db, err = sql.Open("postgres", dbConnStr)
	if err != nil {
		log.Fatalf("failed to connect to DB: %v", err)
	}
	defer db.Close()

	if err := LoadConditionTemplates(); err != nil {
		log.Fatalf("failed to load condition templates: %v", err)
	}
	ticker := time.NewTicker(ingestPeriod)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			runIngestionCycle(ctx)
		case <-ctx.Done():
			wg.Wait()
			return
		}
	}

}

func LoadConditionTemplates() error {
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
		var ct model.ConditionTemplate
		if err := rows.Scan(&ct.ID, &ct.TargetType, &ct.Threshold, &ct.Name); err != nil {
			return err
		}
		conditionTemplates = append(conditionTemplates, ct)
	}
	return nil
}

func runIngestionCycle(ctx context.Context) {
	start := time.Now()
	subs, err := fetchSubscriptions()
	if err != nil {
		log.Printf("error fetching subscriptions: %v", err)
		return
	}
	log.Printf("Starting generating mock data...")
	var counter atomic.Int32
	for _, sub := range subs {
		wg.Add(1)
		go func(sub model.Subscription) {
			defer wg.Done()
			counter.Add(int32(processSubscription(ctx, sub)))
		}(sub)
	}
	wg.Wait()
	ingest_alerts.AlertData <- nil // EOF
	<-ingest_alerts.AlertsFlushed  // wait until it flushed
	log.Printf("Processed %d flights in %s", counter.Load(), time.Since(start))
}

func fetchSubscriptions() ([]model.Subscription, error) {
	rows, err := db.Query(`SELECT id, name, view_name FROM subscriptions`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var subs []model.Subscription
	for rows.Next() {
		var s model.Subscription
		if err := rows.Scan(&s.ID, &s.Name, &s.ViewName); err != nil {
			return nil, err
		}
		subs = append(subs, s)
	}
	return subs, nil
}

func processSubscription(ctx context.Context, sub model.Subscription) int {
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
		go func(f model.FlightTarget) {
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

func fetchFlights(viewName string) ([]model.FlightTarget, error) {
	rows, err := db.Query(fmt.Sprintf(`SELECT flight_id, source_airport_id, destination_airport_id FROM %s`, viewName))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var flights []model.FlightTarget
	for rows.Next() {
		var f model.FlightTarget
		if err := rows.Scan(&f.FlightID, &f.SourceAirport, &f.DestAirport); err != nil {
			return nil, err
		}
		flights = append(flights, f)
	}
	return flights, nil
}

func processTargets(ctx context.Context, f model.FlightTarget) {
	targets := []struct {
		id   int
		kind string
	}{
		{f.FlightID, "flight"},
		{f.SourceAirport, "source_airport"},
		{f.DestAirport, "destination_airport"},
	}
	for _, t := range targets {
		generateAlertCondition(ctx, t.id, t.kind)
	}
}

// row of                                   condition_id INT NOT NULL REFERENCES conditions(id),
//
//	                      target_id INT NOT NULL, -- ID of flight or airport
//	                      value INT NOT NULL,
//	received_at TIMESTAMPTZ not null,

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
		// []string{"condition_id", "target_id", "is_on", "payload", "received_at"},
		ingest_alerts.AlertData <- []interface{}{ct.ID, targetID, val > ct.Threshold, `{"helper": "mock"}`, time.Now()}
	}
}

func generateStickyMockValue(targetID int, targetType string, ct model.ConditionTemplate) int {
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
