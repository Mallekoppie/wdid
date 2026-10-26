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
- `github.com/Mallekoppie/goslow` platform: Connect/HTTP serving, goslow's
  unified identity and authorization module, logging, BoltDB helpers, local JWT
  issuance
- BoltDB persistence with per-user bucket isolation

## Run

### Local single-user (default)

```bash
export WDID_JWT_SECRET='change-me-at-least-32-characters-long'
go run ./cmd/wdid
```

The server listens on `127.0.0.1:8080` and stores data in `./data/wdid.db` by
default. The first visit creates the single account from a **username** and an
optional password. No email address, bootstrap secret, invite or OIDC is
involved.

### Server / development (opt-in)

Hosted multi-user deployments opt in explicitly:

```bash
export WDID_AUTH_MODE=server
export WDID_BOOTSTRAP_SECRET='change-me-at-least-16-chars'
export WDID_JWT_SECRET='change-me-at-least-32-characters-long'
go run ./cmd/wdid
```

The first account uses the bootstrap secret, later accounts need single-use
invite codes, and Zitadel OIDC is optional.

Or use the Makefile, which supplies local-only development defaults:

```bash
make run        # local mode: username + optional password, no bootstrap
make run-dev    # server/development: bootstrap admin, invites, reflection
make run-demo   # seeded demo database on 127.0.0.1:9201
make build      # compile the service to bin/wdid
make test       # go test ./... and flutter test
make lint       # go vet ./... and flutter analyze
make buildweb   # Flutter release build into cmd/wdid/dist
make help       # list every target
```

`make run` is the local-first flow: the first visit asks for a **username** and
an **optional** password (a display name is not a separate field; it defaults to
the username). `make run-dev` sets `WDID_DEV_MODE=true`, which enables Connect
reflection and forces the server auth behaviour used by `make smoke-web`, the
bootstrap/invite paths, and multi-user development. The seeded demo keeps its
own database and port.

Override any default from the environment, for example
`make run WDID_HTTP_ADDR=0.0.0.0:8080 WDID_DB_PATH=/tmp/wdid.db`. The defaults in
the Makefile are for local development only.

`make run` serves the embedded web UI at **http://127.0.0.1:9300** (the port the
devcontainer forwards for it). The release build lives in
`cmd/wdid/dist`, which is gitignored and removed by `make clean`; `make run`
builds it on first use, and `make buildweb` rebuilds it explicitly. Without a
built UI the server answers 404 at `/`, so open the URL above rather than a
different port. (`go run ./cmd/wdid` without the Makefile uses the config
default, `127.0.0.1:8080`.)

### Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `WDID_HTTP_ADDR` | `127.0.0.1:8080` | Listen address |
| `WDID_DB_PATH` | `./data/wdid.db` | BoltDB file |
| `WDID_AUTH_MODE` | `local` | `local` (one username account, optional password) or `server` (bootstrap admin, email/password, invites, optional OIDC) |
| `WDID_BOOTSTRAP_SECRET` | required in server/dev mode | Deployment secret for the first (admin) account; only in server mode (or development mode, which forces server behaviour), and not accepted in local mode |
| `WDID_JWT_SECRET` | required | HS256 signing key for local tokens |
| `WDID_JWT_SIGNING_METHOD` | `HS256` | `HS256`, `HS384` or `HS512` |
| `WDID_JWT_EXPIRATION_MINUTES` | `720` | Local token lifetime |
| `WDID_MAX_BLOCK_MINUTES` | `240` | Timer block limit before keep/trim/discard |
| `WDID_ALLOWED_ORIGINS` | `http://127.0.0.1:5173,http://localhost:5173` | Exact CORS origins for the Flutter dev server |
| `WDID_DEV_MODE` | `false` | Enables Connect reflection (development only) and forces server auth behaviour |
| `WDID_ZITADEL_ENABLED` | `false` | Accept Zitadel ID tokens; rejected in local mode |
| `WDID_ZITADEL_ISSUER_URL` | empty | Issuer base URL, e.g. `http://zitadel.local:8080` |
| `WDID_ZITADEL_CLIENT_ID` | empty | OIDC client identifier |
| `WDID_ZITADEL_ALLOWED_ALGORITHMS` | `RS256` | Comma-separated signing algorithms |

> **Upgrading an existing deployment:** local mode is now the default. Existing
> server deployments must set `WDID_AUTH_MODE=server`. A local-mode service
> refuses to start against a database that contains accounts without a username
> and reports that fix instead of switching modes or ignoring those accounts.

When Zitadel is enabled, configure it to emit wdid's role vocabulary in a
`roles` claim: an admin token carries `"admin"`, every other token is a plain
user. There is no separately configurable admin-role string; local and OIDC
tokens share one mapping.

## Authentication model

