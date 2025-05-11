package main

import (
	"context"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/lib/pq"
	"github.com/okharch/yal/process_alerts"
	"log"
	"os"
	"os/signal"
	"sync"
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

	// lsiten for subscription updates when new alerts conditions are created
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		err := process_alerts.ListenForSubscriptionUpdates(ctx, dbConnStr, pool)
		if err != nil {
			log.Printf("error processing user_subscription_alerts notifications: %s", err)
		}
	}()

	// listen for condition changes when user subscription conditions are updated
	wg.Add(1)
	go func() {
		defer wg.Done()
		err := process_alerts.ListenForConditionChanges(ctx, dbConnStr, pool)
		if err != nil {
			log.Printf("error processing subscription_condition_changes notifications: %s", err)
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
	wg.Wait()
	log.Println("Exiting...")
}
