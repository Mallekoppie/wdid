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

1. Read `.github/copilot-instructions.md`, `internal/contracts/README.md`, `plan.md`, and `stich-design.md` before changing anything.
2. Follow the Go service structure and `goslow` framework patterns used in `/var/home/Mallekoppie/code/source/ChaosGenerator`.

## Method

1. Restate the contract: affected protobuf files, services, RPCs, message fields, field numbers, auth requirements, and validation rules.
2. Keep business logic in the service layer; do not add UI or screen assumptions.
3. Preserve wire compatibility: do not renumber or reuse fields, reserve removals, and keep enum zero values.
4. Keep gRPC-Web working for every browser-facing RPC, including CORS preflight in local development.
5. Map failures to gRPC status codes and `errdetails.BadRequest` field violations.
6. Regenerate stubs with `make proto` and implement in small, reviewable steps.

## Done when

- the implementation compiles and relevant Go tests pass (report the exact command and result)
- `make proto-check` passes and generated Go stubs are committed
- the proto delta and auth requirements are documented for the UI agent
- no persistence, auth, or validation rule is left to the client
