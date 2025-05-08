package main

import (
	"database/sql"
	"fmt"
	"log"
	"math/rand"
	"time"

	_ "github.com/lib/pq"
)

const (
	numMockUsers = 1000
)

func main() {
	rand.Seed(time.Now().UnixNano())

	pgDSN := "postgresql://postgres@localhost:5433/postgres?sslmode=disable"
	db, err := sql.Open("postgres", pgDSN)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// 1. Get top 30 destination airports in the U.S.
	rows, err := db.Query(`
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
	defer rows.Close()

	var subscriptionIDs []int
	for rows.Next() {
		var airportID int
		var airportName string
		if err := rows.Scan(&airportID, &airportName); err != nil {
			log.Fatal(err)
		}

		subscriptionID := airportID
		viewName := fmt.Sprintf("subscription_%d", subscriptionID)
		viewSQL := fmt.Sprintf(`
			CREATE OR REPLACE VIEW %s AS
			SELECT id AS flight_id, source_airport_id, destination_airport_id
			FROM active_flights
			WHERE destination_airport_id = %d;`,
			viewName, airportID)

		if _, err := db.Exec(viewSQL); err != nil {
			log.Fatalf("Error creating view %s: %v", viewName, err)
		}

		insertSubSQL := `INSERT INTO subscriptions (id, name, view_name) VALUES ($1, $2, $3)
			ON CONFLICT (id) DO NOTHING`
		if _, err := db.Exec(insertSubSQL, subscriptionID, airportName, viewName); err != nil {
			log.Fatalf("Error inserting subscription %d: %v", subscriptionID, err)
		}

		subscriptionIDs = append(subscriptionIDs, subscriptionID)
	}

	log.Println("✅ Subscriptions and views created.")

	// 2. Insert mock users
	log.Println("Inserting users...")
	for i := 1; i <= numMockUsers; i++ {
		_, err := db.Exec(`INSERT INTO users (id, name) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING`, i, fmt.Sprintf("User %d", i))
		if err != nil {
			log.Fatalf("Error inserting user %d: %v", i, err)
		}
	}

	// 3. Assign one random subscription to each user
	log.Println("Assigning one subscription per user...")
	for userID := 1; userID <= numMockUsers; userID++ {
		subID := subscriptionIDs[rand.Intn(len(subscriptionIDs))]
		_, err := db.Exec(`INSERT INTO user_subscriptions (user_id, subscription_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, userID, subID)
		if err != nil {
			log.Printf("Error assigning subscription %d to user %d: %v", subID, userID, err)
		}
	}

	// 4. Fetch all conditions
	log.Println("Fetching conditions...")
	condRows, err := db.Query(`SELECT id FROM conditions`)
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

	// 5. Insert user_subscription_conditions for each user_subscription
	log.Println("Creating user_subscription_conditions...")
	userSubRows, err := db.Query(`SELECT id FROM user_subscriptions`)
	if err != nil {
		log.Fatal("Failed to fetch user_subscriptions:", err)
	}
	defer userSubRows.Close()

	for userSubRows.Next() {
		var userSubID int
		if err := userSubRows.Scan(&userSubID); err != nil {
			log.Fatal(err)
		}
		for _, condID := range conditionIDs {
			_, err := db.Exec(`
				INSERT INTO user_subscription_conditions (user_subscription_id, condition_id, is_on, last_changed_at)
				VALUES ($1, $2, true, now())
				ON CONFLICT DO NOTHING`, userSubID, condID)
			if err != nil {
				log.Printf("Failed to insert condition %d for user_subscription %d: %v", condID, userSubID, err)
			}
		}
	}

	log.Println("✅ All users, subscriptions, and conditions are successfully populated.")
}
