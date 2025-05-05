package main

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/lib/pq"
)

func main() {
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

	var unionParts []string

	for rows.Next() {
		var airportID int
		var airportName string

		if err := rows.Scan(&airportID, &airportName); err != nil {
			log.Fatal(err)
		}

		subscriptionID := airportID
		viewName := fmt.Sprintf("subscription_%d", subscriptionID)

		// 2. Create the view for this subscription using active_flights
		viewSQL := fmt.Sprintf(`
			CREATE OR REPLACE VIEW %s AS
			SELECT id AS flight_id, source_airport_id, destination_airport_id
			FROM active_flights
			WHERE destination_airport_id = %d;`,
			viewName, airportID)

		if _, err := db.Exec(viewSQL); err != nil {
			log.Fatalf("Error creating view %s: %v", viewName, err)
		}

		// 3. Insert into subscriptions table
		insertSubSQL := `INSERT INTO subscriptions (id, name, view_name) VALUES ($1, $2, $3)
			ON CONFLICT (id) DO NOTHING`
		if _, err := db.Exec(insertSubSQL, subscriptionID, airportName, viewName); err != nil {
			log.Fatalf("Error inserting subscription %d: %v", subscriptionID, err)
		}

		// 4. Prepare for union
		unionParts = append(unionParts,
			fmt.Sprintf("SELECT %d AS subscription_id, flight_id, source_airport_id, destination_airport_id FROM %s",
				subscriptionID, viewName))
	}

	// 5. Create the union view
	unionSQL := fmt.Sprintf(`CREATE OR REPLACE VIEW flight_to_subscription_id AS
%s;`, joinWithUnionAll(unionParts))

	if _, err := db.Exec(unionSQL); err != nil {
		log.Fatalf("Error creating flight_to_subscription_id view: %v", err)
	}

	log.Println("✅ All demo subscriptions and views created successfully.")
}

func joinWithUnionAll(parts []string) string {
	return "  " + join(parts, "\nUNION ALL\n  ")
}

func join(parts []string, sep string) string {
	out := ""
	for i, part := range parts {
		if i > 0 {
			out += sep
		}
		out += part
	}
	return out
}
