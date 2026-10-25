# wdid developer entry points.
#
# Local development defaults are intentionally weak and must never be used for a
# real deployment. Override any variable from the environment or the command
# line, for example:
#
#   make run WDID_HTTP_ADDR=0.0.0.0:8080 WDID_DB_PATH=/tmp/wdid.db
#
# Run `make` or `make help` for the full target list.

SHELL := /bin/bash
.DEFAULT_GOAL := help

GO        ?= go
FLUTTER   ?= flutter
DOCKER    ?= docker
GO_MODULE := github.com/Mallekoppie/wdid

# go.mod requires Go 1.27.2. Auto lets an older local toolchain fetch the
# matching toolchain until the dev container is rebuilt.
GOTOOLCHAIN := auto
export GOTOOLCHAIN

BINARY  ?= wdid
BIN_DIR ?= bin
CMD     := ./cmd/wdid

WEB_DIR   := web
WEB_BUILD := $(WEB_DIR)/build/web
DIST_DIR  := cmd/wdid/dist
API_BASE_URL ?= http://127.0.0.1:8080

IMAGE ?= wdid:dev

# Local-only defaults. internal/config requires a bootstrap secret of at least
# 16 characters and a JWT secret of at least 32 characters.
WDID_HTTP_ADDR            ?= 127.0.0.1:9200
WDID_DB_PATH              ?= ./data/wdid.db
WDID_BOOTSTRAP_SECRET     ?= local-dev-bootstrap-secret
WDID_JWT_SECRET           ?= local-dev-jwt-secret-change-me-32chars
WDID_ALLOWED_ORIGINS      ?= http://127.0.0.1:5173,http://localhost:5173
WDID_DEV_MODE             ?= true

# Browser smoke credentials. The bootstrap secret must match the one the
# running service was started with, so it defaults to the development default
# above and makes `make run` + `make smoke-web` work against a fresh database.
WDID_SMOKE_EMAIL             ?= smoke@example.com
WDID_SMOKE_PASSWORD          ?= smoke-password-123
WDID_SMOKE_BOOTSTRAP_SECRET  ?= $(WDID_BOOTSTRAP_SECRET)

export WDID_HTTP_ADDR WDID_DB_PATH WDID_BOOTSTRAP_SECRET WDID_JWT_SECRET
export WDID_ALLOWED_ORIGINS WDID_DEV_MODE
export WDID_SMOKE_EMAIL WDID_SMOKE_PASSWORD WDID_SMOKE_BOOTSTRAP_SECRET

.PHONY: help all build run test test-go test-web web-deps buildweb serveweb \
        lint fmt tidy proto proto-check docker-build clean check smoke-web

help: ## Show this help
	@printf 'wdid targets:\n\n'
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nOverride defaults, e.g.: make run WDID_HTTP_ADDR=0.0.0.0:8080\n'

all: build ## Build the service binary (alias for build)

build: ## Compile cmd/wdid into bin/wdid
	@mkdir -p $(BIN_DIR)
	$(GO) build -trimpath -o $(BIN_DIR)/$(BINARY) $(CMD)

run: ## Run the service locally using the development defaults above
	$(GO) run $(CMD)

test: test-go test-web ## Run Go tests and Flutter tests

test-go: ## Run the Go test suite
	$(GO) test ./...

test-web: web-deps ## Run the Flutter test suite
	cd $(WEB_DIR) && $(FLUTTER) test

web-deps: ## Fetch Flutter packages
	cd $(WEB_DIR) && $(FLUTTER) pub get

buildweb: web-deps ## Build the Flutter web app into cmd/wdid/dist
	cd $(WEB_DIR) && $(FLUTTER) build web --release
	rm -rf $(DIST_DIR)
	mkdir -p $(DIST_DIR)
	cp -R $(WEB_BUILD)/. $(DIST_DIR)/
	@touch $(DIST_DIR)/.gitkeep

serveweb: web-deps ## Serve the Flutter web app with hot reload on 127.0.0.1:5173
	cd $(WEB_DIR) && $(FLUTTER) run -d web-server \
		--web-hostname 127.0.0.1 --web-port 5173 \
		--dart-define=WDID_API_BASE_URL=$(API_BASE_URL)

lint: ## Run go vet and flutter analyze
	$(GO) vet ./...
	cd $(WEB_DIR) && $(FLUTTER) analyze

fmt: ## Format Go and Dart sources
	$(GO) fmt ./...
	cd $(WEB_DIR) && dart format lib test

