
REGISTRY_LOCAL_CONTAINER_CACHE ?= $(CURDIR)/.containers/registry/data

REGISTRIES_DATA ?= \
  public \
  private \
  cache

up:
	@echo "Starting registry containers..."
	@mkdir -p $(REGISTRIES_DATA:%=$(REGISTRY_LOCAL_CONTAINER_CACHE)/%)
	@docker compose up -d
.PHONY: up

down:
	@echo "Stopping registry containers..."
	@mkdir -p $(REGISTRIES_DATA:%=$(REGISTRY_LOCAL_CONTAINER_CACHE)/%)
	@docker compose down
.PHONY: down

logs:
	@echo "Logs for registry containers:"
	@mkdir -p $(REGISTRIES_DATA:%=$(REGISTRY_LOCAL_CONTAINER_CACHE)/%)
	@docker compose logs
.PHONY: logs

logs-f:
	@echo "Logs follow for registry containers:"
	@mkdir -p $(REGISTRIES_DATA:%=$(REGISTRY_LOCAL_CONTAINER_CACHE)/%)
	@docker compose logs --follow
.PHONY: logs-f

ui:
	@echo "Starting registry UI..."
	@docker compose up -d registry-ui
.PHONY: ui

ui-down:
	@echo "Stopping registry UI..."
	@docker compose down registry-ui
.PHONY: ui-down