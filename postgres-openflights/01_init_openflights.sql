    -- Create the database
CREATE DATABASE openflights;
\connect openflights

-- Create tables
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

CREATE TABLE planes (
                        id SERIAL PRIMARY KEY,
                        name TEXT,
                        iata VARCHAR(10),
                        icao VARCHAR(10)
);

-- Import data from /import
COPY countries(name, iso_code, dafif_code)
    FROM '/import/countries.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

COPY airports(id, name, city, country, iata, icao, latitude, longitude, altitude, timezone, dst, tz_database_time_zone, type, source)
    FROM '/import/airports.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

COPY airlines(id, name, alias, iata, icao, callsign, country, active)
    FROM '/import/airlines.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

COPY planes(name, iata, icao)
    FROM '/import/planes.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

COPY routes(airline, airline_id, source_airport, source_airport_id, destination_airport, destination_airport_id, codeshare, stops, equipment)
    FROM '/import/routes.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

    -- cleanup routes
    DELETE FROM routes
    WHERE destination_airport_id NOT IN (
        SELECT id FROM airports
    );
    DELETE FROM routes
    WHERE source_airport_id NOT IN (
      SELECT id FROM airports
    );

-- flights
-- Cleanup orphaned routes
    DELETE FROM routes
    WHERE destination_airport_id NOT IN (SELECT id FROM airports);

    DELETE FROM routes
    WHERE source_airport_id NOT IN (SELECT id FROM airports);

    DELETE FROM routes
    WHERE airline_id NOT IN (SELECT id FROM airlines);

-- Drop flights table if exists
    DROP TABLE IF EXISTS flights CASCADE;

-- Create flights table
    CREATE TABLE flights (
                             id SERIAL PRIMARY KEY,
                             route_id INTEGER NOT NULL REFERENCES routes(id),
                             airline_id INTEGER NOT NULL REFERENCES airlines(id),
                             flight_number TEXT NOT NULL,
                             departure_time TIMESTAMP NOT NULL,
                             arrival_time TIMESTAMP NOT NULL,
                             status TEXT NOT NULL CHECK (status IN ('scheduled', 'departed', 'arrived', 'cancelled', 'delayed'))
    );

    -- Create function to truncate and regenerate flights
    CREATE OR REPLACE FUNCTION regenerate_flights()
        RETURNS void AS $$
    BEGIN
        TRUNCATE TABLE flights RESTART IDENTITY;

        INSERT INTO flights (route_id, airline_id, flight_number, departure_time, arrival_time, status)
        SELECT
            r.id,
            r.airline_id,
            COALESCE(a.iata, a.icao, 'XX') || LPAD(r.id::text, 4, '0') AS flight_number,
            NOW() + (r.id % 12) * interval '1 hour',
            NOW() + ((r.id % 12) + 2) * interval '1 hour',
            CASE
                WHEN r.id % 15 = 0 THEN 'cancelled'
                WHEN r.id % 7 = 0 THEN 'delayed'
                WHEN r.id % 5 = 0 THEN 'departed'
                ELSE 'scheduled'
                END
        FROM routes r
                 JOIN airlines a ON r.airline_id = a.id
        WHERE r.airline_id IS NOT NULL;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION schedule_next_day_flights()
        RETURNS INTEGER AS $$
    DECLARE
        scheduled_count INTEGER;
    BEGIN
        WITH new_flights AS (
            INSERT INTO flights (route_id, airline_id, flight_number, departure_time, arrival_time, status)
                SELECT
                    f.route_id,
                    f.airline_id,
                    f.flight_number || '_D' || TO_CHAR(NOW() + INTERVAL '1 day', 'DD'), -- e.g. LH0743_D02
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

    select regenerate_flights();
