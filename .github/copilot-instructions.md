# Copilot instructions for wdid / LogLoop

## Project intent

This repository is a local-first personal work journal and review assistant for tracking time, outcomes, strategic initiative progress, support work, and AI-assisted check-in summaries.

Reference implementation:

- Use the project at `/var/home/Mallekoppie/code/source/ChaosGenerator` as the implementation reference for the Go service architecture and conventions.
- Where practical, follow the `goslow` framework patterns and helper functions used in that sample project rather than inventing a different service structure.

The product split is intentionally layered:

- Service layer owns the source of truth, persistence, validation, auth, backup logic, exports, and AI prompt generation.
- Web UI layer owns interaction flows, route screens, forms, timers, and display logic.
- The two layers communicate through explicit protobuf contracts and shared domain rules, not by implicit cross-layer shortcuts.

## Core principles

1. Keep business logic in the service layer.
2. Keep interaction logic in the UI layer.
3. Preserve the design intent from the product docs and design plan.
4. Favor small, reviewable changes over broad refactors.
5. Prefer contract-first implementation over “just make it work in one place.”
6. Never introduce UI assumptions into storage, auth, or data models.
7. Never introduce storage assumptions into the UI layer.

## Transport and contract rules

The service uses goslow's Connect transport. Connect serves Connect, native gRPC,
and gRPC-Web from one handler; the browser client uses gRPC-Web. There is one
protobuf contract and no parallel REST/JSON surface for the same capability.

- `internal/contracts/*.proto` is the single source of truth for the service API.
  Both agents implement against it; neither invents a side channel.
- The Go service implements `platform.ConnectService` and registers the generated
  Connect handlers. goslow serves Connect, native gRPC, and gRPC-Web on the same
  origin as the embedded Flutter app.
- `make proto` generates message stubs in `internal/gen/wdid/v1/` and Connect
  handlers in `internal/gen/wdid/v1/wdidv1connect/` using
  `protoc-gen-connect-go`. Both are committed and never hand-edited. Do not
  generate `*_grpc.pb.go`.
- The Flutter web UI consumes generated Dart stubs through a gRPC-Web channel
  (`GrpcWebClientChannel.xhr`). It must not hand-write JSON DTOs or call REST
  endpoints for capabilities that have RPCs.
- Generated Dart stubs in `web/lib/src/generated/` are gitignored, so `make
  proto` is required before Flutter analysis, tests, or builds.
- Contract changes are additive and wire-compatible unless a break is explicitly
  approved. Never renumber or reuse field numbers; use `reserved` for removals.
- Authentication travels as `authorization: Bearer <token>` metadata and is
  validated by goslow's Connect auth interceptor for both local JWTs and Zitadel
  ID tokens. Set `Grpc.Server.Auth` explicitly (`AuthLocalOrOIDC` when Zitadel
  is enabled, `AuthLocalJWT` for local-only), declare public RPCs in
  `Auth.Server.UnauthenticatedPaths`, and admin RPCs in
  `Grpc.Server.ProcedureRoles`.
- Enable Connect health with `Grpc.Server.HealthEnabled`; enable reflection only
  in development. Configure exact origins in `HTTP.Server.AllowedOrigins` and
  `Grpc.Server.AllowedOrigins`; never use wildcard CORS.
- Existing REST handlers in `internal/api/` are legacy. Do not extend them; retire
  them as their RPC replacements land.
- Do not use the removed goslow APIs: `GRPCService`, `StartGrpcServer`,
  `StartGrpcServerWithWeb`, `AuthRequired`, `Grpc.Server.UnAuthenticatedPaths`,
  `StartHttpServerWithHtmlHosting`, or `RemoveDBFile`.

See `internal/contracts/README.md` for the full wire and generation conventions.

## Deployment and auth model

For the initial local deployment:

- use a local Zitadel instance for OIDC authentication
- configure the app to integrate with Zitadel as the identity provider
- allow initial login using a local user account
- require a registration secret for sign-up flows during the initial rollout
- keep the architecture compatible with a hosted deployment model as the product grows, without compromising the local-first developer setup

This should be treated as the baseline deployment and auth pattern unless a task explicitly changes the identity architecture.

## Ownership boundaries

### Service agent owns

