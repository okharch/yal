postgres-openflights

# postgres-openflights

A self-contained PostgreSQL Docker image preloaded with OpenFlights airline, airport, and route data. Designed to support development and simulation of aviation-related alerting systems, it includes utilities to generate and schedule synthetic flight activity for testing purposes.

## Features

*   Based on official `postgres:17` image
*   Automatically creates a new `openflights` database on container startup
*   Imports OpenFlights datasets (`.dat` files) into structured PostgreSQL tables
*   Preloads synthetic flight data using PL/pgSQL functions
*   Includes a `Makefile` to simplify common tasks (build, run, clean, logs, psql)
*   Supports continuous simulation by scheduling next-day flights

## Table Overview

*   `countries`, `airports`, `airlines`, `routes`, `planes`: Core OpenFlights data
*   `flights`: Synthetic table populated by `regenerate_flights()` and `schedule_next_day_flights()` functions

## Folder Structure

postgres-openflights/
├── Dockerfile
├── Makefile
├── import/
│   ├── airlines.dat
│   ├── airports.dat
│   ├── routes.dat
│   ├── planes.dat
│   └── countries.dat
└── 01\_init\_openflights.sql

## Usage

### Build the Docker image

```
make build
```

### Run the container

```
make run
```

This will:

*   Start PostgreSQL on port `5433` (host)
*   Create the `openflights` database
*   Load all `.dat` files from `/import/` into respective tables
*   Populate the `flights` table with simulated data

### Rebuild from scratch

```
make rebuild
```

### View logs

```
make logs
```

### Stop and remove the container

```
make clean
```

### Access PostgreSQL with `psql` (requires local psql client)

```
make psql
```

## Connection Details

*   **User:** `postgres`
*   **Password:** `mysecretpassword`
*   **Database:** `openflights`
*   **Port:** `5433`

## Simulated Flights

SQL functions available for generating and scheduling flights:

*   `regenerate_flights()`
*   `schedule_next_day_flights()`

```
SELECT regenerate_flights();
SELECT schedule_next_day_flights();
```

## Data Source

All `.dat` files come from the [OpenFlights project](https://github.com/jpatokal/openflights/tree/master/data).

## License

OpenFlights data is licensed under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/).