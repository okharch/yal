IMAGE_NAME=postgres-openflights
CONTAINER_NAME=postgres-openflights-db
POSTGRES_PASSWORD=mysecretpassword
PORT=5433

# Build Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Run the container
run:
	docker run --name $(CONTAINER_NAME) \
		-e POSTGRES_PASSWORD=$(POSTGRES_PASSWORD) \
		-p $(PORT):5432 \
		-d $(IMAGE_NAME)

# Stop and remove container
clean:
	docker rm -f $(CONTAINER_NAME) || true

# Rebuild from scratch
rebuild: clean build run

# Show logs
logs:
	docker logs -f $(CONTAINER_NAME)

# Enter psql shell (requires psql installed locally)
psql:
	psql -h localhost -p $(PORT) -U postgres

# Show container status
status:
	docker ps -f name=$(CONTAINER_NAME)
