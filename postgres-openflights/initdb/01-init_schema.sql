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

create table user_subscription_push
(
    user_subscription_id INT NOT NULL REFERENCES user_subscriptions (id),
    alerts_triggered_at TIMESTAMPTZ NULL, -- when the subscription's alerts were triggered
    alerts_pushed_at TIMESTAMPTZ NULL -- when the subscription's alerts were pushed to the user
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

CREATE OR REPLACE FUNCTION notify_subscription_condition_change()
    RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
BEGIN
    -- Construct a simple JSON payload with the ID
    payload := json_build_object(
            'user_subscription_condition_id', NEW.id,
            'is_on', NEW.is_on
               );

    PERFORM pg_notify('subscription_condition_changes', payload::text);

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

CREATE TABLE subscription_targets(
    subscription_id INT NOT NULL REFERENCES subscriptions (id),
    target_id INT NOT NULL,
    target_type target_type NOT NULL,
    UNIQUE (subscription_id, target_id, target_type)
);

CREATE OR REPLACE VIEW user_subscription_new_alerts AS
SELECT
    us.id AS user_subscription_id,
    usc.condition_id,
    a.id AS alert_id,
    a.target_id,
    ct.target_type,
    a.is_on,
    a.payload,
    a.updated_at,
    us.pushed_at
FROM alerts a
         JOIN conditions c ON a.condition_id = c.id
         JOIN condition_templates ct ON ct.id = c.template_id
         JOIN user_subscription_conditions usc ON usc.condition_id = a.condition_id
         JOIN user_subscriptions us ON us.id = usc.user_subscription_id
         JOIN subscription_targets st ON st.target_id = a.target_id AND st.target_type = ct.target_type AND st.subscription_id = us.subscription_id
WHERE usc.is_on = true
  AND a.updated_at > COALESCE(us.pushed_at, '2000-01-01');


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

CREATE OR REPLACE FUNCTION schedule_next_day_flights()
    RETURNS INTEGER AS $$
DECLARE
    scheduled_count INTEGER;
BEGIN
    WITH new_flights AS (
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
                f.route_id,
                f.airline_id,
                f.flight_number || '_D' || TO_CHAR(NOW() + INTERVAL '1 day', 'DD'),
                f.source_airport_id,
                f.destination_airport_id,
                f.departure_time + INTERVAL '1 day',
                f.arrival_time + INTERVAL '1 day',
                'scheduled'
            FROM flights f
            WHERE f.status IN ('arrived', 'departed')
              AND f.departure_time::date = CURRENT_DATE
              AND NOT EXISTS (
                SELECT 1 FROM flights fx
                WHERE fx.route_id = f.route_id
                  AND fx.departure_time::date = CURRENT_DATE + INTERVAL '1 day'
            )
            RETURNING *
    )
    SELECT COUNT(*) INTO scheduled_count FROM new_flights;

    RETURN scheduled_count;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE process_alert_staging()
    LANGUAGE plpgsql
AS $$
DECLARE
    sub_ids INT[];  -- to store all affected subscription IDs
BEGIN
    -- Step 1: Deduplicate and insert/update alerts, capturing changed ones
    WITH deduped AS (
        SELECT DISTINCT ON (condition_id, target_id) *
        FROM alerts_staging
        ORDER BY condition_id, target_id, received_at DESC
    ),
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

    -- Step 2: Collect affected subscription IDs into sub_ids array
    SELECT ARRAY(
                   SELECT DISTINCT usc.user_subscription_id
                   FROM upserted u
                            JOIN user_subscription_conditions usc ON usc.condition_id = u.condition_id
           )
    INTO sub_ids;

    -- Step 3: Update alerts_triggered_at for affected subscriptions
    UPDATE user_subscriptions us
    SET alerts_triggered_at = now()
    WHERE us.id = ANY(sub_ids);

    -- Step 4: Send notification as one JSON array
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
    FROM user_subscription_new_alerts
    WHERE user_subscription_id = user_sub_id;

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
