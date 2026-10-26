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
API_BASE_URL ?= http://127.0.0.1:9300

IMAGE ?= wdid:dev

# Local-only defaults. internal/config requires a bootstrap secret of at least
# 16 characters and a JWT secret of at least 32 characters.
WDID_HTTP_ADDR            ?= 127.0.0.1:9300
WDID_DB_PATH              ?= ./data/wdid.db
WDID_BOOTSTRAP_SECRET     ?= local-dev-bootstrap-secret
WDID_JWT_SECRET           ?= local-dev-jwt-secret-change-me-32chars
WDID_ALLOWED_ORIGINS      ?= http://127.0.0.1:5173,http://localhost:5173
WDID_DEV_MODE             ?= true

# Browser smoke credentials. The bootstrap secret must match the one the
# running service was started with, so it defaults to the development default
# above and makes `make run-dev` + `make smoke-web` work against a fresh
# database.
WDID_SMOKE_EMAIL             ?= smoke@example.com
WDID_SMOKE_PASSWORD          ?= smoke-password-123
WDID_SMOKE_BOOTSTRAP_SECRET  ?= $(WDID_BOOTSTRAP_SECRET)

# Demo loop. The demo database is separate from the default ./data/wdid.db, so
# seeding and resetting it never touches normal development data. Port 9201
# keeps it clear of `make run` (127.0.0.1:9300, the forwarded app origin).
DEMO_DB       ?= ./data/wdid-demo.db
DEMO_ADDR     ?= 127.0.0.1:9201
DEMO_SCENARIO ?= demo
DEMO_ANCHOR   ?=
SEED_ARGS     ?= --reset

# Seeded browser smoke test. Unlike smoke-web, this target owns the whole
# lifecycle: it seeds throwaway databases, starts the service on SMOKE_PORT,
# drives the seeded UI for each scenario, then stops the service and removes
# the databases. The service resolves Today and "this week" from its own
# clock, so the anchor is the run's UTC date: both the seeder and the frozen
# browser clock in scripts/browser-smoke-seeded.cjs use this same value.
# Override SMOKE_ANCHOR only when the service itself runs on that date.
SMOKE_PORT      ?= 9202
SMOKE_ANCHOR    ?= $(shell date -u +%F)
SMOKE_SCENARIOS ?= demo empty
DEMO_EMAIL      ?= demo@wdid.local
DEMO_PASSWORD   ?= demo-password-123

# Node + Playwright preflight shared by both browser smoke targets. $(1) names
# the target in the error message.
define require_browser_smoke_deps
	@command -v node >/dev/null 2>&1 || { \
		echo "node is required for the $(1) browser smoke test" >&2; \
		exit 1; \
	}
	@node -e "require('playwright')" 2>/dev/null || { \
		echo "playwright is required: npm install --no-save playwright (or set NODE_PATH)" >&2; \
		exit 1; \
	}
endef

export WDID_HTTP_ADDR WDID_DB_PATH WDID_BOOTSTRAP_SECRET WDID_JWT_SECRET
export WDID_ALLOWED_ORIGINS WDID_DEV_MODE
export WDID_SMOKE_EMAIL WDID_SMOKE_PASSWORD WDID_SMOKE_BOOTSTRAP_SECRET

.PHONY: help all build run run-dev test test-go test-web web-deps buildweb \
        web-ready serveweb lint fmt tidy proto proto-check docker-build clean \
        check smoke-web smoke-seeded seed-demo run-demo

help: ## Show this help
	@printf 'wdid targets:\n\n'
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nOverride defaults, e.g.: make run WDID_HTTP_ADDR=0.0.0.0:8080\n'

all: build ## Build the service binary (alias for build)

build: ## Compile cmd/wdid into bin/wdid
	@mkdir -p $(BIN_DIR)
	$(GO) build -trimpath -o $(BIN_DIR)/$(BINARY) $(CMD)

# The embedded UI lives in cmd/wdid/dist, which is gitignored and removed by
# `make clean`. Build it on demand so `make run` never serves an API-only
# server that answers 404 at the app origin.
web-ready:
	@test -f $(DIST_DIR)/index.html || { \
		echo "Building the web UI (missing $(DIST_DIR)/index.html)..."; \
		$(MAKE) buildweb; \
	}

