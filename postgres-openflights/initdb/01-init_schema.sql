-- =============
-- ENUM Types
-- =============

CREATE TYPE target_type AS ENUM ('airport', 'flight');
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

CREATE TABLE alert_conditions (
                                  id SERIAL PRIMARY KEY,
                                  condition_id INT NOT NULL REFERENCES conditions(id),
                                  target_id INT NOT NULL, -- ID of flight or airport
                                  value INT NOT NULL,
            received_at TIMESTAMPTZ not null,
                                  created_at  TIMESTAMPTZ DEFAULT now() ,
                                  processed_at TIMESTAMPTZ
);

CREATE TABLE alerts (
                        id SERIAL PRIMARY KEY,
                        condition_id INT NOT NULL REFERENCES conditions(id),
                        target_id INT NOT NULL,
                        alert_condition_id INT NOT NULL REFERENCES alert_conditions(id),
                        is_on BOOL NOT NULL,
                        updated_at TIMESTAMPTZ NOT NULL default now(),
                        UNIQUE (condition_id, target_id)
);

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

-- =============
-- Trigger Function
-- =============

CREATE OR REPLACE FUNCTION process_alert_condition()
    RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO alerts (condition_id, target_id, alert_condition_id, is_on)
    SELECT
        NEW.condition_id,
        NEW.target_id,
        NEW.id,
        (NEW.value >= c.threshold)
    FROM conditions c
         JOIN condition_templates ct ON ct.id = c.template_id
         LEFT JOIN alerts a ON a.condition_id = c.id AND a.target_id = NEW.target_id
    WHERE c.id = NEW.condition_id
      AND (
        a.id IS NULL
            OR a.is_on IS DISTINCT FROM (NEW.value >= c.threshold)
        )
    ON CONFLICT (condition_id, target_id) DO UPDATE
        SET
            alert_condition_id = EXCLUDED.alert_condition_id,
            is_on = EXCLUDED.is_on,
            updated_at = clock_timestamp();

    UPDATE alert_conditions
    SET processed_at = clock_timestamp()
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_process_alert_condition
    AFTER INSERT ON alert_conditions
    FOR EACH ROW
EXECUTE FUNCTION process_alert_condition();

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
    user_id         INT NOT NULL,
    subscription_id INT NOT NULL REFERENCES subscriptions (id),
    updated_at     TIMESTAMPTZ DEFAULT now() -- set when all alerts triggers processed according to this data
);

