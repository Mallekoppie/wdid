#!/usr/bin/env bash
# Runs once after the dev container is created (see devcontainer.json).
# The heavy toolchain is baked into the image; this only primes per-project
# state (Go modules, Flutter packages) and reports what is available.
# Every step is best-effort so a flaky network does not block opening the repo.
set -u

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

cd /workspaces/wdid 2>/dev/null || cd /workspaces 2>/dev/null || true

log "Toolchain"
printf '  go      : %s\n' "$(go version 2>/dev/null | awk '{print $3}')"
printf '  protoc  : %s\n' "$(protoc --version 2>/dev/null)"
printf '  dart    : %s\n' "$(dart --version 2>&1 | head -1)"
printf '  flutter : %s\n' "$(flutter --version 2>/dev/null | head -1)"
if command -v claude >/dev/null 2>&1; then
    printf '  claude  : %s\n' "$(claude --version 2>/dev/null | head -1)"
else
    warn "claude not found - rebuild the container to install the devcontainer feature"
fi
for p in protoc-gen-go protoc-gen-connect-go protoc-gen-dart; do
    if command -v "$p" >/dev/null 2>&1; then
        printf '  %-8s: %s\n' "${p#protoc-gen-}" "$(command -v "$p")"
    else
        warn "$p not found on PATH"
    fi
done

log "Host container engine"
if command -v docker >/dev/null 2>&1; then
    if docker ps >/dev/null 2>&1; then
        echo "  host engine reachable via ${DOCKER_HOST:-<unset>}"
    else
        warn "cannot reach the host engine - is the host podman.socket running?"
        warn "  host fix: systemctl --user start podman.socket"
    fi
else
    warn "docker/podman client not found"
fi

if [ -f go.mod ]; then
    log "Downloading Go modules"
    go mod download && echo "  ok" || warn "go mod download failed (offline?)"
fi

if [ -f Makefile ]; then
    log "Generating protobuf stubs (make proto)"
    make proto >/dev/null 2>&1 && echo "  ok" || warn "make proto failed - run it manually"
fi

if [ -f web/pubspec.yaml ] && command -v flutter >/dev/null 2>&1; then
    log "Flutter packages (web/)"
    (cd web && flutter pub get) && echo "  ok" || warn "flutter pub get failed"
fi

if [ -f go.mod ]; then
    log "Verifying the project builds"
    go build ./... && echo "  BUILD OK" || warn "go build ./... failed - inspect output above"
fi

log "post-create finished."
cat <<'EOF'

Next steps:
  claude            # first run signs in; auth persists in a volume
  make proto        # generate Go + Dart stubs from internal/contracts/*.proto
  make buildweb     # build the Flutter web app into the embedded dist directory
  make all          # build the server
  make test         # go test + flutter test
  make run          # run the server locally
  make docker-build # build the image with the HOST engine

EOF
