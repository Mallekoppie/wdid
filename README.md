# wdid service

Backend service for **wdid** ("what did I do"): a local-first work journal with
initiative-based time attribution, support tracking, and review-ready period
exports.

This service is the source of truth for persistence, validation, identity,
exports and AI-ready summaries. The web client consumes the Connect contract over
gRPC-Web and must not reimplement these rules.

> **Status:** This README describes the current service implementation. `plan.md`
> is the canonical product and domain model; where the two differ, the plan wins
> and the service is to be migrated. The current domain and storage shape is the
> pre-taxonomy model.

> **Transport status:** Connect is the only service transport. It serves
> Connect, native gRPC, and gRPC-Web from one handler, and
> `internal/contracts/*.proto` is the source of truth. `/healthz` is the only
> non-RPC route.

## Stack

- Go 1.27.2
- `github.com/Mallekoppie/goslow` platform: Connect/HTTP serving, goslow auth
  interceptors, logging, BoltDB helpers, local JWT issuance
- `github.com/coreos/go-oidc` for Zitadel ID token verification in the wdid
  identity resolver
- BoltDB persistence with per-user bucket isolation

## Run

```bash
export WDID_BOOTSTRAP_SECRET='change-me-at-least-16-chars'
export WDID_JWT_SECRET='change-me-at-least-32-characters-long'
go run ./cmd/wdid
```

The server listens on `127.0.0.1:8080` and stores data in `./data/wdid.db` by
default.

Or use the Makefile, which supplies local-only development defaults for the
required secrets:

```bash
make run        # go run ./cmd/wdid with development defaults
make build      # compile the service to bin/wdid
make test       # go test ./... and flutter test
make lint       # go vet ./... and flutter analyze
make buildweb   # Flutter release build into cmd/wdid/dist
make help       # list every target
```

Override any default from the environment, for example
`make run WDID_HTTP_ADDR=0.0.0.0:8080 WDID_DB_PATH=/tmp/wdid.db`. The defaults in
the Makefile are for local development only.

### Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `WDID_HTTP_ADDR` | `127.0.0.1:8080` | Listen address |
| `WDID_DB_PATH` | `./data/wdid.db` | BoltDB file |
| `WDID_BOOTSTRAP_SECRET` | required | Deployment secret for the first (admin) account |
| `WDID_JWT_SECRET` | required | HS256 signing key for local tokens |
| `WDID_JWT_SIGNING_METHOD` | `HS256` | `HS256`, `HS384` or `HS512` |
| `WDID_JWT_EXPIRATION_MINUTES` | `720` | Local token lifetime |
| `WDID_MAX_BLOCK_MINUTES` | `240` | Timer block limit before keep/trim/discard |
| `WDID_ALLOWED_ORIGINS` | `http://127.0.0.1:5173,http://localhost:5173` | Exact CORS origins for the Flutter dev server |
| `WDID_DEV_MODE` | `false` | Enables Connect reflection (development only) |
| `WDID_ZITADEL_ENABLED` | `false` | Accept Zitadel ID tokens |
| `WDID_ZITADEL_ISSUER_URL` | empty | Issuer base URL, e.g. `http://zitadel.local:8080` |
| `WDID_ZITADEL_CLIENT_ID` | empty | OIDC client identifier |
| `WDID_ZITADEL_ALLOWED_ALGORITHMS` | `RS256` | Comma-separated signing algorithms |
| `WDID_ZITADEL_ADMIN_ROLE` | `wdid-admins` | Role claim mapped to admin |

## Authentication model

Initial local deployment baseline:

1. The **first** account registers through
   `wdid.v1.AuthService/RegisterAccount` with the deployment bootstrap secret and
   becomes `admin`. The bootstrap secret is not accepted once that account
   exists.
2. Every later account needs a single-use invite code issued by an admin with
   `wdid invite create --email <address>` and becomes `user`. Reusing or
   revoking a code makes it unusable.
