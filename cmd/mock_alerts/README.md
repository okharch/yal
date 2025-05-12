# ⚙️ mock_alerts — Real-Time Alert Generator

This component is responsible for **generating synthetic alert data**, writing it to PostgreSQL in high-throughput bursts, and **simulating real-world alert subscription mechanics** with concurrent goroutines. It works in conjunction with a high-performance PostgreSQL backend, acting as a **real-time stress tester** and performance validator.

---

## 🧪 Key Features

- **High-speed alert ingestion** via buffered channels and `COPY FROM`.
- **Mock condition generation** for flights and airports.
- **Sticky alert simulation** to emulate real-world condition persistence.
- **Concurrent alert generation** using goroutines per subscription.
- **Efficient fetch of updated alerts** triggered by PostgreSQL `LISTEN/NOTIFY`.

---

## 🗂 Directory Structure

```text
cmd/mock_alerts/
├── mock-alerts.go               # Main script to run mock ingestion loop
├── ingest_alerts/ingest.go     # Buffered ingestion and merge into DB
├── mock_alerts/generate_mocks.go  # Synthetic condition value generation
└── process_alerts/listen_subscription_updates.go  # React to NOTIFY messages and fetch updates
```

---

## 🚀 How It Works

### Ingestion Pipeline

1. **GenerateMockAlerts** loads real condition templates from the DB.
2. **Each flight + airport** under each subscription generates mocked condition data.
3. Alerts are pushed into `ingest_alerts.AlertData`, a buffered channel.
4. `ingest_alerts.IngestAlertData` batches these alerts every 500ms or 50k rows.
5. On flush, alerts are staged in the `alerts_staging` RAM-disk table and merged using:
   ```sql
   CALL process_alert_staging();
   ```

### Notification and Fetching

- After alerts are merged, **PostgreSQL NOTIFY** triggers are fired with updated user subscription IDs.
- `process_alerts.ListenForSubscriptionUpdates` listens for these and batches alert fetches using:
   ```sql
   SELECT get_alerts_json($1)
   ```
- Alert fetching is run concurrently, printing throughput stats.

---

## 📊 Performance

On a modern CPU:
- **120,000+ alerts ingested per batch**
- **Merge + fetch alerts for 1000 subscriptions in <400ms**
- **Over 3,000 subscription updates per second**
- CPU remains mostly idle outside of bursts (10–40%)

---

## 🧠 Design Insights

| Concept                    | Description                                                               |
|---------------------------|---------------------------------------------------------------------------|
| Buffered channel           | High-capacity `AlertData` channel absorbs load bursts                   |
| CopyFrom + RAM-disk table  | Fast bulk write to unlogged, memory-backed `alerts_staging`             |
| Sticky alert state         | Simulates real-world alert stability over time                          |
| LISTEN/NOTIFY + goroutines | Efficient parallel subscription fetch with flush batching               |

---

## 🧪 Usage

Run the full ingestion + listener with:

```bash
make alert
```

---

## 📧 Maintainer

Oleksandr Kharchenko  
[okharch@gmail.com](mailto:okharch@gmail.com)