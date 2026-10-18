# goslow update recommendations

Target revision reviewed: `78b922b0aa76b608d902014c6db0cef3f07dce95`
(`github.com/Mallekoppie/goslow`, commit "fixed boltdb issue", 2026-02-14)

Consumer context: the `wdid` service uses goslow for HTTP routing, logging,
BoltDB persistence, and local JWT issuance. Two goslow defects had to be worked
around in the consumer:

1. `SetupBoltDB` creates a new database file with mode `0000`, so the service
   cannot reopen the file after a container restart.
2. `ReadObject` panics when the bucket does not exist.

Both were reproduced against the current revision. Fixing them in goslow removes
the workarounds and makes hosted/container deployments reliable.

Legend: **P0** blocks reliable deployment, **P1** correctness/security,
**P2** capability gaps, **P3** polish.

---

## P0 — BoltDB container restart failure

### P0.1 File mode is zero on first creation

**Location:** `platform/boltdb.go:42`

```go
dbBolt, err = bolt.Open(internalConfig.Database.BoltDB.FileName, os.ModeExclusive, nil)
```

`bolt.Open`'s second argument is an `os.FileMode`, not a set of open flags.
`os.ModeExclusive` is a mode bit (`1 << 20`), and its permission bits are zero.
On first creation the file is created as `0000`.

**Reproduction (verified):**

```go
f, _ := os.OpenFile("/tmp/test.db", os.O_CREATE|os.O_RDWR, os.ModeExclusive)
f.Close()
// created mode: 0000
// reopen after restart: open /tmp/test.db: permission denied
```

This is exactly the observed behaviour: the first container run creates the
database, and every subsequent run fails to open it. It also becomes acute when
the first run happened as root and later runs use a non-root container user.

**Fix:**

```go
const (
	boltFileMode        = 0o600
	defaultOpenTimeout  = 5 * time.Second
)

func SetupBoltDB() error {
	conf, err := GetPlatformConfiguration()
	if err != nil {
		return err
	}
	if !conf.Database.BoltDB.Enabled {
		Log.Info("Database BoltDb not enabled")
		return ErrBoltDbIsNotEnabled
	}
	return OpenBoltDB(conf.Database.BoltDB.FileName, conf.Database.BoltDB.OpenTimeout)
}

func OpenBoltDB(path string, timeout time.Duration) error {
	if strings.TrimSpace(path) == "" {
		return errors.New("boltdb: database file name is required")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("boltdb: create data directory: %w", err)
	}

	if timeout <= 0 {
		timeout = defaultOpenTimeout
	}

	db, err := bolt.Open(path, boltFileMode, &bolt.Options{Timeout: timeout})
	if err != nil {
		return describeBoltOpenError(path, err)
	}

	dbBolt = db
	return nil
}
```

**Acceptance criteria:**

- A new database file is created with mode `0600` (or another explicitly
  configured mode), never `0000`.
- The same process, and a fresh process running as the same user, can reopen the
  file after close.
- A test asserts `info.Mode().Perm()&0o077 == 0`.
- A test asserts a second `OpenBoltDB` on the same path succeeds after `Close`.

### P0.2 Remove the restart hack

**Location:** `platform/boltdb.go:20-27`, called from `:39`

```go
func databaseHackToRestartServiceIKnowThisIsBad(conf *Config) {
	os.Chmod(conf.Database.BoltDB.FileName, 0755)
	os.Remove(conf.Database.BoltDB.FileName + ".lock")
}
```

Problems:

- `0755` on a database holding personal work records is world-readable. It
  should be `0600` or stricter.
- BoltDB uses `flock` on the database file, not a `.lock` sidecar. Removing a
  `.lock` file is meaningless at best.
- If a `.lock` file did belong to another tool or process, deleting it while that
  process holds the database is unsafe.
- Errors are ignored, so permission failures are silent.
- The function name is a reliable signal that it should not ship.

**Fix:** delete the function and its call. Replace it with real error handling
from `bolt.Open`.

**Acceptance criteria:**

- No `os.Chmod` on the database file during startup.
- No sidecar lock file is created or removed.
- A failed open returns the underlying error, including the path.