run: web-ready ## Run locally in single-user local mode (username, optional password)
	WDID_DEV_MODE=false WDID_AUTH_MODE=local $(GO) run $(CMD)

run-dev: web-ready ## Run the server/development flow (bootstrap admin, invites, reflection)
	WDID_DEV_MODE=true WDID_AUTH_MODE=server $(GO) run $(CMD)

seed-demo: ## Seed data/wdid-demo.db with the demo scenario (dev-only; resets by default)
	WDID_DEV_MODE=true WDID_DB_PATH=$(DEMO_DB) \
	$(GO) run $(CMD) seed $(SEED_ARGS) $(if $(DEMO_ANCHOR),--anchor $(DEMO_ANCHOR)) $(DEMO_SCENARIO)

run-demo: web-ready ## Serve data/wdid-demo.db on 127.0.0.1:9201 (seeds it first if missing)
	@test -f $(DEMO_DB) || $(MAKE) seed-demo
	WDID_DEV_MODE=true WDID_DB_PATH=$(DEMO_DB) WDID_HTTP_ADDR=$(DEMO_ADDR) \
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
	$(call require_browser_smoke_deps,smoke-web)
	node scripts/browser-smoke.cjs

smoke-seeded: buildweb build ## Seed temp DBs, serve, and walk the seeded UI (Node + Playwright)
	$(call require_browser_smoke_deps,smoke-seeded)
	@set -euo pipefail; \
	tmp="$$(mktemp -d)"; \
	pid=""; \
	log="$$tmp/server.log"; \
	cleanup() { \
		if [ -n "$$pid" ]; then \
			kill "$$pid" 2>/dev/null || true; \
			wait "$$pid" 2>/dev/null || true; \
		fi; \
		rm -rf "$$tmp"; \
	}; \
	trap cleanup EXIT INT TERM; \
	for scenario in $(SMOKE_SCENARIOS); do \
		db="$$tmp/$$scenario.db"; \
		echo "==> smoke-seeded: $$scenario (anchor $(SMOKE_ANCHOR))"; \
		WDID_DEV_MODE=true WDID_DB_PATH="$$db" \
			./bin/wdid seed --reset --anchor $(SMOKE_ANCHOR) "$$scenario"; \
		WDID_DEV_MODE=true WDID_DB_PATH="$$db" \
			WDID_HTTP_ADDR=127.0.0.1:$(SMOKE_PORT) \
			WDID_BOOTSTRAP_SECRET=$(WDID_BOOTSTRAP_SECRET) \
			WDID_JWT_SECRET=$(WDID_JWT_SECRET) \
			WDID_ALLOWED_ORIGINS=$(WDID_ALLOWED_ORIGINS) \
			./bin/wdid >"$$log" 2>&1 & \
		pid=$$!; \
		ready=0; \
		for _ in $$(seq 1 100); do \
			if curl -fsS "http://127.0.0.1:$(SMOKE_PORT)/healthz" >/dev/null 2>&1; then \
				ready=1; \
				break; \
			fi; \
			if ! kill -0 "$$pid" 2>/dev/null; then \
				echo "smoke-seeded: server exited before becoming ready" >&2; \
				cat "$$log" >&2; \
				exit 1; \
			fi; \
			sleep 0.1; \
		done; \
		if [ "$$ready" -ne 1 ]; then \
			echo "smoke-seeded: server did not become ready on port $(SMOKE_PORT)" >&2; \
			cat "$$log" >&2; \
			exit 1; \
		fi; \
		if ! WDID_BASE_URL="http://127.0.0.1:$(SMOKE_PORT)" \
			WDID_SMOKE_SCENARIO="$$scenario" \
			WDID_SMOKE_ANCHOR="$(SMOKE_ANCHOR)" \
			WDID_SMOKE_EMAIL="$(DEMO_EMAIL)" \
			WDID_SMOKE_PASSWORD="$(DEMO_PASSWORD)" \
			node scripts/browser-smoke-seeded.cjs; then \
			echo "smoke-seeded: $$scenario failed; server log:" >&2; \
			cat "$$log" >&2; \
			exit 1; \
		fi; \
		kill "$$pid" 2>/dev/null || true; \
		wait "$$pid" 2>/dev/null || true; \
		pid=""; \
	done

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
