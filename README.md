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

---

## 🧱 Repository Structure

```text
.
├── postgres-openflights/        # Core PostgreSQL engine and schema
│   ├── Dockerfile
│   ├── Makefile
│   └── initdb/
├── cmd/
│   └── mock_alerts/             # Main PoC engine that simulates real-time alert traffic
│       ├── mock-alerts.go
│       ├── ingest_alerts/
│       ├── mock_alerts/
│       └── process_alerts/
```

---

## 🚀 How to Run

1. **Build and launch the database:**

```bash
cd postgres-openflights
make rebuild
```

2. **Start ingestion and simulate load:**

```bash
make ingest
```

You'll see logs for ingestion performance and alerts being fetched for thousands of user subscriptions in parallel.

---


---

## 🧩 Scalability Considerations

Although the system can theoretically be scaled horizontally by **partitioning flight and airport targets** across multiple PostgreSQL servers, this proof-of-concept demonstrates that such partitioning is **not required** for handling high volumes of alerts and subscriptions in real-time.

The current architecture achieves sub-second latency and multi-thousand subscription throughput **on a single machine** using standard PostgreSQL and RAM disk staging.

> 🔬 While partitioning could unlock additional scaling capacity, it would also demand **significantly more complex orchestration** between backend services and PostgreSQL shards — including routing, deduplication, synchronization, and fault tolerance.


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

✅ You don’t always need Kafka, Redis, or microservices to scale — **clear schema, proper batching, and smart SQL** go a long way.

---

## 🧑‍💻 Author

Oleksandr Kharchenko  
[okharch@gmail.com](mailto:okharch@gmail.com)