### P0.3 Surface ownership and mode on open failure

Container volume bugs are hard to diagnose because BoltDB returns a bare
`permission denied`. Include the context needed to fix it.

```go
func describeBoltOpenError(path string, err error) error {
	info, statErr := os.Stat(path)
	if statErr != nil {
		return fmt.Errorf("boltdb: open %s: %w", path, err)
	}

	mode := info.Mode().Perm()
	return fmt.Errorf(
		"boltdb: open %s (mode=%04o uid=%d gid=%d): %w; "+
			"check that the container user owns the data volume",
		path, mode, os.Geteuid(), os.Getgid(), err,
	)
}
```

For a portable build, put the uid/gid part behind a Unix build tag. On Windows,
report the path, mode, and error only.

**Acceptance criteria:**

- An open failure names the path, the file mode, the effective uid/gid on Unix,
  and wraps the original error so `errors.Is(err, fs.ErrPermission)` works.

### P0.4 Open timeout

`bolt.Open` without `Options.Timeout` blocks indefinitely when another process
holds the file lock. In containers this presents as a service that hangs on
startup with no log line after "Setting up BoltDB".

**Fix:** `bolt.Options{Timeout: 5 * time.Second}` by default, configurable as
`platform.database.boltdb.opentimeoutseconds`.

**Acceptance criteria:**

- Two processes opening the same database: the second returns an error within the
  timeout instead of hanging.
- The error message mentions the lock being held by another process.

### P0.5 Guard against uninitialized configuration

**Location:** `platform/boltdb.go:30-37`

`SetupBoltDB` dereferences the package-global `internalConfig` without a nil
check, so calling it before configuration is set panics rather than returning an
error.

**Fix:** call `GetPlatformConfiguration()` and use the returned config, as in the
P0.1 snippet.

**Acceptance criteria:**

- `SetupBoltDB` returns a clear error when configuration is missing or BoltDB is
  disabled.
- No nil dereference is possible from exported API calls.

### P0.6 Make `Close` nil-safe and restartable

**Location:** `platform/boltdb.go:52-54`

```go
func (d *boltDbDatabase) Close() error {
	return dbBolt.Close()
}
```

Two issues:

- `dbBolt` may be nil when BoltDB was never opened, causing a nil dereference.
- After close, `dbBolt` still points at a closed handle, so a later
  `SetupBoltDB` in the same process is fragile.

```go
func (d *boltDbDatabase) Close() error {
	if dbBolt == nil {
		return nil
	}
	err := dbBolt.Close()
	dbBolt = nil
	return err
}
```

**Acceptance criteria:**

- `Close` on an unopened database returns nil.
- Open → close → open → close works in one process.

---

## P1 — correctness and security

### P1.1 `ReadObject` panics on a missing bucket

**Location:** `platform/boltdb.go:98-121`

```go
b := tx.Bucket([]byte(bucket))
result := b.Get([]byte(id))
```

`tx.Bucket` returns nil when the bucket does not exist. `Bucket.Get` calls
`b.Cursor()`, and `Cursor.seek` executes `_assert(c.bucket.tx.db != nil, ...)`,
which dereferences the nil bucket and panics. This is reachable on the very first
read of any new user bucket.

**Fix:**

```go
b := tx.Bucket([]byte(bucket))
if b == nil {
	return ErrNoEntryFoundInDB
}

result := b.Get([]byte(id))
if len(result) == 0 {
	return ErrNoEntryFoundInDB
}
```

**Acceptance criteria:**

- Reading a missing bucket returns `ErrNoEntryFoundInDB`, without a panic.
- A test covers a database with no buckets at all.

### P1.2 Local JWT middleware can panic on a malformed header

**Location:** `platform/middleware.go:246-258`

```go
authHeader := r.Header.Get("Authorization")
if authHeader == "" { ... }
tokenString := authHeader[len("Bearer "):]
```

If the header is shorter than `len("Bearer ")` (for example `Basic x` or `abc`),
the slice operation panics. There is also no check that the scheme is actually
`Bearer`.

**Fix:**