tidy: ## Tidy go.mod and go.sum
	$(GO) mod tidy

check: lint proto-check test ## Run proto-check, lint and both test suites

smoke-web: ## Drive the served app end to end in a browser (WDID_BASE_URL, Node + Playwright)
	@command -v node >/dev/null 2>&1 || { \
		echo "node is required for the browser smoke test" >&2; \
		exit 1; \
	}
	@node -e "require('playwright')" 2>/dev/null || { \
		echo "playwright is required: npm install --no-save playwright (or set NODE_PATH)" >&2; \
		exit 1; \
	}
	node scripts/browser-smoke.cjs

proto: ## Generate message, Connect, and Dart stubs from internal/contracts/*.proto
	@command -v protoc >/dev/null 2>&1 || { \
		echo "protoc not found on PATH - use the dev container or install protoc" >&2; \
		exit 1; \
	}
	@command -v protoc-gen-connect-go >/dev/null 2>&1 || { \
		echo "protoc-gen-connect-go not found on PATH - go install connectrpc.com/connect/cmd/protoc-gen-connect-go@latest" >&2; \
		exit 1; \
	}
	@shopt -s nullglob; protos=(internal/contracts/*.proto); \
	if [ $${#protos[@]} -eq 0 ]; then \
		echo "No .proto files in internal/contracts - nothing to generate."; \
		exit 0; \
	fi; \
	rm -rf internal/gen $(WEB_DIR)/lib/src/generated; \
	mkdir -p internal/gen $(WEB_DIR)/lib/src/generated; \
	protoc -I internal/contracts \
		--go_out=. --go_opt=module=$(GO_MODULE) \
		--connect-go_out=. --connect-go_opt=module=$(GO_MODULE) \
		$${protos[@]}; \
	protoc -I internal/contracts \
		--dart_out=grpc:$(WEB_DIR)/lib/src/generated \
		$${protos[@]}

proto-check: ## Regenerate in a temp dir and fail if internal/gen is stale
	@command -v protoc >/dev/null 2>&1 || { \
		echo "protoc not found on PATH - use the dev container or install protoc" >&2; \
		exit 1; \
	}
	@command -v protoc-gen-connect-go >/dev/null 2>&1 || { \
		echo "protoc-gen-connect-go not found on PATH - go install connectrpc.com/connect/cmd/protoc-gen-connect-go@latest" >&2; \
		exit 1; \
	}
	@shopt -s nullglob; protos=(internal/contracts/*.proto); \
	if [ $${#protos[@]} -eq 0 ]; then \
		echo "WARNING: no .proto files in internal/contracts - the contract gate is not exercised."; \
		exit 0; \
	fi; \
	tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	mkdir -p "$$tmp" "$$tmp/dart"; \
	protoc -I internal/contracts \
		--go_out="$$tmp" --go_opt=module=$(GO_MODULE) \
		--connect-go_out="$$tmp" --connect-go_opt=module=$(GO_MODULE) \
		$${protos[@]} || exit 1; \
	protoc -I internal/contracts \
		--dart_out=grpc:"$$tmp/dart" \
		$${protos[@]} || exit 1; \
	if [ ! -d internal/gen ]; then \
		echo "internal/gen is missing - run 'make proto' and commit the generated Go stubs" >&2; \
		exit 1; \
	fi; \
	if ! diff -ru internal/gen "$$tmp/internal/gen"; then \
		echo "Generated Go stubs are stale or edited - run 'make proto' and commit internal/gen" >&2; \
		exit 1; \
	fi; \
	if [ -d $(WEB_DIR)/lib/src/generated ]; then \
		if ! diff -ru $(WEB_DIR)/lib/src/generated "$$tmp/dart"; then \
			echo "Generated Dart stubs are stale or edited - run 'make proto'" >&2; \
			exit 1; \
		fi; \
	fi; \
	find "$$tmp/dart" -name '*.dart' -print -quit | grep -q . || { \
		echo "Dart stubs were not generated - check protoc-gen-dart" >&2; \
		exit 1; \
	}

docker-build: ## Build the container image (requires a root Dockerfile)
	@if [ ! -f Dockerfile ]; then \
		echo "No Dockerfile at the repository root yet - add one before running docker-build." >&2; \
		exit 1; \
	fi
	$(DOCKER) build -t $(IMAGE) .

clean: ## Remove build artifacts (never touches data/ or backups/)
	rm -rf $(BIN_DIR) $(DIST_DIR) $(WEB_BUILD)
