package process_alerts

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ConditionChangePayload struct {
	Id   int  `json:"id"`
	IsOn bool `json:"is_on"`
}

// ListenForConditionChanges listens on PostgreSQL pub/sub channel
// 'subscription_condition_changes' and reacts to changes in user's
// subscription to alert conditions.
func ListenForConditionChanges(ctx context.Context, dbConnStr string, db *pgxpool.Pool) error {
	conn, err := pgx.Connect(ctx, dbConnStr)
	if err != nil {
		return fmt.Errorf("failed to connect for LISTEN: %w", err)
	}
	defer conn.Close(ctx)

	_, err = conn.Exec(ctx, "LISTEN subscription_condition_changes")
	if err != nil {
		return fmt.Errorf("failed to LISTEN on subscription_condition_changes: %w", err)
	}

	log.Println("Listening for subscription_condition_changes notifications...")

	for {
		select {
		case <-ctx.Done():
			log.Println("Stopping condition change listener...")
			return nil
		default:
			notification, err := conn.WaitForNotification(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return nil
				}
				log.Printf("error receiving notification: %v", err)
				continue
			}

			var payload ConditionChangePayload
			err = json.Unmarshal([]byte(notification.Payload), &payload)
			if err != nil {
				log.Printf("failed to parse payload(%s): %v", notification.Payload, err)
				continue
			}

			handleConditionChange(ctx, db, payload)
		}
	}

	return nil
}

// handleConditionChange fetches alerts from the view and sends them directly as raw JSON.
func handleConditionChange(ctx context.Context, db *pgxpool.Pool, payload ConditionChangePayload) {

	var alertsJSON []byte
	query := `
			SELECT json_agg(json_build_object(
				'alert_id', alert_id,
				'condition_id', condition_id,
				'target_id', target_id,
				'target_type', target_type,
				'payload', payload,
				'updated_at', updated_at,
				'is_on', %s
			))
			FROM user_subscription_alerts
			WHERE user_subscription_condition_id = $1 AND is_on = true`

	if payload.IsOn {
		// Normal: show active alerts as-is
		query = fmt.Sprintf(query, "true")
	} else {
		// Inverted: send is_on=false for active alerts as this condition is now inactive
		query = fmt.Sprintf(query, "false")
	}

	err := db.QueryRow(ctx, query, payload.Id).Scan(&alertsJSON)
	if err != nil {
		log.Printf("failed to fetch alerts for user_subscription_id=%d: %v", payload.Id, err)
		return
	}

	if alertsJSON == nil {
		log.Printf("No alerts to push for user_subscription_id=%d (is_on=%v)", payload.Id, payload.IsOn)
		return
	}
	if ShowDebug {
		LogPayload(payload, string(alertsJSON))
	}
}

// pushAlertsToFrontend simulates sending alerts to frontend.
// Replace this with actual WebSocket/message queue/etc.
func LogPayload(payloadParams interface{}, jsonPayload string) {
	log.Printf("PUSH to frontend [user_subscription_id=%+v, payload=%s]", payloadParams, jsonPayload) // ,
}
