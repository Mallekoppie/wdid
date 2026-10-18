# wdid TODO — paused 2026-10-18

## Current state

goslow was merged and wdid has been migrated onto the merged API.

- goslow merged revision: `v0.0.0-20261018185216-5eded094f41a`
  (`master` commit `5eded09`, "Fixes for wdid (#5)")
- wdid module: `go 1.27.2`
- The Makefile exports `GOTOOLCHAIN=auto` because the current container still
  has Go 1.26.9; rebuild the dev container when convenient.
- The service now starts `platform.StartApplicationServerWithContext` and serves
  Connect, native gRPC, gRPC-Web, legacy REST routes, and the embedded Flutter
  assets from one listener.
- The first live contract is `internal/contracts/auth.proto` with
  `wdid.v1.AuthService`:
  - `RegisterAccount` — public
  - `Login` — public
  - `GetAuthConfig` — public
  - `GetCurrentUser` — bearer token required
- Generated Go stubs are under `internal/gen/wdid/v1/` and
  `internal/gen/wdid/v1/wdidv1connect/`.
- Generated Dart stubs are under `web/lib/src/generated/` and are gitignored.
- `web/pubspec.yaml` now depends on `grpc` 5.2.0 and `protobuf` 6.1.0.

## Verification already run

```text
make proto-check                         pass
make build                               pass
go vet ./...                             pass
go test -race ./...                      pass
cd web && flutter analyze                pass
cd web && flutter test                   pass (16 tests)
```

Runtime smoke test also passed:

- `GET /healthz` returned 200.
- `POST /wdid.v1.AuthService/GetAuthConfig` returned the public auth config.
- An unknown RPC path returned 404 instead of falling through to the SPA.
- Connect, gRPC-Web, and native gRPC AuthService tests pass.

## Immediate cleanup before committing

1. **Restore `GOSLOW-UPDATES.md`.**
   It is currently deleted in the working tree (` D GOSLOW-UPDATES.md`). Restore
   it with `git checkout -- GOSLOW-UPDATES.md`, then re-apply the concise
   merge-status version. Do not commit the deletion.
2. **Run `git diff --check` again.**
   The extra blank line at the end of `internal/auth/service.go` was fixed, but
   the final check had not been re-run before stopping.
3. **Confirm the generated artifacts are included.**
   Commit `internal/contracts/auth.proto`, `internal/gen/`, `internal/rpc/`, and
   `cmd/wdid/dist/.gitkeep`. Generated Dart stubs stay gitignored.
4. **Rebuild the dev container.**
   The Dockerfile is already on Go 1.27 and installs
   `protoc-gen-connect-go` 1.21.1, but this running container is still on Go
   1.26.9.

## Next implementation steps

### 1. Wire the Flutter client to AuthService over gRPC-Web

- Create a gRPC-Web client adapter using `GrpcWebClientChannel.xhr`.
- Use the generated `AuthServiceClient` from `web/lib/src/generated/`.
- Add bearer-token metadata and per-call deadlines.
- Map `GrpcError` / Connect codes to the existing login-screen error states.
- Replace the demo auth behaviour before wiring the domain repository.
- Run `make proto` before Flutter analysis or build.

### 2. Replace `DemoWdidRepository`

- Implement a real `WdidRepository` backed by generated stubs.
- Do not hand-write JSON DTOs for capabilities that have RPCs.
- Keep server-owned totals, validation, and attribution rules authoritative.
- Add loading, empty, error, and success states where the demo adapter currently
  returns synthetic data.

### 3. Migrate the remaining domain contracts

Add protos and Connect services in this order:

1. Initiatives
2. Work entries and timer lifecycle
3. Period summary and export
4. Check-ins and AI summary prompt payload
5. Settings and backups

For each one:

- Add request/response messages with permanent field numbers.
- Add the service implementation under `internal/rpc/`.
- Register the service with `ApplicationServerOptions.Services`.
- Add the fully qualified service name to `ServiceNames`.
- Move the matching REST handler out of `internal/api/` once the RPC lands.
- Add Connect error mapping and `httptest` coverage.
- Add gRPC-Web and, where relevant, native gRPC tests.

### 4. Authorization follow-ups

- Add `Grpc.Server.ProcedureRoles` entries when admin-only RPCs land.
- Keep identity derived from goslow's verified auth context; never trust a
  `user_id` in a request message.
- For OIDC, `GetCurrentUser` currently re-verifies the token because goslow
  exposes roles/username/issuer but not verified subject/email claims. Prefer
  exporting OIDC claims from goslow and remove the second verification.
- Add an OIDC/Zitadel integration test once a local IdP is available.

### 5. UI and product validation

- Verify the five-second quick-capture path still works after the repository
  swap.
- Verify keyboard-first flows, loading/empty/error states, and compact layout.
- Run a real browser gRPC-Web request against the running service.
- Build the Flutter web app into `cmd/wdid/dist` and verify the embedded SPA is
  served on the same origin as Connect.

## Known non-blocking notes

- goslow logs `code":"unknown"` for successful RPCs; this is a goslow logging
  issue, not a wdid failure.
- The expected missing-user path logs a BoltDB "no entry found" error from
  `ReadObject`; the store wrapper still returns `ErrNotFound`.
- `cmd/wdid/dist` contains only `.gitkeep` until `make buildweb` runs. The embed
  uses `//go:embed all:dist`.
- `GOSLOW-UPDATES.md` should retain only remaining goslow follow-ups:
  custom-handler h2c documentation, handler `TLSEnabled` semantics, OIDC claims
  context, duplicate denied-auth metrics, `http.TimeoutHandler` cancellation,
  deprecated indirect protobuf dependency, and metrics listener lifetime.

## Useful commands

```bash
make proto          # regenerate Go + Dart stubs
make proto-check    # fail if generated stubs are stale
make build          # compile bin/wdid
make test-go        # Go tests
make test-web       # Flutter tests
make lint           # go vet + flutter analyze
make check          # lint + proto-check + Go/Flutter tests
```

Smoke test:

```bash
WDID_HTTP_ADDR=127.0.0.1:18080 \
WDID_DB_PATH=/tmp/wdid.db \
WDID_REGISTRATION_SECRET=local-dev-registration-secret \
WDID_JWT_SECRET=local-dev-jwt-secret-change-me-32chars \
WDID_DEV_MODE=true \
./bin/wdid
```