```go
const bearerPrefix = "Bearer "

header := r.Header.Get("Authorization")
if !strings.HasPrefix(header, bearerPrefix) {
	http.Error(w, "Unauthorized", http.StatusUnauthorized)
	return
}

tokenString := strings.TrimSpace(strings.TrimPrefix(header, bearerPrefix))
if tokenString == "" {
	http.Error(w, "Unauthorized", http.StatusUnauthorized)
	return
}
```

**Acceptance criteria:**

- Headers `""`, `"abc"`, `"Basic xyz"`, and `"Bearer "` all return 401 without
  panicking.
- A test exercises each case.

### P1.3 OAuth middleware silently drops requests when no role is required

**Location:** `platform/middleware.go:85-177`

```go
authorized := false
if len(roles) > 0 {
	// verification, sets authorized = true
}
if authorized {
	inner.ServeHTTP(w, r.WithContext(ctx))
}
```

When `AuthRequired` is true but `RolesRequired` is empty, the middleware
verifies nothing, never sets `authorized`, and never calls `inner`. The client
receives an empty `200` with no body. This is a silent failure that is very hard
to debug.

**Fix:** treat "authentication required with no role restriction" as valid:

```go
if len(roles) == 0 {
	// token still must verify; only role matching is skipped
	authorized = true
}
```

Better: restructure the middleware so verification and authorization are
separate concerns (see P1.4).

**Acceptance criteria:**

- A protected route with no required roles still invokes the handler for a valid
  token.
- An invalid token returns 401.
- A test covers both.

### P1.4 Auth middlewares are stacked, not alternatives

**Location:** `platform/httpserver.go:32-44`

```go
if conf.Auth.Server.Basic.Enabled && route.AuthRequired {
	handler = basicAuthMiddleware(handler, ...)
}
if conf.Auth.Server.OAuth.Enabled && route.AuthRequired {
	handler = oAuth2Middleware(handler, ...)
}
if conf.Auth.Server.LocalJwt.Enabled && route.AuthRequired {
	handler = localJwtAuthMiddleware(handler)
}
```

All enabled schemes are applied to every protected route as an AND. There is no
way to express "accept a local token **or** an OIDC token", which is a normal
requirement during a migration from local accounts to an identity provider. It
is also impossible to protect different routes with different schemes.

**Fix:** add an explicit per-route auth strategy and a chaining middleware:

```go
type AuthStrategy string

const (
	AuthNone       AuthStrategy = "none"
	AuthLocalJWT   AuthStrategy = "local-jwt"
	AuthOAuth      AuthStrategy = "oauth"
	AuthBasic      AuthStrategy = "basic"
	AuthLocalOrOIDC AuthStrategy = "local-or-oidc"
)

type Route struct {
	Path        string
	Method      string
	HandlerFunc http.HandlerFunc
	SlaMs       int64
	RolesRequired []string
	Auth        AuthStrategy // zero value: none
}
```

Chaining implementation:

```go
func anyAuthMiddleware(next http.Handler, candidates ...func(*http.Request) error) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var lastErr error
		for _, verify := range candidates {
			if err := verify(r); err == nil {
				next.ServeHTTP(w, r)
				return
			} else {
				lastErr = err
			}
		}
		Log.Warn("Authentication failed", zap.Error(lastErr))
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
	})
}
```

Keep `AuthRequired bool` for backward compatibility during the transition, but
mark it deprecated.

**Acceptance criteria:**

- A route can require local JWT only, OIDC only, or either.
- Existing configurations using `AuthRequired` keep working.
- Tests cover each strategy.

### P1.5 OIDC discovery runs at router construction and panics on failure

**Location:** `platform/middleware.go:85-104`

`oidc.NewProvider` is called while building the router and `panic`s if the
identity provider is unreachable. A transient IdP outage or a container start
ordering issue takes down the whole service, including routes that do not need
OIDC.

**Fix:** discover lazily with a mutex-guarded cache, retry on later requests, and
return `503` with `Retry-After` instead of panicking:

