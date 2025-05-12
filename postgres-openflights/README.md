# 🚀 postgres-openflights

This component is the **core database engine** of a high-performance, real-time alert system for aviation. It uses **PostgreSQL** enhanced with **OpenFlights data**, **RAM disk staging**, and **efficient triggers and procedures** to emulate and evaluate alert conditions on thousands of subscriptions and flights in under one second.

---

## 📦 Features

- **OpenFlights schema** extended with alerting logic.
- Realistic simulation of flight-based and airport-based conditions.
- High-throughput ingestion using unlogged tables in RAM disk (`alerts_staging`).
- Batched alert processing with notification broadcast using `pg_notify`.
- Views and procedures to support real-time subscriptions and condition tracking.
- `.dat` files in `import/` directory are automatically downloaded during `make import` or any full rebuild.

---

## 🛠️ How to Build & Run

Database setup and rebuild is handled from the **repository root** using the `Makefile`. Use:

```bash
make rebuild
```

This orchestrates the following:

1. Downloads OpenFlights data files (if not present).
2. Builds the PostgreSQL Docker image.
3. Starts the container with a tmpfs-mounted `/ramdisk`.
4. Initializes schema and loads OpenFlights data.
5. Seeds test alert conditions and mock subscriptions.

> For more details, see the top-level [`README.md`](../README.md).

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

| Component                     | Description                                                                 |
|------------------------------|-----------------------------------------------------------------------------|
| `alerts_staging`             | Unlogged RAM-disk table for temporary bulk ingest                           |
| `process_alert_staging()`    | Stored procedure that deduplicates and merges alerts in bulk                |
| `pg_notify` triggers         | Notify backend about affected subscriptions without polling                 |
| `user_subscription_new_alerts` | View to fetch only new, unpushed alerts per user                          |
| `get_alerts_json()`          | Efficient JSON serializer and push marker for subscription alerts           |

---

## 📂 Directory Structure

```text
.
├── Dockerfile                 # Docker image based on postgres:latest
├── import/                   # Auto-fetched OpenFlights source data files (.dat)
│   ├── fetchdata.sh
│   └── *.dat
├── initdb/                   # Initialization SQL scripts
│   ├── 01-init_schema.sql
│   ├── 02-load-openflights-data.sql
│   └── 03-test-airport-feed.sql
├── shell/                    # Shell profile customization (e.g., .inputrc for psql)
└── README.md                 # This file
```

---

## 📧 Maintainer

Oleksandr Kharchenko  
[okharch@gmail.com](mailto:okharch@gmail.com)