wdid has two deployment modes. **Local** is the default; **server** is opt-in
with `WDID_AUTH_MODE=server` (and is always effective when
`WDID_DEV_MODE=true`).

### Local mode (default)

1. The first run registers the single account through
   `wdid.v1.AuthService/RegisterAccount` with a **username** and an optional
   password. It becomes `admin` so instance-wide backups remain usable.
2. Login accepts the username and, when the account has one, its password. A
   passwordless account signs in with the username alone.
3. Login returns a local HS256 JWT. Protected RPCs accept
   `Authorization: Bearer <token>`.
4. There is no email, bootstrap secret, invite or OIDC in local mode, and local
   mode can never create a second account.
5. A local-mode service refuses to start on a database that already contains
   server accounts (accounts without usernames). It never switches modes
   silently or picks an account; the error tells the operator to set
   `WDID_AUTH_MODE=server`.

### Server mode (`WDID_AUTH_MODE=server`)

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
   `AuthLocalOrOIDC`, so the same RPCs also accept a Zitadel ID token. The first
   OIDC login provisions a local account by email.
5. The caller's role always comes from the verified token's `roles` claim:
   `"admin"` is required for admin, everything else is a plain user. The stored
   profile role is a provisioning record, not an authorization source. An OIDC
   deployment must therefore grant the IdP admin role to at least one user;
   bootstrapping an admin locally first also works, because local tokens carry
   `"admin"`.

Passwords are stored as bcrypt hashes in `sys:user_credentials`, separate from
the user profile, so hashes are never serialized into API responses. Local
accounts keep their username in `sys:user_usernames`; server accounts are
indexed by email instead.

## Invite CLI

Invites exist only in server mode. In local mode the single account is created
on first run and no invite is needed.

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
| `wdid.v1.AuthService/RegisterAccount` | public | Create the first account with the bootstrap secret, or a later one with an invite code |
| `wdid.v1.AuthService/Login` | public | Exchange email + password for a local JWT |
| `wdid.v1.AuthService/GetAuthConfig` | public | Report local/OIDC login capabilities |
| `wdid.v1.AuthService/GetCurrentUser` | bearer token | Resolve the current account |

## Non-RPC routes

`GET /healthz` is the only non-RPC route. It returns `{"status":"ok"}` and is
the liveness probe.

## Storage layout

- `sys:meta` — `schema_version`, `instance_id`, `index_version`
- `sys:users`, `sys:user_emails`, `sys:user_usernames`, `sys:user_credentials`
- `sys:invites` (keyed by the invite-code hash)
- `user_<id>:categories`, `user_<id>:subcategories`
- `user_<id>:entries`, `user_<id>:milestones`, `user_<id>:notes`
- `user_<id>:checkins`, `user_<id>:settings`, `user_<id>:timer`
- `user_<id>:idx_entries_day`, `idx_entries_category`,
  `idx_entries_subcategory`, `idx_entries_person`

User-owned records live in user-prefixed buckets, so cross-account reads return
not found by construction. The identity indexes (`sys:user_emails`,
`sys:user_usernames`) are unique and case-insensitive; they are written in the
same transaction as the account and preserve the original spelling in the
profile for display. Local mode requires its account to have a username
identity. A local-mode service refuses to start on a database holding accounts
without one, so legacy server databases must set `WDID_AUTH_MODE=server`.

Entry indexes are written in the same transaction as the entry and rebuilt on
startup when `index_version` changes. Every new account is seeded with
`Initiatives`, `Support` (+ modes) and `Other` (+ modes), plus default settings.

## Verification

```bash
make build       # compile the service
make test        # go test ./... + flutter test
make lint        # go vet ./... + flutter analyze
make proto-check # fail if generated Go/Dart stubs are stale
make check       # lint, proto-check, and both test suites
```

`make buildweb` builds the Flutter app into `cmd/wdid/dist`; `make serveweb`
runs it with hot reload on `127.0.0.1:5173` and points it at the API on
`127.0.0.1:9300` (the same origin `make run` uses).

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
- `auth.Service.IdentityFromRequestContext` reads goslow's single
  `platform.Identity` from the request context and resolves it onto a local
  account. goslow's `Identity.Issuer` selects local (`wdid-local`) versus OIDC
  resolution; the token's `roles` claim selects the role. wdid does not
  re-verify the token.
- Object reads go through `ReadAllObjects` because goslow's `ReadObject` panics
  on a missing bucket.

## Not yet implemented

- Browser OIDC authorization-code flow (PKCE) and session cookies
- Category, entry, timer, milestone, note, check-in and settings RPCs
- Backup snapshots: goslow does not expose the raw `*bolt.DB`, so the
  `db.View(tx.WriteTo)` hot snapshot needs an upstream accessor
- Admin-only settings and user-management RPCs
