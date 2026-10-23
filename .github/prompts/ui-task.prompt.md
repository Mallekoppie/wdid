---
description: "Start a scoped UI task with the wdid UI agent"
agent: "ui-agent"
argument-hint: "Screen or interaction change, target route, acceptance criteria"
---

Work on the following UI-layer task in the wdid repository.

## Task

${selection}

If no text was selected, use the task described in the chat input after this prompt.

## Required context

1. Read `.github/copilot-instructions.md`, `internal/contracts/README.md`, `plan.md`, and `GLOSSARY.md` before changing anything.
2. Treat the service layer and generated protobuf contract as the source of truth; do not reimplement backend rules in the client.

## Method

1. Identify the target route and the screen states involved (loading, empty, error, success, invalid input).
2. Follow the documented information architecture, keyboard-first flows, and quiet-density styling.
3. Run `make proto` and consume the generated Dart clients over a gRPC-Web channel; do not hand-write JSON DTOs or REST calls.
4. Apply auth metadata, explicit deadlines, stream cancellation, and `GrpcError` mapping.
5. If a required field or RPC is missing, stop and request the contract from the service agent rather than inventing local behavior.
6. Implement the change in small, reviewable steps.

## Done when

- the change matches the design docs and route structure
- the relevant Flutter analysis, build, or test passes (report the exact command and result)
- the client uses generated stubs and `GrpcWebClientChannel`, with no `package:http` JSON path
- no business rule is duplicated outside the service layer
