package process_alerts

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"log"
	"sync"
	"time"
)

type NotificationPayload struct {
	UserSubscriptionIDs []int `json:"user_subscription_ids"`
}

func fetchAlertsJSON(ctx context.Context, db *pgxpool.Pool, subscriptionId int) (string, error) {
	var jsonStr string

	err := db.QueryRow(ctx, `SELECT get_alerts_json($1)`, subscriptionId).Scan(&jsonStr)
	if err != nil {
		return "", fmt.Errorf("failed to fetch JSON: %w", err)
	}

	return jsonStr, nil
}

func ListenForSubscriptionUpdates(ctx context.Context, dbConnStr string, db *pgxpool.Pool) error {
	conn, err := pgx.Connect(ctx, dbConnStr) // this connection is used to listen for notifications
	if err != nil {
		return fmt.Errorf("failed to acquire DB connection: %w", err)
	}
	defer conn.Close(ctx)
	_, err = conn.Exec(context.Background(), "LISTEN user_subscription_alerts")
	if err != nil {
		return fmt.Errorf("failed to LISTEN: %w", err)
	}

	log.Println("Listening for user_subscription_alerts notifications...")
	affectedSubscriptions := make(chan int, 1024*16)
	go func() {
		for {
			select {
			case <-ctx.Done():
				log.Println("Stopping subscription listener...")
				return
			default:
				notification, err := conn.WaitForNotification(context.Background())
				if err != nil {
					// If context is done, this error is expected
					if ctx.Err() != nil {
						return
					}
					log.Printf("error waiting for notification: %v", err)
					continue
				}

				var payload NotificationPayload
				err = json.Unmarshal([]byte(notification.Payload), &payload)
				if err != nil {
					log.Printf("failed to parse notification payload: %v", err)
					continue
				}
				for _, id := range payload.UserSubscriptionIDs {
					select {
					case <-ctx.Done():
						log.Println("Stopping subscription listener...")
						return
					case affectedSubscriptions <- id:
					}
				}
			}
		}
	}()
	dirty := make(map[int]struct{}, 1024)
	lastFlush := time.Now()
	flushUnderway := false
	var fuLock sync.Mutex
	for {
		// read all dirty first
		select {
		case <-ctx.Done():
			log.Println("Stopping subscription listener...")
			return nil
		case id := <-affectedSubscriptions:
			dirty[id] = struct{}{}
			continue
		default:
			// no new notifications, check if need to flush dirty
		}

		// if no dirty or time since last flush is less than 100ms then wait some more
		if len(dirty) == 0 || time.Since(lastFlush) < 100*time.Millisecond {
			time.Sleep(10 * time.Millisecond)
			continue
		}
		// if flush is underway, wait for it to finish
		fuLock.Lock()
		if flushUnderway {
			fuLock.Unlock()
			continue
		}
		flushUnderway = true
		fuLock.Unlock()
		// we have some dirty flush copy them to slice to free the map
		subscriptionIDs := make([]int, 0, len(dirty))
		for id := range dirty {
			subscriptionIDs = append(subscriptionIDs, id)
		}
		// clear dirty
		dirty = make(map[int]struct{}, 1024)
		lastFlush = time.Now()
		go func() {
			started := time.Now()
			var wg sync.WaitGroup
			for id := range subscriptionIDs {
				wg.Add(1)
				go func(id int) {
					defer wg.Done()
					_, err := fetchAlertsJSON(ctx, db, id)
					if err != nil {
						log.Printf("failed to fetch alerts JSON for subscription %d: %v", id, err)
						return
					}
				}(id)
			}
			wg.Wait()
			subPerSecond := float64(len(subscriptionIDs)) / time.Since(started).Seconds()
			log.Printf("=== Finished fetching of %d user_subscription's alerts in %s. %.1f subscriptions per sec", len(subscriptionIDs), time.Since(started), subPerSecond)
			fuLock.Lock()
			flushUnderway = false
			fuLock.Unlock()
		}()
	}
}
