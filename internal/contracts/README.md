# wdid protobuf contracts

`internal/contracts/*.proto` is the single source of truth for the service API.
The Go service implements the generated Connect handlers and the Flutter web
client calls them through gRPC-Web using generated Dart stubs. Connect serves
Connect, native gRPC, and gRPC-Web from one handler.

The domain model behind these contracts is defined in `plan.md`; `GLOSSARY.md` is
canonical for domain terms. This file covers wire and generation conventions only.

## Generation

```bash
make proto        # regenerate Go and Dart stubs
make proto-check  # regenerate in a temp dir and fail if Go or Dart stubs are stale
make check        # runs lint, proto-check, and both test suites
```

- **Go messages:** `internal/gen/wdid/v1/` — committed and never hand-edited.
- **Connect handlers:** `internal/gen/wdid/v1/wdidv1connect/` — committed and
  never hand-edited.
- **Dart:** `web/lib/src/generated/` — gitignored; regenerate before Flutter
  analysis, tests, or builds.
- **Tooling:** `protoc`, `protoc-gen-go`, `protoc-gen-connect-go`, and
  `protoc-gen-dart` (see `.devcontainer/README.md`). Do not install or use
  `protoc-gen-go-grpc`.

`make proto` removes stale generated output before regenerating. Generation uses
`--go_opt=module=github.com/Mallekoppie/wdid` and
`--connect-go_opt=module=github.com/Mallekoppie/wdid`, so the `go_package` option
determines the output paths under `internal/gen/`. Do not keep hand-written files
in either generated directory.

## Layout

- Keep protos flat under `internal/contracts/` until the Makefile glob and
  `-I` include path are updated for subpackages.
- Proto package: `wdid.v1`.
- Go package option:

  ```proto
  option go_package = "github.com/Mallekoppie/wdid/internal/gen/wdid/v1;wdidv1";
  ```

- File names follow the domain: `auth.proto`, `categories.proto`,
  `entries.proto`, `milestones.proto`, `notes.proto`, `timer.proto`,
  `check_ins.proto`, `summaries.proto`, `settings.proto`.
- Service names end in `Service` (`AuthService`, `CategoryService`,
  `EntryService`, `MilestoneService`, `NoteService`, `TimerService`,
  `CheckInService`, `SummaryService`, `SettingsService`).
- Hand-written Go implementations live in `internal/rpc/`, implement
  `platform.ConnectService`, and register the generated `wdidv1connect` handler.
  Never edit generated packages.

## Wire rules

- Field numbers are permanent. Never renumber or reuse one. Use `reserved` for
  removed numbers and names.
- Changes are additive and wire-compatible unless a break is explicitly
  approved. Removing a field, changing its type, or changing a method signature
  is a breaking change.
- Every enum has a zero value named `<ENUM>_UNSPECIFIED = 0`. Enum values are
  prefixed with the enum name.
- Instants use `google.protobuf.Timestamp` in UTC.
- Local calendar dates use `YYYY-MM-DD` strings so day-boundary rules stay
  explicit.
- Durations use `google.protobuf.Duration`. Do not mix minutes and seconds in
  the same message.
- List RPCs use `page_size`, `page_token`, and `next_page_token`. The server caps
  page size. Small fixed lists (`ListBackups`, `ListPromptTemplates`) are exempt
  and return the complete collection without paging fields.
- Request and response messages are distinct types.
- Do not expose BoltDB records, bucket names, auth internals, or secrets.
- Never trust a `user_id` or tenant field supplied by the client. Derive
  identity from validated metadata.

## Errors

Use Connect errors with `connect.NewError`. Never return a raw error for a
condition that has a specific code. Attach validation details with
`connect.NewErrorDetail` and `google.rpc.BadRequest`. Do not import
`google.golang.org/grpc/status`.

| Condition | Connect code |
| --- | --- |
| validation or invariant violation | `connect.CodeInvalidArgument` with `BadRequest` field violations |
| missing, expired, or invalid token | `connect.CodeUnauthenticated` |
| authenticated but not allowed | `connect.CodePermissionDenied` |
| unknown record | `connect.CodeNotFound` |
| duplicate or unique constraint | `connect.CodeAlreadyExists` |
| state conflict (timer already running, entry finalized) | `connect.CodeFailedPrecondition` |
| page size or payload too large | `connect.CodeResourceExhausted` |
| unexpected failure | `connect.CodeInternal` (log details, return a generic message) |

## Transport

- Connect serves Connect, native gRPC (`application/grpc`), and gRPC-Web
  (`application/grpc-web+proto` / `application/grpc-web-text`) from one handler.
- Prefer `platform.StartApplicationServerWithContext` for the combined Connect,
  optional HTTP, and embedded Flutter app. Use
  `platform.StartConnectServerWithContext` for an RPC-only server.
- One explicit application listener serves the RPC surface and the embedded UI.
  Production is same-origin. Local cross-origin is limited to the Flutter dev
  server.
- Set `Grpc.Server.Auth` explicitly. For wdid, use
  `platform.AuthLocalOrOIDC` when Zitadel is enabled and
  `platform.AuthLocalJWT` for a local-only deployment. Declare public RPCs in
  `Auth.Server.UnauthenticatedPaths` and admin RPCs in
  `Grpc.Server.ProcedureRoles`. Do not use `AuthRequired` or
  `Grpc.Server.UnAuthenticatedPaths`.
- Auth metadata: `authorization: Bearer <token>`. Both unary and stream
  handlers use the same auth interceptor and allow-list.
- Enable health with `Grpc.Server.HealthEnabled` and reflection only in
  development with `Grpc.Server.ReflectionEnabled`. Provide fully qualified
  `ServiceNames` for both.
- Configure exact origins in `HTTP.Server.AllowedOrigins` and
  `Grpc.Server.AllowedOrigins`. Never use wildcard origins.
- The canonical first slice is `AuthService` plus health; it proves generation,
  registration, gRPC-Web, metadata auth, roles, and code mapping before domain
  RPCs are added.
  - Public: `/wdid.v1.AuthService/RegisterAccount`,
    `/wdid.v1.AuthService/Login`, `/wdid.v1.AuthService/GetAuthConfig`.
  - Protected: `/wdid.v1.AuthService/GetCurrentUser`.
  - `GetCurrentUser` derives the account from goslow's verified auth context; it
    never trusts a user id in the request.
- The Flutter client opens one `GrpcOrGrpcWebClientChannel` in
  `web/lib/data/grpc_channel.dart` and calls generated stubs over gRPC-Web. It
  must not hand-write JSON or call REST endpoints for capabilities that have
  RPCs.

## Review gates

The review agent treats these as blockers:

- a wire-incompatible or one-sided contract change;
- generated message or Connect stub drift, uncommitted stubs, or hand-edited
  generated code;
- `*_grpc.pb.go` output or grpc-go/improbable-eng imports;
- Dart stubs that were not regenerated before analysis or build;
- a browser capability without a verified gRPC-Web path;
- an auth bypass, implicit auth, or an over-broad unauthenticated allowlist;
- missing `ProcedureRoles` for admin RPCs;
- wildcard CORS or missing health/reflection service names when enabled;
- a parallel REST/JSON endpoint that duplicates an RPC;
- use of removed goslow APIs.
