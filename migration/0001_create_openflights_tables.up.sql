CREATE TABLE airports (
                          id SERIAL PRIMARY KEY,
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
                          id SERIAL PRIMARY KEY,
                          name TEXT,
                          alias TEXT,
                          iata VARCHAR(2),
                          icao VARCHAR(3),
                          callsign TEXT,
                          country TEXT,
                          active CHAR(1)
);

CREATE TABLE routes (
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
                        name TEXT,
                        iata VARCHAR(3),
                        icao VARCHAR(4)
);

CREATE TABLE countries (
                           name TEXT,
                           iso_code VARCHAR(2),
                           dafif_code VARCHAR(3)
);
