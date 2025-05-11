package main

import (
	"context"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/lib/pq"
	"github.com/okharch/yal/ingest_alerts"
	"github.com/okharch/yal/mock_alerts"
	"github.com/okharch/yal/process_alerts"
	"log"
	"os"
	"os/signal"
	"syscall"
)

const dbConnStr = "postgresql://postgres@localhost:5433/postgres?sslmode=disable"

func main() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds) // Include milliseconds

	ctx, cancel := context.WithCancel(context.Background())
	pool, err := pgxpool.New(ctx, dbConnStr)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer pool.Close()

	go ingest_alerts.IngestAlertData(ctx, pool)
	go func() {
		err := process_alerts.ListenForSubscriptionUpdates(ctx, dbConnStr, pool)
		if err != nil {
			log.Printf("error processing user_subscription_alerts notifications: %s", err)
		}
	}()

	// Handle Ctrl-C
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("Stopping ingestion...")
		cancel()
	}()

	mock_alerts.GenerateMockAlerts(ctx, dbConnStr)
}
