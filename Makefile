.PHONY: help all generate build build-cli check test coverage cover fmt vet lint lint-ci install clean

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

APP_NAME    = sunspecctl
APP_SRC     = ./cmd/sunspecctl
ARCHS       = linux/amd64 linux/arm64 linux/arm/v7 darwin/amd64 darwin/arm64
RELEASE_DIR = release

all: check build ## Run all checks and build library + CLI

generate: ## Regenerate registry from SunSpec JSON models
	@echo "Generating registry/models_gen.go"
	@go run ./internal/gen

sync: ## Sync SunSpec JSON models from upstream and regenerate
	@echo "Syncing SunSpec models"
	@./sync-models.sh
	@$(MAKE) generate

check: fmt vet lint test ## Run all checks (format, vet, lint, test)

test: ## Run unit and integration tests with race detector
	@echo "Running tests (race detector)"
	@go test -count=1 -race ./...

coverage: ## Run tests with coverage (writes coverage.out)
	@echo "Running tests with coverage"
	@go test -count=1 -race -coverprofile=coverage.out -covermode=atomic ./...

cover: coverage ## Open coverage report in browser
	@echo "Opening coverage report in browser"
	@go tool cover -html=coverage.out

fmt: ## Format Go code with gofmt
	@echo "Running gofmt"
	@gofmt -w .

vet: ## Run go vet on all packages
	@echo "Running go vet"
	@go vet ./...

lint: ## Run staticcheck
	@echo "Running staticcheck"
	@staticcheck ./...

lint-ci: ## Run golangci-lint (uses .golangci.yml)
	@echo "Running golangci-lint"
	@golangci-lint run ./...

build: generate ## Build the library and CLI
	@echo "Building library"
	@go build ./...
	@echo "Building $(APP_NAME)"
	@go build -o $(APP_NAME) $(APP_SRC)

build-cli: ## Build CLI only (skip generate)
	@echo "Building $(APP_NAME)"
	@go build -o $(APP_NAME) $(APP_SRC)

build-all: generate ## Build CLI for all architectures
	@mkdir -p $(RELEASE_DIR)
	@for arch in $(ARCHS); do \
		os=$${arch%%/*}; \
		rest=$${arch#*/}; \
		cpu=$${rest%%/*}; \
		variant=$${rest#*/}; \
		if [ "$$cpu" = "arm" ] && [ "$$variant" = "v7" ]; then \
			echo "Building $(APP_NAME)-$$os-armv7..."; \
			GOOS=$$os GOARCH=$$cpu GOARM=7 go build -o $(RELEASE_DIR)/$(APP_NAME)-$$os-armv7 $(APP_SRC); \
		else \
			echo "Building $(APP_NAME)-$$os-$$cpu..."; \
			GOOS=$$os GOARCH=$$cpu go build -o $(RELEASE_DIR)/$(APP_NAME)-$$os-$$cpu $(APP_SRC); \
		fi \
	done

release-all: build-all ## Package CLI binaries into tar.gz archives
	@for arch in $(ARCHS); do \
		os=$${arch%%/*}; \
		rest=$${arch#*/}; \
		cpu=$${rest%%/*}; \
		variant=$${rest#*/}; \
		if [ "$$cpu" = "arm" ] && [ "$$variant" = "v7" ]; then \
			bin=$(APP_NAME)-$$os-armv7; \
		else \
			bin=$(APP_NAME)-$$os-$$cpu; \
		fi; \
		echo "Packaging $$bin.tar.gz..."; \
		tar czf $(RELEASE_DIR)/$$bin.tar.gz -C $(RELEASE_DIR) $$bin; \
	done

install: build ## Install sunspecctl to /usr/local/bin
	@echo "Installing $(APP_NAME) to /usr/local/bin"
	@sudo install -m 0755 $(APP_NAME) /usr/local/bin/$(APP_NAME)

clean: ## Clean build artifacts and generated code
	@echo "Cleaning build artifacts"
	@rm -f $(APP_NAME)
	@rm -rf $(RELEASE_DIR)
	@rm -f coverage.out
	@rm -f registry/models_gen.go
