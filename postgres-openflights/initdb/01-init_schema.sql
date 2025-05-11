-- =============
-- ENUM Types
-- =============

CREATE TYPE target_type AS ENUM ('source_airport', 'destination_airport', 'flight');
CREATE TYPE flight_status AS ENUM ('scheduled', 'departed', 'arrived', 'cancelled', 'delayed');

-- =============
-- Base Tables
-- =============

CREATE TABLE countries (
                           id SERIAL PRIMARY KEY,
                           name TEXT NOT NULL,
                           iso_code VARCHAR(2),
                           dafif_code VARCHAR(3)
);

CREATE TABLE airports (
                          id INTEGER PRIMARY KEY,
                          name TEXT,
                          city TEXT,
                          country TEXT,
                          iata VARCHAR(3),
                          icao VARCHAR(4),
                          latitude DOUBLE PRECISION,
                          longitude DOUBLE PRECISION,
                          altitude INTEGER,
                          timezone DOUBLE PRECISION,
                          dst CHAR(1),
                          tz_database_time_zone TEXT,
                          type TEXT,
                          source TEXT
);

CREATE TABLE airlines (
                          id INTEGER PRIMARY KEY,
                          name TEXT,
                          alias TEXT,
                          iata VARCHAR(10),
                          icao VARCHAR(10),
                          callsign TEXT,
                          country TEXT,
                          active CHAR(1)
);

CREATE TABLE planes (
                        id SERIAL PRIMARY KEY,
                        name TEXT,
                        iata VARCHAR(10),
                        icao VARCHAR(10)
);

CREATE TABLE routes (
                        id SERIAL PRIMARY KEY,
                        airline TEXT,
                        airline_id INTEGER,
                        source_airport TEXT,
                        source_airport_id INTEGER,
                        destination_airport TEXT,
                        destination_airport_id INTEGER,
                        codeshare TEXT,
                        stops INTEGER,
                        equipment TEXT
);

CREATE TABLE flights (
                         id SERIAL PRIMARY KEY,
                         route_id INTEGER NOT NULL REFERENCES routes(id),
                         airline_id INTEGER NOT NULL REFERENCES airlines(id),
                         flight_number TEXT NOT NULL,
                         source_airport_id INTEGER NOT NULL,
                         destination_airport_id INTEGER NOT NULL,
                         departure_time TIMESTAMPTZ NOT NULL,
                         arrival_time TIMESTAMPTZ NOT NULL,
                         status flight_status NOT NULL
);

-- =============
-- Condition Framework
-- =============

CREATE TABLE condition_templates (
                                     id SERIAL PRIMARY KEY,
                                     name TEXT NOT NULL UNIQUE,
                                     description TEXT NOT NULL,
                                     target_type target_type NOT NULL
);

CREATE TABLE conditions (
                            id SERIAL PRIMARY KEY,
                            template_id INT NOT NULL REFERENCES condition_templates(id),
                            threshold INT NOT NULL,
                            severity INT NOT NULL
);

CREATE INDEX idx_conditions_template_id ON conditions(template_id);

-- =============
-- Alerts
-- =============

CREATE TABLE alerts (
                        id SERIAL PRIMARY KEY,
                        condition_id INT NOT NULL REFERENCES conditions(id),
                        target_id INT NOT NULL,
                        is_on BOOL NOT NULL,
    received_at TIMESTAMPTZ NOT NULL,
    payload text NOT NULL,
                        updated_at TIMESTAMPTZ NOT NULL default now(),
                        UNIQUE (condition_id, target_id)
);
CREATE TABLESPACE ramdisk LOCATION '/ramdisk';

CREATE UNLOGGED TABLE alerts_staging (
                                condition_id INT,
                                target_id INT,
                                is_on BOOLEAN NOT NULL,
                                payload TEXT,
                                received_at TIMESTAMPTZ NOT NULL
) TABLESPACE ramdisk;