- Go backend code, Connect service implementations, interceptors, and server wiring
- protobuf contracts in `internal/contracts/`, message stubs in `internal/gen/wdid/v1/`, and Connect handlers in `internal/gen/wdid/v1/wdidv1connect/`
- Connect/gRPC/gRPC-Web serving, exact-origin CORS, TLS, health, and development reflection
- database schema, storage buckets, models, validation, and migration logic
- auth, RBAC, OIDC, invite validation, and session flow
- timer lifecycle, work entry persistence, initiative tracking, and support logs
- export generation (JSON, Markdown, CSV)
- AI summary prompt content and structured payload generation
- backup and restore logic, snapshot creation, integrity checks

### UI agent owns

- pages, route structure, and navigation
- timer widgets and quick-entry flows
- forms, cards, tables, modals, and filters
- keyboard-first interactions and per-screen UX behavior
- visual presentation, layout, status badges, and state transitions
- the gRPC-Web client adapter and generated-Dart consumption from the service layer

### Shared rules

- UI must use the service contract, not local state as a substitute for server validation.
- Service must not depend on specific UI widgets or screen logic.
- Both layers must respect the design language and information architecture in the product docs.
- UI may read generated protobuf types but must not edit `.proto` files or generated stubs.
- Contract gaps are reported to the owning agent; the consumer never patches the wire format locally.

## Routing rules for work

Use the following rule when deciding which agent should own a task:

- Backend, persistence, auth, RBAC, export, timer engine, AI synthesis, backup logic, Connect server wiring, Connect/gRPC/gRPC-Web serving, or protobuf contract changes belong to the service agent.
- Screen design, forms, layout, navigation, visual hierarchy, frontend interactions, and gRPC-Web client consumption belong to the UI agent.
- Tasks spanning both layers require a handoff: define and generate the protobuf contract first, then implement each side against the generated stubs.
- Reviewing completed work, checking wire compatibility, generated-stub state, transport boundaries, contract alignment, and producing a merge verdict belong to the review agent. The review agent reports findings with evidence and does not edit code.

## Validation expectations

Before concluding a change is complete, validate the relevant area:

- Go backend changes: run the smallest relevant Go test or compile check
- UI changes: run the smallest relevant frontend test, build, or typecheck
- Contract changes: run `make proto-check`, then verify both the Connect service registration and the generated-typed client usage
- Transport changes: verify a real browser-shaped request (`application/grpc-web+proto` or `grpc-web-text`) reaches the service, not only a native gRPC call
- Server changes: run `go vet ./...` and the targeted Go tests; handle the error returned by `platform.SetPlatformConfiguration`

Do not claim completion without fresh evidence from a relevant verification command.

## Design and product alignment

Follow the intent in the product and design docs:

- single-user, local-first, privacy-preserving
- fast capture under five seconds
- keyboard-first and minimal friction
- initiative-based attribution, support tracking, and outcome evidence
- review-ready summaries and exports
- quiet, developer-tool aesthetic with compact density

When requirements are ambiguous, prefer the documented product intent over ad hoc assumptions.

## Working style

- Keep changes narrowly scoped and easy to review.
- Prefer explicit types, validation, and clear names.
- Avoid broad “cleanup” refactors unrelated to the task.
- Preserve existing patterns unless the change explicitly requires a consistent redesign.
- If a task touches the protobuf contract, regenerate stubs and update the consumer side in the same change set.

## Handoff checklist

Before merging anything that changes both layers, confirm:

- the protobuf contract is defined, generated, and wire-compatible
- generated message and Connect stubs are committed and `make proto-check` passes
- the service implements and registers every `platform.ConnectService` and serves the browser over gRPC-Web
- explicit `Grpc.Server.Auth`, `ProcedureRoles`, health, reflection, and exact-origin CORS are configured
- UI state matches the generated contract shape
- validation and Connect error codes are handled
- the task still matches the design documents
- there is no duplicate logic across layers and no parallel REST/JSON path

## Default task selection

If no specific owner is stated, choose the most local owner:

- data model, storage, protobuf contract, or Connect/gRPC/gRPC-Web transport → service agent
- screen flow or interface detail → UI agent

When crossing boundaries, keep the contract as the source of truth and keep each agent in its lane.
