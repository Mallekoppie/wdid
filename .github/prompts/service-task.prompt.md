---
description: "Start a scoped backend task with the wdid service agent"
agent: "service-agent"
argument-hint: "Backend task, affected endpoints or models, acceptance criteria"
---

Work on the following service-layer task in the wdid repository.

## Task

${selection}

If no text was selected, use the task described in the chat input after this prompt.

## Required context

1. Read `.github/copilot-instructions.md`, `plan.md`, and `stich-design.md` before changing anything.
2. Follow the Go service structure and `goslow` framework patterns used in `/var/home/Mallekoppie/code/source/ChaosGenerator`.

## Method

1. Restate the contract: affected routes, request/response shapes, storage buckets, and validation rules.
2. Keep business logic in the service layer; do not add UI or screen assumptions.
3. Flag anything the UI must know about (payload shape, error states, required fields).
4. Implement the change in small, reviewable steps.

## Done when

- the implementation compiles and relevant Go tests pass (report the exact command and result)
- the API or domain contract is documented for the UI agent
- no persistence, auth, or validation rule is left to the client
