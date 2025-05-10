FROM postgres:latest

LABEL maintainer="okharch@gmail.com"
LABEL description="PostgreSQL image with OpenFlights tables and data preloaded in /import"

# Create /import and copy data files
RUN mkdir -p /import
COPY import/*.dat /import/

# Run init SQL script on first container startup
COPY initdb/*.sql /docker-entrypoint-initdb.d/