```go
var (
	providerMu sync.Mutex
	provider   *oidc.Provider
	verifier   *oidc.IDTokenVerifier
)

func getOIDCVerifier(ctx context.Context, conf OAuthConfig) (*oidc.IDTokenVerifier, error) {
	providerMu.Lock()
	defer providerMu.Unlock()

	if verifier != nil {
		return verifier, nil
	}

	discovered, err := oidc.NewProvider(ctx, conf.IdpWellKnownURL)
	if err != nil {
		return nil, fmt.Errorf("oidc discovery: %w", err)
	}

	verifier = discovered.Verifier(&oidc.Config{
		ClientID:             conf.ClientID,
		SupportedSigningAlgs: conf.AllowedAlgorithms,
	})
	provider = discovered
	return verifier, nil
}
```

**Acceptance criteria:**

- The server starts and serves non-OIDC routes while the IdP is down.
- OIDC routes return 503 instead of panicking.
- Discovery is retried after a failure.

### P1.6 `GetPlatformConfiguration` leaks its mutex on error

**Location:** `platform/config.go:40-90`

Several error paths return while holding `mutex`:

- `viper.ReadInConfig` error (non-`ConfigFileNotFoundError`)
- `viper.UnmarshalKey` error
- both `checkPlatformConfiguration` error returns

The next call to `GetPlatformConfiguration` blocks forever. In practice this
turns a configuration error into a hang.

**Fix:**

```go
func GetPlatformConfiguration() (*Config, error) {
	mutex.Lock()
	defer mutex.Unlock()

	if internalConfig != nil {
		return internalConfig, nil
	}

	// load, validate, assign
	conf, err := loadPlatformConfiguration()
	if err != nil {
		return nil, err
	}
	internalConfig = conf
	return internalConfig, nil
}
```

Also:

- Return `nil` rather than a partially populated config on error.
- Validate `HTTP.Server.ListeningAddress`, the BoltDB file name, JWT settings,
  and TLS file pairs in `checkPlatformConfiguration`.
- Replace `reflect.TypeOf(err) == reflect.TypeOf(viper.ConfigFileNotFoundError{})`
  with `errors.As`.

**Acceptance criteria:**

- A configuration error can be observed repeatedly without deadlock.
- A test calls the loader twice after an induced error.

### P1.7 Logger initialization ignores later configuration

**Location:** `platform/logging.go:44-84`

`InitializeLogger` runs in `package init`, before a consumer can call
`SetPlatformConfiguration`. As a result:

- `Component.ComponentName` is always `"Not Specified"` in production logs.
- Log level and file rotation settings come from defaults or `config.yml`, never
  from the programmatic configuration.
- `SetPlatformConfiguration` has no effect on logging.

There is also a missing unlock: when the logger is created, the mutex is never
released. It is currently harmless only because the function is not called again.

**Fix:**

- Remove `func init() { InitializeLogger() }`.
- Export an explicit `ConfigureLogger() error` that reads the current
  configuration, and call it from `SetPlatformConfiguration`.
- Or accept a `LoggerOptions` struct and construct the logger with `zap.New`.
- Always `defer` the unlock, or use `sync.Once`.

**Acceptance criteria:**

- After `SetPlatformConfiguration`, log lines carry the configured component
  name and respect the configured level.
- `SetPlatformConfiguration` can be called before first use without a deadlock.

### P1.8 Token values are logged

**Location:** `platform/jwt.go:106-114`

```go
Log.Error("Invalid JWT token", zap.String("token", tokenString))
```

A rejected token is still a bearer credential; logging it leaks material into
log files and log shippers.

**Fix:** log a hash prefix or omit the token entirely.

```go
Log.Error("Invalid JWT token", zap.String("tokenPrefix", tokenPrefix(tokenString, 8)))
```

Also use `errors.Is(err, jwt.ErrTokenExpired)` instead of `err == ...`, since the
JWT library wraps errors.

**Acceptance criteria:**

- No full token appears in logs.
- Expired and malformed tokens are distinguished correctly.

### P1.9 Role claim mapping is hard-coded

**Location:** `platform/middleware.go:79-83`

```go
type customClaims struct {
	Roles []string `json:"roles,omitempty"`
	...
}
```

Zitadel commonly exposes project roles as a map under
`urn:zitadel:iam:org:project:roles`, not a top-level `roles` array. The current
struct cannot express that.

