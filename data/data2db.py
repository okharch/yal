#!/usr/bin/env python3

import os
import pandas as pd
from sqlalchemy import create_engine
from dotenv import load_dotenv

# Load .env from parent directory
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))

# Get database connection string
db_url = os.getenv("DATABASE_URL")
if not db_url:
    raise RuntimeError("DATABASE_URL not found in .env")

# Connect to database
engine = create_engine(db_url)

# Define structure for each file
file_definitions = {
    "airports.dat": {
        "columns": [
            "id", "name", "city", "country", "iata", "icao",
            "latitude", "longitude", "altitude", "timezone",
            "dst", "tz_database_time_zone", "type", "source"
        ],
        "table": "airports"
    },
    "airlines.dat": {
        "columns": [
            "id", "name", "alias", "iata", "icao",
            "callsign", "country", "active"
        ],
        "table": "airlines"
    },
    "routes.dat": {
        "columns": [
            "airline", "airline_id", "source_airport", "source_airport_id",
            "destination_airport", "destination_airport_id",
            "codeshare", "stops", "equipment"
        ],
        "table": "routes"
    },
    "planes.dat": {
        "columns": ["name", "iata", "icao"],
        "table": "planes"
    },
    "countries.dat": {
        "columns": ["name", "iso_code", "dafif_code"],
        "table": "countries"
    }
}

# Import each file
for filename, info in file_definitions.items():
    if not os.path.exists(filename):
        print(f"⚠️  File not found: {filename}, skipping.")
        continue

    print(f"📥 Importing {filename} into table {info['table']}...")
    df = pd.read_csv(filename, header=None, names=info["columns"], na_values="\\N")
    df.to_sql(info["table"], engine, if_exists="replace", index=False)

print("✅ All files imported successfully.")

