# ✈️ Real-Time Aviation Alert System — Proof of Concept

This repository presents a **proof-of-concept (PoC)** for a high-performance aviation alert system designed to handle **thousands of user subscriptions**, **tens of thousands of active flights**, and **multiple condition checks per flight** — all in **real-time**.

---

## 🧪 What This Is

> ⚠️ This is not a complete product — there are no HTTP APIs or frontend components.  
> The goal is to **prove that PostgreSQL can serve as the core engine** for a highly scalable real-time alert system, without the need for external brokers, caches, or microservices.

---

## ⚙️ System Highlights

- **🚀 Ingests 120,000+ alerts in < 400ms**
- **📦 Pushes new alerts to thousands of subscriptions in < 1 second**
- **📣 Real-time feedback loop via PostgreSQL `LISTEN/NOTIFY`**
- **👂 Built-in alert listener (`make listen`) for debugging**
- **⚡ Peak CPU usage rarely exceeds 40% during alert bursts**

---

## 🧠 Key Design Decisions

| Decision                                       | Impact                                                                 |
|------------------------------------------------|------------------------------------------------------------------------|
| PostgreSQL-only backend                        | No external queue or cache required                                   |
| `alerts_staging` as RAM-disk table             | Drastic performance boost by bypassing disk I/O                       |
| Bulk insert via `COPY FROM`                    | High-speed ingestion of tens of thousands of alert records            |
| Smart `process_alert_staging()` procedure      | Deduplicates, upserts, and notifies in a single pass                  |
| Realistic mock alert generation                | Emulates real load from conditions tied to flights/airports           |
| Concurrent alert fetch after notification      | Fast pull of affected alerts via `get_alerts_json()` per subscription |
| Real-time debug listener (`make listen`)       | Provides introspection into fan-out logic using PostgreSQL `NOTIFY`   |

---

## 🧱 Repository Structure

```text
.
├── postgres-openflights/        # Core PostgreSQL engine and schema
│   ├── Dockerfile
│   ├── Makefile (was here, now in repo root)
│   └── initdb/
├── cmd/
│   ├── mock_alerts/             # Real-time alert generator and simulator
│   └── listen_changes/          # PostgreSQL listener for debugging fan-out
├── import/                      # OpenFlights .dat files (downloaded dynamically)
├── Makefile                     # Main entry point: build, ingest, listen, etc.
└── README.md                    # This file
```

---

## 🚀 How to Run

### 1. Build and launch the database

```bash
make rebuild
```

This builds the container, initializes the schema, and populates test users and subscriptions.

---

### 2. Start ingestion and simulate alert traffic

```bash
make alerts
```

Let it run for 10–20 seconds, then stop with `Ctrl+C`. You’ll see real-time ingestion stats and alert fan-out throughput.

---

### 3. (Optional) Debug alert fan-out using built-in listener

Stop ingestion, then run:

```bash
make listen
```

This launches a PostgreSQL listener for alert fan-out and subscription condition changes. Use SQL commands via:

```bash
make psql
```

For example, toggle a subscription condition:

```sql
UPDATE user_subscription_conditions SET is_on = NOT is_on WHERE id = 42;
```

Or stage a new alert directly:

```sql
INSERT INTO alerts_staging VALUES (1, 257, false, '{"test":true}', now());
CALL process_alert_staging();
```

The listener will log every pushed alert and its subscription target.

---

## 🧩 Scalability Considerations

Although the system can be scaled horizontally by **partitioning flight and airport targets** across multiple PostgreSQL servers, this PoC demonstrates that such partitioning is **not required** to handle high alert volumes in real time.

Current architecture achieves sub-second latency and multi-thousand subscription throughput **on a single machine** using PostgreSQL and RAM disk staging.

> 🔬 Partitioning can improve scalability further, but increases system complexity significantly (routing, deduplication, etc.).

---

## 📊 Observed Performance (on modern desktop CPU)

| Task                                | Time     |
|-------------------------------------|----------|
| Insert 120k alert rows              | ~300ms   |
| Merge into main alert table         | ~200ms   |
| Fetch alerts for 1000 subscriptions | ~300ms   |
| **Total end-to-end time**           | **<1s**  |

---

## 🔍 What This Proves

✅ PostgreSQL alone — when used properly — can serve as the **high-throughput backend** of a real-time alerting system.  
✅ You don’t need Kafka, Redis, or microservices to scale — **clear schema, proper batching, and smart SQL** go a long way.  
✅ With `LISTEN/NOTIFY`, you can build efficient, reactive systems without polling or overengineering.

---

## 🧑‍💻 Author

Oleksandr Kharchenko  
[okharch@gmail.com](mailto:okharch@gmail.com)
