# YAL — Yet Another Aviation Alerts

**YAL** is a lightweight, scalable system for delivering real-time aviation event alerts.  
It is designed with performance, reliability, and efficient data usage in mind.

## Features

- ✈️ Real-time evaluation of aviation conditions (e.g., METAR, TAF, D-ATIS).
- 📡 Subscription-based system — compute alerts only when someone is listening.
- ⚡ Minimal database load — stores only necessary history.
- 🛠️ Efficient backend processing written in Go.
- 🗄️ PostgreSQL-backed for robust and structured data storage.
- 🧩 Designed to scale easily without overcomplicating architecture.

## Project Goals

- **Efficiency First**: Focus on simple, powerful backend logic.
- **Data-Centric**: Let the database handle what it's good at.
- **Real-Time**: Minimize delay between condition change and alert.
- **Pragmatic Design**: No unnecessary microservices, no heavy orchestration unless truly needed.

## Architecture Overview

- **Data Ingestion**: Fetch METAR/TAF/D-ATIS updates.
- **Condition Evaluation**: Apply alert rules only for active subscriptions.
- **Notification Dispatch**: Push alerts to interested users.
- **Database**: PostgreSQL used for subscriptions, condition sets, and optional alert history.

## Planned Components

- Core alert evaluation engine.
- Subscription management API.
- Background service for data ingestion.
- Optional frontend for monitoring and subscription management.

## Why "Yet Another"?

Because sometimes, the best way to move fast is to skip over-engineering and build exactly what you need.  
YAL is pragmatic — no hype, just efficient, maintainable aviation alerts.

---

## License

Private project (initially). License to be determined later.
