---
description: "Start a scoped backend task with the wdid service agent"
agent: "service-agent"
argument-hint: "Backend task, affected RPCs, messages or models, acceptance criteria"
---

Work on the following service-layer task in the wdid repository.

## Task

${selection}

If no text was selected, use the task described in the chat input after this prompt.

## Required context

1. Read `.github/copilot-instructions.md`, `internal/contracts/README.md`, `plan.md`, and `GLOSSARY.md` before changing anything.
2. Follow the Go service structure and `goslow` framework patterns used in `/var/home/Mallekoppie/code/source/ChaosGenerator`.

## Method

1. Restate the contract: affected protobuf files, Connect services, RPCs, message fields, field numbers, auth requirements, and validation rules.
2. Implement `platform.ConnectService` via the generated `wdidv1connect` handlers; do not use grpc-go, `GRPCService`, or `StartGrpcServer*`.
3. Keep business logic in the service layer; do not add UI or screen assumptions.
4. Preserve wire compatibility: do not renumber or reuse fields, reserve removals, and keep enum zero values.
5. Keep Connect/gRPC/gRPC-Web working for every browser-facing RPC; use exact-origin CORS and no wildcard origins.
6. Set `Grpc.Server.Auth` explicitly, declare public paths in `Auth.Server.UnauthenticatedPaths`, and admin RPCs in `Grpc.Server.ProcedureRoles`.
7. Map failures to Connect codes and `google.rpc.BadRequest` field violations.
8. Regenerate stubs with `make proto` using `protoc-gen-connect-go` and implement in small, reviewable steps.

## Done when

- the implementation compiles and relevant Go tests pass (report the exact command and result)
- `make proto-check` passes and generated message + Connect stubs are committed
- the proto delta, auth strategy, roles, health/reflection, and CORS requirements are documented for the UI agent
- no persistence, auth, or validation rule is left to the client
