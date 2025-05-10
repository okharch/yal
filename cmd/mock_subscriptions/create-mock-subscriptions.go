// File: cmd/mock_subscriptions/mock-alerts.go
package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	numMockUsers = 1000
)

func main() {
	ctx := context.Background()

	pgDSN := "postgresql://postgres@localhost:5433/postgres?sslmode=disable"
	dbpool, err := pgxpool.New(ctx, pgDSN)
	if err != nil {
		log.Fatal(err)
	}
	defer dbpool.Close()

	var subscriptionIDs []int
	var targetViewParts []string

	// 1. Get top 30 destination airports in the U.S.
	routes, err := dbpool.Query(ctx, `
		SELECT a.id, a.name
		FROM routes r
		JOIN airports a ON r.destination_airport_id = a.id
		WHERE a.country = 'United States'
		GROUP BY a.id, a.name
		ORDER BY count(*) DESC
		LIMIT 30
	`)
	if err != nil {
		log.Fatal(err)
	}
	defer routes.Close()

	for routes.Next() {
		var id int
		var name string
		if err := routes.Scan(&id, &name); err != nil {
			log.Fatal(err)
		}

		viewName := fmt.Sprintf("subscription_%d", id)
		viewSQL := fmt.Sprintf(`
			CREATE OR REPLACE VIEW %s AS
			SELECT id AS flight_id, source_airport_id, destination_airport_id
			FROM active_flights
			WHERE destination_airport_id = %d;
		`, viewName, id)

		if _, err := dbpool.Exec(ctx, viewSQL); err != nil {
			log.Fatalf("Error creating view %s: %v", viewName, err)
		}

		if _, err := dbpool.Exec(ctx, `
			INSERT INTO subscriptions (id, name, view_name)
			VALUES ($1, $2, $3) ON CONFLICT (id) DO NOTHING
		`, id, name, viewName); err != nil {
			log.Fatalf("Error inserting subscription %d: %v", id, err)
		}

		subscriptionIDs = append(subscriptionIDs, id)

		targetViewParts = append(targetViewParts, fmt.Sprintf(`
		SELECT %d AS subscription_id, flight_id AS target_id, 'flight'::target_type AS target_type FROM %s
		UNION ALL
		SELECT %d, source_airport_id, 'source_airport'::target_type FROM %s
		UNION ALL
		SELECT %d, destination_airport_id, 'destination_airport'::target_type FROM %s
		`, id, viewName, id, viewName, id, viewName))
	}

	// 1b. Create aggregated subscription_targets_view
	viewBody := strings.Join(targetViewParts, "\nUNION ALL\n")
	targetsViewSQL := fmt.Sprintf(`
		CREATE OR REPLACE VIEW subscription_targets_view AS
		%s
	`, viewBody)
	if _, err := dbpool.Exec(ctx, targetsViewSQL); err != nil {
		log.Fatalf("Error creating subscription_targets_view: %v", err)
	}

	log.Println("✅ Subscriptions, views, and subscription_targets_view created.")

	// 2. Collect mock users
	log.Println("Preparing users...")
	users := make([][]any, 0, numMockUsers)
	for i := 1; i <= numMockUsers; i++ {
		users = append(users, []any{i, fmt.Sprintf("User %d", i)})
	}

	_, err = dbpool.CopyFrom(ctx,
		pgx.Identifier{"users"},
		[]string{"id", "name"},
		pgx.CopyFromRows(users),
	)
	if err != nil {
		log.Fatalf("Error bulk inserting users: %v", err)
	}

	// 3. Assign each user to one random subscription
	log.Println("Preparing user_subscriptions...")
	userSubs := make([][]any, 0, numMockUsers)
	for userID := 1; userID <= numMockUsers; userID++ {
		subID := subscriptionIDs[rand.Intn(len(subscriptionIDs))]
		userSubs = append(userSubs, []any{userID, subID})
	}

	_, err = dbpool.CopyFrom(ctx,
		pgx.Identifier{"user_subscriptions"},
		[]string{"user_id", "subscription_id"},
		pgx.CopyFromRows(userSubs),
	)
	if err != nil {
		log.Fatalf("Error bulk inserting user_subscriptions: %v", err)
	}

	// 4. Fetch all conditions
	log.Println("Fetching conditions...")
	condRows, err := dbpool.Query(ctx, `SELECT id FROM conditions`)
	if err != nil {
		log.Fatal("Failed to fetch conditions:", err)
	}
	var conditionIDs []int
	for condRows.Next() {
		var cid int
		if err := condRows.Scan(&cid); err != nil {
			log.Fatal(err)
		}
		conditionIDs = append(conditionIDs, cid)
	}
	condRows.Close()

	// 5. Fetch all user_subscription IDs
	log.Println("Fetching user_subscription IDs...")
	userSubRows, err := dbpool.Query(ctx, `SELECT id FROM user_subscriptions`)
	if err != nil {
		log.Fatal("Failed to fetch user_subscriptions:", err)
	}
	defer userSubRows.Close()

	log.Println("Preparing user_subscription_conditions...")
	uscRows := make([][]any, 0, len(conditionIDs)*numMockUsers)
	now := time.Now()

	for userSubRows.Next() {
		var userSubID int
		if err := userSubRows.Scan(&userSubID); err != nil {
			log.Fatal(err)
		}
		for _, condID := range conditionIDs {
			uscRows = append(uscRows, []any{userSubID, condID, true, now})
		}
	}

	_, err = dbpool.CopyFrom(ctx,
		pgx.Identifier{"user_subscription_conditions"},
		[]string{"user_subscription_id", "condition_id", "is_on", "last_changed_at"},
		pgx.CopyFromRows(uscRows),
	)
	if err != nil {
		log.Fatalf("Error bulk inserting user_subscription_conditions: %v", err)
	}

	log.Println("✅ All mock users, subscriptions, and conditions populated efficiently.")
}