3. Login returns a local HS256 JWT. Protected RPCs accept
   `Authorization: Bearer <token>`.
4. When Zitadel is enabled, goslow's Connect auth interceptor uses
   `AuthLocalOrOIDC`, so the same RPCs also accept a Zitadel ID token. The first OIDC login provisions a local account by email, and a
   configured role claim maps to `admin`.

Passwords are stored as bcrypt hashes in `sys:user_credentials`, separate from
the user profile, so hashes are never serialized into API responses.

## Invite CLI

```bash
wdid invite create --email person@example.com   # prints the code once
wdid invite list                                 # id, email, status, created, used by
wdid invite revoke <id>
```

Invite codes are single-use and bound to the email they were issued for. Only a
SHA-256 hash of the code is stored. The CLI reads `WDID_DB_PATH` and needs no
serving secrets. BoltDB allows one writer, so stop the service before running
invite commands; the CLI reports the lock if it is still running.

## Connect API

`internal/contracts/auth.proto` is the first live contract. `AuthService` serves
Connect, native gRPC, and gRPC-Web on the same origin as the liveness route and
the embedded app.

| RPC | Auth | Purpose |
| --- | --- | --- |
| `wdid.v1.AuthService/RegisterAccount` | public | Create an account with the registration secret |
| `wdid.v1.AuthService/Login` | public | Exchange email + password for a local JWT |
| `wdid.v1.AuthService/GetAuthConfig` | public | Report local/OIDC login capabilities |
| `wdid.v1.AuthService/GetCurrentUser` | bearer token | Resolve the current account |

## Non-RPC routes

`GET /healthz` is the only non-RPC route. It returns `{"status":"ok"}` and is
the liveness probe.

## Storage layout

- `sys:users`, `sys:user_emails`, `sys:user_credentials`
- `sys:invites` (keyed by the invite-code hash)
- `user_<id>:initiatives`
- `user_<id>:entries`
- `user_<id>:timer`

User-owned records live in user-prefixed buckets, so cross-account reads return
not found by construction.

## Verification

```bash
make build       # compile the service
make test        # go test ./... + flutter test
make lint        # go vet ./... + flutter analyze
make proto-check # fail if generated Go/Dart stubs are stale
make check       # lint, proto-check, and both test suites
```

`make buildweb` builds the Flutter app into `cmd/wdid/dist`; `make serveweb`
runs it with hot reload on `127.0.0.1:5173`.

## goslow integration notes

- Persistence goes through `platform.Database.BoltDb` helpers.
- `platform.StartApplicationServerWithContext` serves Connect, native gRPC,
  gRPC-Web, the `/healthz` route, and the embedded Flutter app on one origin.
- `Grpc.Server.Auth` is explicit: `AuthLocalJWT` for local-only deployments and
  `AuthLocalOrOIDC` when Zitadel is enabled.
- Public RPCs live in `Auth.Server.UnauthenticatedPaths`; admin RPCs will use
  `Grpc.Server.ProcedureRoles` as they land.
- `HTTP.Server.AllowedOrigins` and `Grpc.Server.AllowedOrigins` carry exact
  origins only; there is no wildcard or local-development CORS switch.
- The database file is pre-created with `0600` permissions because goslow opens
  BoltDB with `os.ModeExclusive` as the file mode, which would create new files
  as `0000`.
- `auth.Service.IdentityFromRequestContext` resolves the wdid account after
  goslow has already validated the bearer token; it does not re-authenticate
  local JWTs.
- Object reads go through `ReadAllObjects` because goslow's `ReadObject` panics
  on a missing bucket.

## Not yet implemented

- Browser OIDC authorization-code flow (PKCE) and session cookies
- Check-in records and persistence
- Backup snapshots: goslow does not expose the raw `*bolt.DB`, so the
  `db.View(tx.WriteTo)` hot snapshot needs an upstream accessor
- Admin-only settings and user-management RPCs
