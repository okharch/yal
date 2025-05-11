package ingest_alerts

import (
	"context"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"log"
	"time"
)

const flushInterval = 500 * time.Millisecond
const bufferSize = 50000

// AlertData is a buffered channel for alert data ingestion
var AlertData = make(chan []interface{}, bufferSize*3)
var AlertsFlushed = make(chan struct{})

func IngestAlertData(ctx context.Context, pgxPool *pgxpool.Pool) {

	started := time.Now()
	_, err := pgxPool.Exec(ctx, `
		TRUNCATE subscription_targets;
		insert into subscription_targets(subscription_id, target_id, target_type) SELECT DISTINCT subscription_id, target_id, target_type FROM subscription_targets_view;
	`)
	if err != nil {
		log.Fatalf("failed to create temp staging table: %v", err)
	}
	log.Printf("created subscription_targets table in %s", time.Since(started))

	rows := make([][]interface{}, 0, bufferSize)
	toMerge := 0

	flush := func() {
		if len(rows) == 0 {
			// fetch true from AlertDataDirty
			return
		}

		// COPY into staging
		start := time.Now()
		_, err := pgxPool.CopyFrom(
			ctx,
			pgx.Identifier{"alerts_staging"},
			[]string{"condition_id", "target_id", "is_on", "payload", "received_at"},
			pgx.CopyFromRows(rows),
		)
		if err != nil {
			log.Printf("failed to copy to alerts_staging: %v, row looks like this %v", err, rows[0])
			for i, item := range rows[0] {
				log.Printf("rows[0][%d] = %v (type: %T)", i, item, item)
			}
			rows = rows[:0]
			return
		}
		log.Printf("copied %d records to alerts_staging in %s", len(rows), time.Since(start))
		toMerge += len(rows)

		rows = rows[:0]
	}
	merge := func() {
		if toMerge == 0 {
			// fetch true from AlertDataDirty
			return
		}
		start := time.Now()
		// Merge into alerts table
		var size string
		_ = pgxPool.QueryRow(ctx, `SELECT pg_size_pretty(pg_table_size('alerts_staging'))`).Scan(&size)

		_, err = pgxPool.Exec(ctx, "CALL process_alert_staging()")

		if err != nil {
			log.Printf("failed to upsert into alerts: %v", err)
			return
		}

		log.Printf("merged %d alert (%s) records in %s", toMerge, size, time.Since(start))
		toMerge = 0

	}

	flushTicker := time.NewTicker(flushInterval)

	for {
		select {
		case <-ctx.Done():
			log.Printf("context done, exiting IngestAlertData")
			return

		case values, ok := <-AlertData:
			if !ok {
				flush()
				return
			}
			if values == nil {
				flush()
				merge()
				AlertsFlushed <- struct{}{} // flushed after receiving EOF
				continue
			}
			rows = append(rows, values)

			if len(rows) >= bufferSize {
				flush()
			}

		case <-flushTicker.C:
			flush()
			merge()
		}
	}
}