**Fix:** add `RolesClaim string` (default `roles`) and support either:

- a JSON array of strings, or
- a JSON object whose keys are role names.

Document a dotted/colon path for nested claims, for example
`urn:zitadel:iam:org:project:roles`.

**Acceptance criteria:**

- A Zitadel-shaped claim grants the expected role.
- The claim path is configurable.
- Existing `roles` arrays continue to work.

### P1.10 Request bodies are unbounded

**Location:** `platform/marshalling.go:24-41`

`ioutil.ReadAll` reads an unlimited body into memory. A single large request can
exhaust the process.

**Fix:**

```go
func (j *jsonMarshallerOrganizer) ReadJsonRequest(w http.ResponseWriter, requestBody io.ReadCloser, outputType interface{}) error {
	defer requestBody.Close()

	const maxBody = 1 << 20 // 1 MiB, configurable
	decoder := json.NewDecoder(http.MaxBytesReader(w, requestBody, maxBody))
	decoder.DisallowUnknownFields()
	return decoder.Decode(outputType)
}
```

Note: this changes the signature to accept `http.ResponseWriter`. To avoid a
breaking change, add `ReadJsonRequestLimit(body io.ReadCloser, out interface{}, maxBytes int64)` and keep the old method as a wrapper with a default limit.

Also:

- Stop passing `&outputType` (pointer to interface); pass `outputType` directly.
- Replace deprecated `ioutil` with `io`.

**Acceptance criteria:**

- A body over the limit returns 413 or a clear error.
- Unknown fields are rejected (or behind an option).
- Existing handler call sites still compile.

### P1.11 No panic recovery or request correlation

**Location:** `platform/httpserver.go:14-67`

A panic in a handler is recovered by `net/http` per connection, but the client
gets a dropped connection and there is no single structured error record with a
request ID.

**Fix:** add middleware that:

- recovers panics, logs the stack, and writes a JSON `500`;
- generates or propagates `X-Request-ID`;
- adds the request ID to access logs.

**Acceptance criteria:**

- A deliberately panicking test handler returns `500` and does not crash the
  server.
- Every access log line contains a request ID.

---

## P2 — capability gaps for consumers like wdid

### P2.1 No access to the raw database handle

**Location:** `platform/boltdb.go` (all of it)

`dbBolt` is unexported and there is no `WithDB` accessor. Consumers therefore
cannot implement:

- hot snapshots via `db.View(func(tx *bolt.Tx) error { _, err := tx.WriteTo(w); return err })`
- `bolt check`-style integrity verification
- transactional multi-key writes
- ordered scans and pagination
- backups without stopping the service

The wdid PRD requires point-in-time snapshots and integrity checks, so this is a
functional blocker, not just convenience.

**Fix:** add a narrow, explicit API:

```go
// View runs a read-only transaction.
func View(fn func(tx *bolt.Tx) error) error

// Update runs a read-write transaction.
func Update(fn func(tx *bolt.Tx) error) error

// Snapshot streams a consistent point-in-time copy of the database.
func Snapshot(w io.Writer) error {
	if dbBolt == nil {
		return ErrBoltDBNoDBObject
	}
	return dbBolt.View(func(tx *bolt.Tx) error {
		_, err := tx.WriteTo(w)
		return err
	})
}

// Integrity reports whether the database can be opened and read.
func Integrity() error

// Stats exposes engine counters without leaking the handle.
func Stats() (map[string]string, error)
```

**Acceptance criteria:**

- `Snapshot` produces a file that reopens and reads back the same data.
- `Snapshot` does not block writes for the duration of a large copy (it holds a
  read transaction, which is expected; document the trade-off).
- A test snapshots, reopens the copy, and verifies a record.

### P2.2 No transactional multi-key writes

`SaveObject` is one transaction per key. Consumers writing a user plus an email
index cannot make the pair atomic, so a crash between writes leaves an
inconsistent index.

**Fix:** expose `Update(fn)` as above and add a small helper:

```go
func SaveObjects(bucket string, objects map[string]interface{}) error
```

**Acceptance criteria:**

- A failing second write rolls back the first.
- A test asserts the bucket is unchanged after a forced error.

