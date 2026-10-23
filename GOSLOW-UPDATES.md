# goslow review status — Connect transport

## Verdict

`fixes-for-wdid` at `68f7518` is **mergeable**. The previous blockers are fixed,
the branch is internally consistent, and the verification suite passes with the
required Go toolchain.

## Verification

Run with `GOTOOLCHAIN=auto` against `go 1.27.2`:

```text
go vet ./...                       pass
go test ./...                      pass
go test -race ./...                pass
gofmt -l .                         clean
go mod tidy -diff                  clean
staticcheck ./... (v0.8.2, CI)     clean
example modules build + test       pass
git diff --check                    clean
```

The previous regressions are covered by tests in
`platform/review_regression_test.go`, including:

- failed runtime initialization leaves no cached config
- default HTTP and gRPC listener addresses
- health/reflection requiring service names
- metrics lifecycle and single metrics listener
- local-JWT verifier misses not logging errors
- OIDC success without local-JWT error noise
- bounded HTTP routes with unbounded Connect streams

## Integration status

wdid now consumes goslow at the merged `master` revision
(`v0.0.0-20261018185216-5eded094f41a`), the module directive is `go 1.27.2`, and
`make` exports `GOTOOLCHAIN=auto` so an older local toolchain can fetch the
matching Go release until the dev container is rebuilt.

`make proto` uses `protoc-gen-connect-go` and generates:

- `internal/gen/wdid/v1/*.pb.go`
- `internal/gen/wdid/v1/wdidv1connect/*.connect.go`

The first live slice is `wdid.v1.AuthService` with Connect, native gRPC, and
gRPC-Web transport tests.

## Non-blocking follow-ups

1. **Custom-handler transport setup.** `NewConnectHandler` and
   `NewApplicationHandler` are usable with a caller-owned `http.Server`, but the
   h2c/HTTP2 setup lives in the unexported `configureHTTPProtocols`. Export a
   helper or document that custom servers must set `http.Protocols` themselves.
2. **Handler TLS fields.** `ConnectServerOptions.TLSEnabled` and
   `ApplicationServerOptions.TLSEnabled` are only consumed by the `Serve*`
   helpers, not by handler construction. Clarify the docs or remove the fields
   from the handler-only options.
3. **OIDC claims context.** The OAuth verifier exposes roles, username, and
   issuer, but not the verified subject/email claims. wdid re-verifies the OIDC
   token in `GetCurrentUser` to resolve the local account. Export the verified
   OIDC claims (or subject/email) on the request context to avoid a second
   verification.
4. **HTTP auth metrics.** Denied HTTP auth is recorded by the auth middleware and
   then counted again as `anonymous` by `loggingMiddleware`. Set the outcome to
   `denied` in the request context before writing the auth error.
5. **HTTP timeout semantics.** `http.TimeoutHandler` bounds the response but does
   not cancel the underlying HTTP handler. Document that or wrap the handler with
   a cancellable context/timeout.
6. **Deprecated indirect dependency.** `github.com/golang/protobuf` remains as a
   deprecated indirect dependency. It is not used directly; remove it if a
   dependency upgrade allows it.
7. **Metrics listener lifetime.** Disabling metrics stops recording but leaves an
   already-running metrics listener bound until shutdown. This is acceptable if
   documented; otherwise stop/rebind it on config changes.

## Intentional decisions — do not undo

- Connect is the only RPC transport. Do not reintroduce grpc-go,
  `improbable-eng/grpc-web`, or the old gRPC helper APIs.
- Deprecated wrappers and fields are removed:
  `GRPCService`, `StartGrpcServer*`, `AuthRequired`,
  `Grpc.Server.UnAuthenticatedPaths`, `StartHttpServerWithHtmlHosting`,
  `RemoveDBFile`, and `AllowCorsForLocalDevelopment`.
- No compatibility shims. Breaking changes are intentional.
- No package `init()` side effects.
- No wildcard CORS.
- No secrets or full tokens in logs.
- Public RPCs use `Auth.Server.UnauthenticatedPaths`; admin RPCs use
  `Grpc.Server.ProcedureRoles`; `Grpc.Server.Auth` is explicit.

## Merge checklist

- [x] Connect/gRPC/gRPC-Web transport and streaming tests pass.
- [x] Explicit auth strategy, procedure roles, and public-path allow-list work.
- [x] Connect request ID, recovery, logging, and timeout interceptors work.
- [x] Health and reflection are configurable and validated.
- [x] HTTP and gRPC-Web CORS use exact origins.
- [x] Configuration defaults, validation, and rollback work.
- [x] Logger reconfiguration is race-free.
- [x] BoltDB API and lifecycle tests pass.
- [x] Deprecated APIs are removed.
- [ ] wdid Go directive and dependency bump after merge.
- [ ] Optional follow-ups above.
