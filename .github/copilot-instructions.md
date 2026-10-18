# Copilot instructions for wdid / LogLoop

## Project intent

This repository is a local-first personal work journal and review assistant for tracking time, outcomes, strategic initiative progress, support work, and AI-assisted check-in summaries.

Reference implementation:

- Use the project at `/var/home/Mallekoppie/code/source/ChaosGenerator` as the implementation reference for the Go service architecture and conventions.
- Where practical, follow the `goslow` framework patterns and helper functions used in that sample project rather than inventing a different service structure.

The product split is intentionally layered:

- Service layer owns the source of truth, persistence, validation, auth, backup logic, exports, and AI prompt generation.
- Web UI layer owns interaction flows, route screens, forms, timers, and display logic.
- The two layers communicate through explicit API contracts and shared domain rules, not by implicit cross-layer shortcuts.

## Core principles

1. Keep business logic in the service layer.
2. Keep interaction logic in the UI layer.
3. Preserve the design intent from the product docs and design plan.
4. Favor small, reviewable changes over broad refactors.
5. Prefer contract-first implementation over “just make it work in one place.”
6. Never introduce UI assumptions into storage, auth, or data models.
7. Never introduce storage assumptions into the UI layer.

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

- Go backend code, HTTP handlers, middleware, routes, and APIs
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
- fetching and rendering data from the service layer

### Shared rules

- UI must use the service contract, not local state as a substitute for server validation.
- Service must not depend on specific UI widgets or screen logic.
- Both layers must respect the design language and information architecture in the product docs.

## Routing rules for work

Use the following rule when deciding which agent should own a task:

- Backend, persistence, auth, RBAC, export, timer engine, AI synthesis, backup logic, or API contract changes belong to the service agent.
- Screen design, forms, layout, navigation, visual hierarchy, and frontend interactions belong to the UI agent.
- Tasks spanning both layers require a handoff: define the contract first, then implement each side against it.
- Reviewing completed work, checking contract alignment, and producing a merge verdict belong to the review agent. The review agent reports findings with evidence and does not edit code.

## Validation expectations

Before concluding a change is complete, validate the relevant area:

- Go backend changes: run the smallest relevant Go test or compile check
- UI changes: run the smallest relevant frontend test, build, or typecheck
- Contract changes: verify both sides of the boundary are implemented and aligned

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
- If a task touches the API layer, update the consumer side in the same change set.

## Handoff checklist

Before merging anything that changes both layers, confirm:

- the service contract is defined and stable
- UI state matches the contract shape
- validation and error states are handled
- the task still matches the design documents
- there is no duplicate logic across layers

## Default task selection

If no specific owner is stated, choose the most local owner:

- data model, storage, or API → service agent
- screen flow or interface detail → UI agent

When crossing boundaries, keep the contract as the source of truth and keep each agent in its lane.
