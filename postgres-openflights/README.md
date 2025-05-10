# 🚀 postgres-openflights

This component is the **core database engine** of a high-performance, real-time alert system for aviation. It uses **PostgreSQL** enhanced with **OpenFlights data**, **RAM disk staging**, and **efficient triggers and procedures** to emulate and evaluate alert conditions on thousands of subscriptions and flights in under one second.

---

## 📦 Features

- **OpenFlights schema** extended with alerting logic.
- Dockerized build with data preloaded from OpenFlights `.dat` files.
- Realistic simulation of flight-based and airport-based conditions.
- High-throughput ingestion using unlogged tables in RAM disk (`alerts_staging`).
- Batched alert processing with notification broadcast using `pg_notify`.
- Views and procedures to support real-time subscriptions and condition tracking.

---

## 🛠️ Build & Run

To build and launch the PostgreSQL database with full schema, data, and mock subscriptions:

```bash
make rebuild
```

This performs the following steps:

1. Builds the PostgreSQL image with OpenFlights data.
2. Runs the container with a tmpfs-mounted `/ramdisk` (512MB).
3. Initializes the schema (`initdb/01-init_schema.sql`).
4. Loads OpenFlights data (`initdb/02-load-openflights-data.sql`).
5. Seeds test conditions (`initdb/03-test-airport-feed.sql`).
6. Runs `mock_subscriptions` Go program to prepare users and subscriptions.

To generate and stress test alerts:

```bash
make ingest
```

This runs the `mock_alerts` generator which:
- Inserts up to 120,000 alerts per cycle.
- Merges and deduplicates them via a stored procedure (`process_alert_staging`).
- Sends backend notifications for affected user subscriptions.
- Fetches alerts per subscription in parallel.

---

## ⚡ Performance

Real-time tests on a 16-thread desktop CPU show:

- **~120k alerts processed in <400ms**
- **~3000 user subscriptions fetched per second**
- **CPU usage peaks at ~40% only during alert generation**
- **RAM disk staging eliminates disk I/O bottlenecks**

This validates that a **PostgreSQL-based architecture** can meet real-time alerting needs, without the overhead of microservices or external queues.

---

## 🧠 Design Highlights

| Component               | Description                                                                 |
|------------------------|-----------------------------------------------------------------------------|
| `alerts_staging`       | Unlogged RAM-disk table for temporary bulk ingest                           |
| `process_alert_staging`| Stored procedure that deduplicates and merges alerts in bulk                |
| `pg_notify` triggers   | Notify backend about affected subscriptions without polling                 |
| `user_subscription_new_alerts` | View to fetch only new, unpushed alerts per user                    |
| `get_alerts_json()`    | Efficient JSON serializer and push marker for subscription alerts           |

---

## 📂 Directory Structure

```text
.
├── Dockerfile                 # Docker image based on postgres:latest
├── Makefile                   # Build, run, and ingest automation
├── import/*.dat               # OpenFlights source data files
└── initdb/
    ├── 01-init_schema.sql     # Base schema and procedures
    ├── 02-load-openflights-data.sql
    └── 03-test-airport-feed.sql
```

---

## 📧 Maintainer

Oleksandr Kharchenko  
[okharch@gmail.com](mailto:okharch@gmail.com)