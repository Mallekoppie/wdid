---
description: "Review completed wdid service or UI implementation work"
agent: "review-agent"
argument-hint: "Change set to review, affected layers, acceptance criteria"
---

Review the following completed work in the wdid repository.

## Task

${selection}

If no text was selected, use the change set and acceptance criteria described in
the chat input after this prompt.

## Required context

1. Read `.github/copilot-instructions.md`, `plan.md`, `stich-design.md`, and
   `GOSLOW-UPDATES.md` before judging the implementation.
2. Inspect the full change set with `git status` and `git diff`, and read the
   changed files in context.
3. Compare the result against the ownership rules in
   `.github/agents/service-agent.agent.md` and
   `.github/agents/ui-agent.agent.md`.

## Method

1. Confirm the contract: affected routes, payload shapes, validation rules, and
   whether both layers were updated together.
2. Verify the layering boundaries: no business logic in the UI, no UI
   assumptions in the service, no duplicated validation.
3. Check correctness, security, and the required UI states.
4. Run the relevant Makefile verification commands yourself and record the exact
   results.
5. Produce findings with file and line references and a clear verdict.

## Done when

- the verdict is one of **Approve**, **Approve with changes**, or
  **Request changes**
- every finding has a severity, location, evidence, impact, and owning agent
- verification commands and their results are reported
- blockers and major findings are routed to the correct agent, with no code
  changes made by the reviewer
