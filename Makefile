# 📦 Variables
IMAGE_NAME = postgres-openflights
CONTAINER_NAME = postgres-openflights
POSTGRES_PORT = 5433
POSTGRES_DIR = postgres-openflights
IMPORT_DIR = $(POSTGRES_DIR)/import
IMPORT_FILES = airports.dat airlines.dat routes.dat planes.dat countries.dat
SUBSCRIPTIONS_DIR = ./cmd/mock_subscriptions

.PHONY: build run clean rebuild psql logs shell status go-run-subscriptions alerts listen import wait-for-db

## 🔨 Build the PostgreSQL Docker image
build:
	cd $(POSTGRES_DIR) && docker build -t $(IMAGE_NAME) .

## 🚀 Run the PostgreSQL container with tmpfs ramdisk
run:
	docker run -d \
		--name $(CONTAINER_NAME) \
		-p $(POSTGRES_PORT):5432 \
		-e POSTGRES_USER=postgres \
		-e POSTGRES_DB=postgres \
		-e POSTGRES_HOST_AUTH_METHOD=trust \
		-e TZ=$(shell cat /etc/timezone) \
		-v /etc/localtime:/etc/localtime:ro \
		--tmpfs /ramdisk:rw,size=512m,uid=999,gid=999 \
		$(IMAGE_NAME)

## 🧼 Stop and remove the container
clean:
	docker rm -f $(CONTAINER_NAME) || true

## 🔁 Full cycle: clean, build, run, and start subscriptions
rebuild: import clean build run wait-for-db go-run-subscriptions

## ⏳ Wait until PostgreSQL is ready to accept connections
wait-for-db:
	@echo "⏳ Waiting for PostgreSQL to be ready..."
	@until pg_isready -h localhost -p $(POSTGRES_PORT) > /dev/null 2>&1; do \
		sleep 0.5; \
	done
	@echo "✅ PostgreSQL is ready."

## 📜 Tail container logs
logs:
	docker logs -f $(CONTAINER_NAME)

## 🖥️ Open a shell inside the running container
shell:
	docker exec -it $(CONTAINER_NAME) bash

## 📊 Check container status
status:
	docker ps -f name=$(CONTAINER_NAME)

## 🎯 Run the mock subscriptions Go service
go-run-subscriptions:
	go run $(SUBSCRIPTIONS_DIR)

## 🧪 Ingest mock alerts into the database
alerts:
	go run ./cmd/mock_alerts

## 👂 Listen to database change notifications
listen:
	go run ./cmd/listen_changes

## ⬇ Import OpenFlights data files (if missing)
import: $(addprefix $(IMPORT_DIR)/, $(IMPORT_FILES))

$(IMPORT_DIR)/%.dat:
	@mkdir -p $(IMPORT_DIR)
	@echo "⬇ Downloading $*.dat"
	curl -s -o $@ https://raw.githubusercontent.com/jpatokal/openflights/master/data/$*.dat

## 🐘 Connect to PostgreSQL using psql inside the container
psql:
	docker exec -it $(CONTAINER_NAME) psql -U postgres -d postgres
