-- countries.dat: no ID in file → specify columns
COPY countries(name, iso_code, dafif_code)
    FROM '/import/countries.dat'
    WITH (FORMAT csv, NULL '', QUOTE '"');

-- airlines.dat: includes all columns (including ID) → no need to specify
COPY airlines
    FROM '/import/airlines.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

-- airports.dat: includes all columns (including ID) → no need to specify
COPY airports
    FROM '/import/airports.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

-- planes.dat: no ID in file → specify columns
COPY planes(name, iata, icao)
    FROM '/import/planes.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

-- routes.dat: no ID in file → specify columns
COPY routes(airline, airline_id, source_airport, source_airport_id,
            destination_airport, destination_airport_id, codeshare, stops, equipment)
    FROM '/import/routes.dat'
    WITH (FORMAT csv, NULL '\N', QUOTE '"');

delete from routes where destination_airport_id is null or source_airport_id is null;

-- Run synthetic data generation after load
SELECT regenerate_flights();