### P2.3 `ReadAllObjects` loses ordering and cannot paginate

`ReadAllObjects` returns `map[string]string`, which destroys key order. Consumers
need chronological ranges (`startedAt` keys), pagination, and prefix scans.

**Fix:**

```go
func Keys(bucket string) ([]string, error)             // sorted by BoltDB key order
func Scan(bucket string, fn func(key, value []byte) error) error
func ScanPrefix(bucket string, prefix []byte, fn func(key, value []byte) error) error
func Count(bucket string) (int, error)
```

**Acceptance criteria:**

- Keys come back in lexicographic order.
- `ScanPrefix` visits only matching keys.
- A test inserts out-of-order keys and checks ordered output.

### P2.4 Migrate from `github.com/boltdb/bolt` to `go.etcd.io/bbolt`

`github.com/boltdb/bolt` is unmaintained (last release 2016). `bbolt` is the
maintained fork, is API-compatible for the calls used here, and is what the wdid
design requires (`bbolt v1.3.8`).

**Fix:**

- Replace the import with `go.etcd.io/bbolt`.
- Keep `bolt.Open(path, 0o600, &bolt.Options{Timeout: ...})`.
- Run the existing BoltDB tests unchanged to prove compatibility.

**Acceptance criteria:**

- `go.mod` no longer depends on `github.com/boltdb/bolt`.
- Existing database files open without migration.
- Tests pass against `bbolt`.

### P2.5 No graceful shutdown or HTTP timeouts

**Location:** `platform/httpserver.go:69-103`

`http.ListenAndServe` has no read-header timeout (slowloris exposure) and no
graceful shutdown, so in-flight requests are cut when the container stops.

**Fix:**

```go
server := &http.Server{
	Addr:              conf.HTTP.Server.ListeningAddress,
	Handler:           router,
	ReadHeaderTimeout: 5 * time.Second,
	ReadTimeout:       30 * time.Second,
	WriteTimeout:      60 * time.Second,
	IdleTimeout:       120 * time.Second,
}

go func() { errCh <- server.ListenAndServe() }()

select {
case <-ctx.Done():
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return server.Shutdown(shutdownCtx)
case err := <-errCh:
	return err
}
```

Add `StartHttpServerWithContext(ctx, routes)` and keep `StartHttpServer` as a
wrapper using `signal.NotifyContext`.

Also stop treating `http.ErrServerClosed` as an error in logs.

**Acceptance criteria:**

- SIGTERM drains in-flight requests before exit.
- Timeouts are configurable and have safe defaults.
- `ErrServerClosed` is not logged as a failure.

### P2.6 HTTP server closes the database implicitly

**Location:** `platform/httpserver.go:77-79`

```go
if config.Database.BoltDB.Enabled {
	defer Database.BoltDb.Close()
}
```

The HTTP server owning the database lifecycle prevents:

- running workers or CLI commands in the same process;
- closing the database before the HTTP listener stops;
- testing the router without opening a database.

**Fix:** remove the implicit close. The application owns resource lifecycle.
Optionally add a `platform.Shutdown()` helper that closes both in the right
order.

**Acceptance criteria:**

- Starting and stopping the HTTP server does not close an externally managed
  database.
- Existing example services call `defer platform.Database.BoltDb.Close()`.

### P2.7 Dead configuration fields

- `Route.AllowedContentType` is never applied (`httpserver.go:27` is commented
  out).
- `Config.Auth.Server.OAuth.AllowedAlgorithms` is parsed but unused by the OAuth
  middleware.
- `Config.Auth.Client.OAuth` is a slice of an unexported type, so consumers
  cannot populate it from code.
- `grpc` settings exist without an equivalent HTTP auth strategy.

**Fix:** either implement the fields or remove them. Dead configuration is worse
than no configuration because it suggests behaviour that does not exist.

**Acceptance criteria:**

- Every exported config field is read by production code or documented as
  reserved.
- A lint or test guards against unused auth fields.

### P2.8 `database.init` shadows the global

**Location:** `platform/database.go:13-20`

```go
func init() {
	Database := PlatformDatabases{}
	Database.BoltDb = boltDbDatabase{}
}
```

