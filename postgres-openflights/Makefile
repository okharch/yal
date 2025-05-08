# Variables
IMAGE_NAME=postgres-openflights
CONTAINER_NAME=postgres-openflights
POSTGRES_PORT=5433
SUBSCRIPTIONS_DIR=../cmd/mock_subscriptions

.PHONY: build run clean rebuild psql logs shell status go-run-subscriptions ingest

## 🔧 Docker build & run
build:
	docker build -t $(IMAGE_NAME) .

run:
	docker run -d \
		--name $(CONTAINER_NAME) \
		-p $(POSTGRES_PORT):5432 \
		-e POSTGRES_USER=postgres \
		-e POSTGRES_DB=postgres \
		-e POSTGRES_HOST_AUTH_METHOD=trust \
		-e TZ=$(shell cat /etc/timezone) \
		-v /etc/localtime:/etc/localtime:ro \
		$(IMAGE_NAME)

clean:
	docker rm -f $(CONTAINER_NAME) || true

## 🔁 Full rebuild and launch subscriptions
rebuild: clean build run wait-for-db go-run-subscriptions

## 💻 Postgres & container tools
psql:
	psql -h localhost -p $(POSTGRES_PORT) -U postgres -d postgres

logs:
	docker logs -f $(CONTAINER_NAME)
wait-for-db:
	@echo "⏳ Waiting for PostgreSQL to be ready..."
	@until pg_isready -h localhost -p $(POSTGRES_PORT) > /dev/null 2>&1; do \
		sleep 0.5; \
	done
	@echo "✅ PostgreSQL is ready."


shell:
	docker exec -it $(CONTAINER_NAME) bash

status:
	docker ps -f name=$(CONTAINER_NAME)

## 🧪 Run mock subscriptions service
go-run-subscriptions:
	go run $(SUBSCRIPTIONS_DIR)

ingest:
	go run ../cmd/mock_ingest/mock_ingest.go