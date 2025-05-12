## 📡 `make listen`: Debug Real-Time Alert Fan-Out

The `make listen` target starts the alert listener daemon which subscribes to PostgreSQL `NOTIFY` channels and logs alert fan-out activity to user subscriptions. It is a core tool for testing and debugging real-time alerts.

---

### 🧩 What It Does

This command starts `cmd/listen_changes`, which spins up two concurrent listeners:

| Listener                          | Channel Name                    | Purpose                                              |
|----------------------------------|----------------------------------|------------------------------------------------------|
| `ListenForConditionChanges`      | `subscription_condition_changes` | Reacts to condition `is_on` flips for a subscription |
| `ListenForSubscriptionUpdates`   | `user_subscription_alerts`       | Reacts to bulk updates of user subscriptions         |

Both listeners output structured debug logs showing what alerts are delivered and to which subscriptions.

---

### ⚠️ Important: Stop Ingestion First

Before running `make listen`, **you must stop any ongoing `make alerts` ingestion** using `Ctrl+C` or `kill`, otherwise the the output will be overwhelmed with thousands of debug messages.

---

### 🧪 How to Use

#### 1. Run database and populate alerts

```bash
make rebuild # clean and build the database
make alerts  # let it run briefly to populate data, then stop it
```


Then stop with `Ctrl+C`.
```
make alerts
go run ./cmd/mock_alerts
2025/05/12 10:10:28.118378 Listening for user_subscription_alerts notifications...
2025/05/12 10:10:28.334115 created subscription_targets table in 218.025525ms
2025/05/12 10:10:40.121263 Starting generating mock data...
2025/05/12 10:10:40.190066 copied 50000 records to alerts_staging in 18.384618ms
2025/05/12 10:10:40.213798 copied 50000 records to alerts_staging in 17.285238ms
2025/05/12 10:10:40.224866 copied 21872 records to alerts_staging in 8.252248ms
2025/05/12 10:10:40.432146 merged 121872 alert (8168 kB) records in 207.240179ms
2025/05/12 10:10:40.432171 Processed 7617 flights in 311.919302ms
2025/05/12 10:10:40.856873 === Finished fetching of 1000 user_subscription's alerts in 420.080579ms. 2380.5 subscriptions per sec
^C2025/05/12 10:10:42.565031 Stopping ingestion...
2025/05/12 10:10:42.565134 context done, exiting IngestAlertData
make: *** [Makefile:62: alerts] Error 1

```

#### 2. Launch the listener

```bash
make listen
```

You’ll see output like:

```
Listening for subscription_condition_changes notifications...
Listening for user_subscription_alerts notifications...
```

#### 3. In another terminal, use `make psql`:

```bash
make psql
```

#### 4. Manually simulate a condition change:

```sql
UPDATE user_subscription_conditions SET is_on = false WHERE id = 8;
UPDATE user_subscription_conditions SET is_on = true WHERE id = 8;
```

This will trigger:

- A `NOTIFY` with payload:
  ```json
  { "id": 8, "is_on": true, "user_subscription_id": 1 }
  ```

- Console output from the listener:
  ```text
  go run ./cmd/listen_changes
  2025/05/12 10:00:12.114968 Listening for subscription_condition_changes notifications...
  2025/05/12 10:00:12.115192 Listening for user_subscription_alerts notifications...
  PUSH user_sub 1
  payload=[{"alert_id" : 22985, "condition_id" : 8, "target_id" : 3670, "target_type" : "destination_airport", "payload" : "{"helper": "mock"}", "updated_at" : "2025-05-12T09:59:56.468546+03:00", "is_on" : false}]
  PUSH user_sub 1
  payload=[{"alert_id" : 22985, "condition_id" : 8, "target_id" : 3670, "target_type" : "destination_airport", "payload" : "{"helper": "mock"}", "updated_at" : "2025-05-12T09:59:56.468546+03:00", "is_on" : true}]
  ```

Note: the same alert is pushed twice — first with `is_on: false`, then with `is_on: true` to reflect the condition toggle.

---

### 🔍 Example: Triggering an Alert Fan-Out via `alerts_staging`

In another test case, we simulate a change to an alert condition using the `alerts_staging` buffer:

```sql
SELECT count(*), count(distinct user_subscription_id)
FROM user_subscription_alerts
WHERE alert_id = 1 AND is_on = true;
```

```
 count | count 
-------+-------
    33 |    33
```

```sql
INSERT INTO alerts_staging VALUES (1, 257, false, '{test:true}', now());
CALL process_alert_staging();
```

This will emit a `NOTIFY` that triggers delivery to **33 user subscriptions**:

```text
=== ListenForSubscriptionUpdates Received notification: {"user_subscription_ids" : [42,815,91,344,58,...]}
PUSH user_sub 373
payload=[{"alert_id": 1, "condition_id": 1, "target_id": 257, "target_type": "flight", "is_on": false, "payload": "{"helper": "mock"}", ...}]
...
2025/05/12 10:03:25.278456 === Finished fetching of 33 user_subscription's alerts in 24.419799ms. 1351.4 subscriptions per sec
```

This demonstrates successful fan-out to all affected subscriptions with efficient batching and logging.
