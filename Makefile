IMAGE   := going-fishing:latest
BINARY  := bin/ringbuffer

COMPOSE := podman-compose

.PHONY: all build image up up-arc down logs test clean

all: build

## build  – compile the Go ring buffer locally
build: $(BINARY)

$(BINARY): go.mod ringbuffer/main.go
	go build -o $@ ./ringbuffer/...

## image  – build the container image with podman
image: Containerfile
	podman build -t $(IMAGE) -f Containerfile .

## up     – start core services (versitygw + ringbuffer + setup + ingest + pequod)
up: image
	mkdir -p data/s3 data/iam
	@# Copy DuckDB extensions from our image so pequod can load them without internet access
	mkdir -p data/duck-extensions
	podman run --rm -v "$$(pwd)/data/duck-extensions:/out" $(IMAGE) \
		sh -c 'cp /root/.duckdb/extensions/v1.5.2/linux_amd64/*.duckdb_extension* /out/'
	$(COMPOSE) up -d

## up-arc – start core services plus the Arc hot-tier
up-arc: image
	mkdir -p data/s3 data/iam
	mkdir -p data/duck-extensions
	podman run --rm -v "$$(pwd)/data/duck-extensions:/out" $(IMAGE) \
		sh -c 'cp /root/.duckdb/extensions/v1.5.2/linux_amd64/*.duckdb_extension* /out/'
	$(COMPOSE) --profile arc up -d

## down   – stop and remove containers (data volume preserved)
down:
	$(COMPOSE) down

## logs   – tail all service logs
logs:
	$(COMPOSE) logs -f

## compact – run DuckLake compaction once (merge files, expire snapshots)
compact:
	podman run --rm \
		-v "$$(pwd)/data:/app/data" \
		-e VGW_ENDPOINT=versitygw:9000 \
		-e VGW_ACCESS_KEY=demo \
		-e VGW_SECRET_KEY=demoSecret \
		-e DUCKLAKE_CATALOG=data/catalog.db \
		-e DUCKLAKE_DATA_PATH=s3://iot-lake/data/ \
		--network going-fishing_net \
		$(IMAGE) ./compact.sh --once

## test   – run the end-to-end test suite against a local build
test: build
	bash test.sh

## shell  – open a shell in a one-off container (useful for ad-hoc queries)
shell: image
	podman run --rm -it \
		-v "$$(pwd)/data:/app/data" \
		-e VGW_ENDPOINT=versitygw:9000 \
		--network going-fishing_net \
		$(IMAGE) sh

## clean  – remove binary, image, generated data, and named volumes
clean: down
	rm -f $(BINARY)
	podman rmi $(IMAGE) 2>/dev/null || true
	podman volume rm going-fishing_data 2>/dev/null || true
	rm -rf data/

help:
	@grep -E '^## ' Makefile | sed 's/## /  make /'
