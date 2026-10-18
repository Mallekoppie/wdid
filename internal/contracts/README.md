# wdid protobuf contracts

`internal/contracts/*.proto` is the single source of truth for the service API.
The Go service implements these RPCs and the Flutter web client calls them
through gRPC-Web using generated Dart stubs.

## Generation

```bash
make proto        # regenerate Go and Dart stubs
make proto-check  # regenerate in a temp dir and fail if internal/gen is stale
```

- **Go:** `internal/gen/wdid/v1/` — committed and never hand-edited.
- **Dart:** `web/lib/src/generated/` — gitignored; regenerate before Flutter
  analysis, tests, or builds.
- **Tooling:** `protoc`, `protoc-gen-go`, `protoc-gen-go-grpc`, and
  `protoc-gen-dart` (see `.devcontainer/README.md`).

`make proto` removes stale generated output before regenerating. Generation uses
`--go_opt=module=github.com/Mallekoppie/wdid`, so the `go_package` option
determines the output path under `internal/gen/`. Do not keep hand-written files
in either generated directory.

## Layout

- Keep protos flat under `internal/contracts/` until the Makefile glob and
  `-I` include path are updated for subpackages.
- Proto package: `wdid.v1`.
- Go package option:

  ```proto
  option go_package = "github.com/Mallekoppie/wdid/internal/gen/wdid/v1;wdidv1";
  ```

- File names follow the domain: `auth.proto`, `timer.proto`,
  `work_items.proto`, `initiatives.proto`, `check_ins.proto`,
  `summaries.proto`, `settings.proto`.
- Service names end in `Service` (`TimerService`, `WorkItemService`, ...).
- Hand-written Go implementations live in `internal/rpc/`, not in generated
  packages.

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
  page size.
- Request and response messages are distinct types.
- Do not expose BoltDB records, bucket names, auth internals, or secrets.
- Never trust a `user_id` or tenant field supplied by the client. Derive
  identity from validated metadata.

## Errors

Use `google.golang.org/grpc/status` errors. Never return `Unknown` for a
condition that has a specific code.

| Condition | Code |
| --- | --- |
| validation or invariant violation | `InvalidArgument` with `errdetails.BadRequest` field violations |
| missing, expired, or invalid token | `Unauthenticated` |
| authenticated but not allowed | `PermissionDenied` |
| unknown record | `NotFound` |
| duplicate or unique constraint | `AlreadyExists` |
| state conflict (timer already running, entry finalized) | `FailedPrecondition` |
| page size or payload too large | `ResourceExhausted` |
| unexpected failure | `Internal` (log details, return a generic message) |

## Transport

- Native gRPC uses `application/grpc`.
- Browsers use gRPC-Web: `application/grpc-web+proto` or
  `application/grpc-web-text`.
- Both are served on the same origin as the embedded Flutter app. Production is
  same-origin. Local cross-origin is limited to the Flutter dev server.
- The listener is configured explicitly (for example `WDID_GRPC_ADDR`), not by
  reusing the legacy HTTP address. Plain-HTTP local development uses h2c; any
  non-loopback listener uses TLS.
- Auth metadata: `authorization: Bearer <token>`.
- The Flutter client uses `GrpcWebClientChannel.xhr` with generated stubs. It
  must not hand-write JSON or call REST endpoints for capabilities that have
  RPCs.
- `grpc_health_v1` is always registered. Server reflection is enabled only in
  development.

## Review gates

The review agent treats these as blockers:

- a wire-incompatible or one-sided contract change;
- generated Go stub drift, uncommitted stubs, or hand-edited generated code;
- Dart stubs that were not regenerated before analysis or build;
- a browser capability without a verified gRPC-Web path;
- an auth bypass or an over-broad unauthenticated allowlist;
- a parallel REST/JSON endpoint that duplicates an RPC.