CREATE TABLE users(
                     id SERIAL PRIMARY KEY,
                     name TEXT NOT NULL,
                     created_at TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE subscriptions (
                               id INT PRIMARY KEY,
                               name TEXT NOT NULL,
                               view_name TEXT NOT NULL,
    start_update TIMESTAMPTZ,
    finish_update TIMESTAMPTZ
);

create table user_subscriptions
(
    id SERIAL PRIMARY KEY,
    user_id         INT NOT NULL references users (id),
    subscription_id INT NOT NULL REFERENCES subscriptions (id),
    unique (user_id, subscription_id),
    pushed_at     TIMESTAMPTZ NULL, -- when the subscription's alerts were pushed to the user
    alerts_triggered_at TIMESTAMPTZ NULL -- when the subscription's alerts were triggered
);

create table user_subscription_conditions
(
    id SERIAL PRIMARY KEY,
    user_subscription_id INT NOT NULL REFERENCES user_subscriptions (id),
    condition_id        INT NOT NULL references conditions (id),
    unique (user_subscription_id, condition_id),
    is_on              BOOL NOT NULL,
    last_changed_at TIMESTAMPTZ
);

-- ================================================
-- Function: notify_subscription_condition_change
-- --------------------------------
-- Purpose:
--   Sends a lightweight notification when a user's
--   subscription condition (`user_subscription_conditions.is_on`)
--   is updated.
--
-- Use Case:
--   When a user enables or disables a specific alert condition,
--   this trigger informs the backend in real-time, allowing it to:
--     - Reactively reload or clear active alerts
--     - Update internal state or caches
--     - Log user-initiated condition changes
--
-- Notification Channel:
--   'subscription_condition_changes'
--
-- Payload Example:
--   {
--     "user_subscription_condition_id": 123,
--     "is_on": true
--   }
-- ================================================
CREATE OR REPLACE FUNCTION notify_subscription_condition_change()
    RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
BEGIN
    -- Construct a JSON payload containing the ID and new `is_on` status
    payload := json_build_object(
            'user_subscription_condition_id', NEW.id,
            'user_subscription_id', NEW.user_subscription_id,
            'is_on', NEW.is_on
               );

    -- Notify the backend listener via PostgreSQL pub/sub
    PERFORM pg_notify('subscription_condition_changes', payload::text);

    -- Return the new row to complete the update
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger itself
CREATE TRIGGER trg_notify_subscription_condition_change
    AFTER UPDATE OF is_on ON user_subscription_conditions
    FOR EACH ROW
    WHEN (OLD.is_on IS DISTINCT FROM NEW.is_on)
EXECUTE FUNCTION notify_subscription_condition_change();

-- =============
-- Views
-- =============

CREATE OR REPLACE VIEW active_flights AS
SELECT * FROM flights
WHERE status IN ('scheduled', 'departed', 'delayed')
  AND arrival_time > now();

CREATE OR REPLACE VIEW inactive_flights AS
SELECT * FROM flights
WHERE NOT (status IN ('scheduled', 'departed', 'delayed') AND arrival_time > now());

-- Create function to truncate and regenerate flights
CREATE OR REPLACE FUNCTION regenerate_flights()
    RETURNS INTEGER AS $$
DECLARE
    inserted_count INTEGER := 0;
    routes_count INTEGER := 0;
    airlines_count INTEGER := 0;
    joinable_routes_count INTEGER := 0;
BEGIN
    TRUNCATE TABLE flights CASCADE;

    INSERT INTO flights (
        route_id,
        airline_id,
        flight_number,
        source_airport_id,
        destination_airport_id,
        departure_time,
        arrival_time,
        status
    )
    SELECT
        r.id,
        r.airline_id,
        COALESCE(a.iata, a.icao, 'XX') || LPAD(r.id::text, 4, '0') AS flight_number,
        r.source_airport_id,
        r.destination_airport_id,
        NOW() + (r.id % 12) * interval '1 hour',
        NOW() + ((r.id % 12) + 2) * interval '1 hour',
        CASE
            WHEN r.id % 15 = 0 THEN 'cancelled'
            WHEN r.id % 7 = 0 THEN 'delayed'
            WHEN r.id % 5 = 0 THEN 'departed'
            ELSE 'scheduled'
            END::flight_status
    FROM routes r
             JOIN airlines a ON r.airline_id = a.id
    WHERE r.airline_id IS NOT NULL;

    GET DIAGNOSTICS inserted_count = ROW_COUNT;

    IF inserted_count = 0 THEN
        SELECT COUNT(*) INTO routes_count FROM routes;
        SELECT COUNT(*) INTO airlines_count FROM airlines;
        SELECT COUNT(*) INTO joinable_routes_count
        FROM routes r
                 JOIN airlines a ON r.airline_id = a.id
        WHERE r.airline_id IS NOT NULL;

        RAISE WARNING 'No flights inserted. Diagnostics:';
        RAISE WARNING ' - Total routes: %', routes_count;
        RAISE WARNING ' - Total airlines: %', airlines_count;
        RAISE WARNING ' - Joinable routes with airline_id: %', joinable_routes_count;
        RAISE WARNING 'Potential issues: routes.airline_id may not match any airlines.id, or airline_id is null';
    END IF;

    RETURN inserted_count;
END;
$$ LANGUAGE plpgsql;

0-- ================================================
-- Procedure: process_alert_staging
-- --------------------------------
-- Purpose:
--   - Efficiently process and merge alert condition changes
--     from the high-speed alerts_staging table.
--   - Only updates the 'alerts' table when 'is_on' status
--     has changed.
--   - Identifies and notifies affected user subscriptions.
--   - Clears the staging table after processing.
-- --------------------------------
-- Performance Features:
--   - Deduplication based on (condition_id, target_id)
--   - Conflict resolution via conditional UPSERT
--   - Operates entirely in-memory until final merge
-- ================================================
CREATE OR REPLACE PROCEDURE process_alert_staging()
    LANGUAGE plpgsql
AS $$
DECLARE
    sub_ids INT[];  -- List of affected user_subscription IDs
BEGIN
    -- Step 1: Deduplicate incoming alert updates
    -- Keep only the most recent (latest received_at) update
    -- for each (condition_id, target_id) combination
    WITH deduped AS (
        SELECT DISTINCT ON (condition_id, target_id) *
        FROM alerts_staging
        ORDER BY condition_id, target_id, received_at DESC
    ),

         -- Step 2: UPSERT into main alerts table
         -- Only perform update if the 'is_on' state has changed
         -- to avoid unnecessary writes and reduce database churn
         upserted AS (
             INSERT INTO alerts (condition_id, target_id, is_on, payload, received_at, updated_at)
                 SELECT
                     s.condition_id,
                     s.target_id,
                     s.is_on,
                     s.payload,
                     s.received_at,
                     now()
                 FROM deduped s
                          JOIN conditions c ON c.id = s.condition_id
                          JOIN condition_templates ct ON ct.id = c.template_id
                 ON CONFLICT (condition_id, target_id) DO UPDATE
                     SET
                         is_on = EXCLUDED.is_on,
                         updated_at = now(),
                         received_at = EXCLUDED.received_at
                     WHERE alerts.is_on IS DISTINCT FROM EXCLUDED.is_on
                 RETURNING alerts.id, alerts.condition_id, alerts.target_id
         )

    -- Step 3: Identify affected user subscriptions
    -- Only include subscriptions where the user actively listens (is_on = true)
    SELECT ARRAY(
                   SELECT DISTINCT usc.user_subscription_id
                   FROM upserted u
                            JOIN user_subscription_conditions usc
                                 ON usc.condition_id = u.condition_id
                   WHERE usc.is_on = true
           ) INTO sub_ids;

    -- Step 4: Update alerts_triggered_at to mark activity
    UPDATE user_subscriptions us
    SET alerts_triggered_at = now()
    WHERE us.id = ANY(sub_ids);

    -- Step 5: Clean up staging buffer
    -- Truncate RAM-based alerts_staging to reclaim memory
    TRUNCATE alerts_staging;

    -- Step 6: Send single NOTIFY payload with all affected subscription IDs
    IF array_length(sub_ids, 1) > 0 THEN
        PERFORM pg_notify(
                'user_subscription_alerts',
                json_build_object(
                        'user_subscription_ids', sub_ids
                )::text
                );
    END IF;
END;
$$;

CREATE TABLE subscription_targets(
                                     subscription_id INT NOT NULL REFERENCES subscriptions (id),
                                     target_id INT NOT NULL,
                                     target_type target_type NOT NULL,
                                     UNIQUE (subscription_id, target_id, target_type)
);

-- ============================================================================
-- Procedure: recreate_subscription_targets
-- Description:
--     This procedure rebuilds the 'subscription_targets' table by iterating
--     over all user subscriptions and extracting related target IDs (flights,
--     source airports, destination airports) from each subscription view.
--
--     For each subscription:
--         - The corresponding view is dynamically queried.
--         - All distinct flight_id, source_airport_id, and destination_airport_id
--           values are inserted into the 'subscription_targets' table along with
--           the appropriate target_type and subscription_id.
--
--     NOTE:
--         This procedure must be called whenever:
--           1. A user subscription is created, updated, or deleted.
--           2. The list of active flights (used in subscription views) changes.
--
--     It ensures that the 'subscription_targets' table always contains an
--     up-to-date mapping of subscriptions to the targets they are monitoring.
-- ============================================================================
CREATE OR REPLACE PROCEDURE recreate_subscription_targets()
    LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    dyn_sql TEXT;
BEGIN
    -- Step 1: Clear existing data
    TRUNCATE subscription_targets;

    -- Step 2: Iterate over each subscription
    FOR rec IN SELECT id, view_name FROM subscriptions LOOP
            -- Step 3: Construct dynamic SQL for each subscription view
            dyn_sql := format($fmt$
            INSERT INTO subscription_targets(subscription_id, target_id, target_type)
            SELECT DISTINCT %s, flight_id, 'flight'::target_type FROM %I
            WHERE flight_id IS NOT NULL
            UNION ALL
            SELECT DISTINCT %s, source_airport_id, 'source_airport'::target_type FROM %I
            WHERE source_airport_id IS NOT NULL
            UNION ALL
            SELECT DISTINCT %s, destination_airport_id, 'destination_airport'::target_type FROM %I
            WHERE destination_airport_id IS NOT NULL;
        $fmt$, rec.id, rec.view_name, rec.id, rec.view_name, rec.id, rec.view_name);
            -- Step 4: insert targets from current subscription into subscription_targets
            EXECUTE dyn_sql;
        END LOOP;
END;
$$;

CREATE OR REPLACE VIEW user_subscription_alerts AS
SELECT
    us.id AS user_subscription_id,
    usc.condition_id,
    a.id AS alert_id,
    a.target_id,
    ct.target_type,
    a.is_on,
    a.payload,
    a.updated_at,
    us.pushed_at,
    usc.is_on usc_is_on
FROM alerts a
         JOIN conditions c ON a.condition_id = c.id
         JOIN condition_templates ct ON ct.id = c.template_id
         JOIN user_subscription_conditions usc ON usc.condition_id = a.condition_id
         JOIN user_subscriptions us ON us.id = usc.user_subscription_id
         JOIN subscription_targets st ON st.target_id = a.target_id AND st.target_type = ct.target_type AND st.subscription_id = us.subscription_id;

CREATE OR REPLACE FUNCTION get_alerts_json(user_sub_id INT)
    RETURNS JSON AS $$
DECLARE
    alerts JSON;
BEGIN
    SELECT json_agg(json_build_object(
            'alert_id', alert_id,
            'condition_id', condition_id,
            'target_id', target_id,
            'target_type', target_type,
            'is_on', is_on,
            'payload', payload,
            'updated_at', updated_at
                    ))
    INTO alerts
    FROM user_subscription_alerts
    WHERE user_subscription_id = user_sub_id
      and usc_is_on = true  AND updated_at > COALESCE(pushed_at, '2000-01-01');

    IF alerts IS NULL THEN
        RETURN '[]'::json;
    END IF;

    -- Update pushed_at only if there are alerts
    UPDATE user_subscriptions
    SET pushed_at = now()
    WHERE id = user_sub_id;

    RETURN alerts;
END;
$$ LANGUAGE plpgsql;
