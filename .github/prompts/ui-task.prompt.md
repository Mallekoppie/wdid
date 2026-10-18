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

1. Read `.github/copilot-instructions.md`, `plan.md`, and `stich-design.md` before changing anything.
2. Treat the service layer as the source of truth; do not reimplement backend rules in the client.

## Method

1. Identify the target route and the screen states involved (loading, empty, error, success).
2. Follow the documented information architecture, keyboard-first flows, and quiet-density styling.
3. Consume the existing service contract; if a required field or endpoint is missing, stop and request the contract rather than inventing local behavior.
4. Implement the change in small, reviewable steps.

## Done when

- the change matches the design docs and route structure
- the relevant build, typecheck, or frontend test passes (report the exact command and result)
- no business rule is duplicated outside the service layer