This assigns to a local variable. The global `Database` stays at its zero value.
It happens to work because `boltDbDatabase` has no fields, but it is misleading
and will break the moment state is added to the struct.

**Fix:** either remove the `init` entirely (the zero value is sufficient) or
assign the global explicitly.

**Acceptance criteria:**

- No shadowed package-level identifiers.
- A test asserts `Database.BoltDb` is usable immediately after import.

---

## P3 — polish

1. `platform/marshalling.go`: ignore or return `Write` errors; `Content-Type`
   should be set before `WriteHeader` (it already is, but the error path can
   write a status twice).
2. `platform/logging.go`: `logLevelStringToZapType` never returns an error despite
   `ErrInvalidLogLevel`; either validate and return the error or drop the error
   return.
3. `platform/config.go`: `writePlatformConfiguration` is unused; either wire it
   to a `SavePlatformConfiguration` API or remove it.
4. `platform/boltdb.go`: `RemoveDBFile` closes and deletes without a nil guard and
   without confirming the caller's intent. Rename to `DeleteDatabase` and require
   an explicit path match.
5. `platform/middleware.go`: `AllowCorsForLocalDevelopment` allows `*` methods
   and headers with no origin allow-list. Keep it dev-only and require
   `Conf.HTTP.Server.AllowCorsForLocalDevelopment` to be explicitly enabled.
6. Documentation: the README should call out that `config.yml` is optional, what
   the defaults are, and that `SetPlatformConfiguration` bypasses the file.
7. Add CI (`go vet`, `go test -race ./...`, `staticcheck`) — several of the bugs
   above are detectable by `go vet` or a race run.

---

## Suggested PR breakdown

Keep each PR reviewable and independently testable.

| PR | Contents | Risk |
| --- | --- | --- |
| 1 | P0.1–P0.6: BoltDB mode, timeout, nil-safe close, remove hack, error context | Low, high value |
| 2 | P1.1–P1.2: nil bucket and Bearer parsing | Low |
| 3 | P1.3–P1.5: auth strategy, role-less auth, lazy OIDC | Medium |
| 4 | P1.6–P1.8: config lock, logger configuration, token redaction | Low |
| 5 | P1.9–P1.11: claim mapping, body limits, recovery/request IDs | Medium |
| 6 | P2.1–P2.3: DB accessors, transactions, ordered scans | Low |
| 7 | P2.4: bbolt migration | Medium |
| 8 | P2.5–P2.6: graceful shutdown and lifecycle ownership | Medium |
| 9 | P2.7–P2.8 and P3 polish | Low |

## Test plan to add in goslow

```text
platform/boltdb_test.go
  TestOpenCreatesRestrictivePermissions
  TestReopenAfterCloseSucceeds
  TestOpenTimeoutWhenLocked
  TestReadObjectMissingBucketReturnsError
  TestSnapshotRoundTrip
  TestSaveObjectsRollsBackOnError
  TestKeysAreOrdered
  TestScanPrefixFilters

platform/middleware_test.go
  TestLocalJWTRejectsMalformedHeaders
  TestAuthNoRolesStillCallsHandler
  TestEitherAuthAcceptsLocalToken
  TestEitherAuthAcceptsOIDCToken
  TestOIDCDiscoveryFailureReturns503

platform/config_test.go
  TestGetPlatformConfigurationReleasesLockOnError
  TestInvalidConfigurationIsRejected
  TestSetPlatformConfigurationUpdatesLogger

platform/httpserver_test.go
  TestPanicHandlerReturns500
  TestGracefulShutdownDrainsRequests
  TestServerDoesNotCloseExternalDatabase
```

## Acceptance criteria for the whole change set

- A container can create its database on first run and reopen it after restart
  without manual `chmod` or `chown`.
- No exported goslow API can panic on normal error conditions.
- A protected route can accept local and OIDC tokens as alternatives.
- Consumers can take a consistent snapshot and run an integrity check without
  stopping the service.
- `go test -race ./...` passes.
- The consumer workarounds documented in `README.md` can be removed: the
  0600 pre-creation, the `ReadAllObjects` read path, and the custom combined auth
  middleware.
