# wdid work plan — updated 2026-10-23

> **Status:** Active. `plan.md` is the canonical product and design source;
> `GLOSSARY.md` defines the domain terms; `docs/adr/` records the hard-to-reverse
> decisions. This file is the execution order.

## Execution rules

1. **Replace the old model in place.** No compatibility layer and no data
   migration: there is no `data/` or `backups/` directory and no user data.
2. **RPC-only through Connect.** M1 deletes the legacy REST domain surface.
   `/healthz` remains the only non-RPC route.
3. **M1 defines the full data layer.** Later milestones add contracts, RPCs, and
   screens; they do not reshape the store.
4. **Work in vertical slices.** Each milestone runs
   `proto → domain/store → service → generated Dart client → owning screen`.
5. **The UI consumes generated clients.** `DemoWdidRepository` survives only for
   screens whose slice has not landed and is deleted in M8.
6. **No client-side authoritative totals.** Period aggregates come from
   `SummaryService.GetPeriodReport`.
7. **Every slice ships** Connect tests (unary and gRPC-Web), domain tests, and the
   owning screen's loading, empty, error, and validation states.

## Current state (2026-10-23)

- Go module `github.com/Mallekoppie/wdid`, `go 1.27.2`, goslow merged revision
  `v0.0.0-20261018185216-5eded094f41a`.
- Connect serves one service: `wdid.v1.AuthService` (`RegisterAccount`, `Login`,
  `GetAuthConfig`, `GetCurrentUser`). Generated Go and Connect stubs are
  committed.
- Legacy REST surface in `internal/api/`: auth, initiatives, entries, timer,
  summary, export.
- Domain in `internal/domain/`: `User`, `Initiative`, `Entry` with `kind`, and
  `ActiveTimer`. Store buckets: `sys:users`, `sys:user_emails`,
  `sys:user_credentials`, `user_<id>:initiatives`, `user_<id>:entries`,
  `user_<id>:timer`.
- The Flutter client runs on `DemoWdidRepository`; screens exist for every route.
  There are no REST calls from `web/lib`.
- No check-in, note, settings, milestone, or backup persistence exists.
- No `data/` or `backups/` directory exists, so there is nothing to migrate.
- The dev container still has Go 1.26.9; the Makefile exports `GOTOOLCHAIN=auto`.
- Verification baseline: `make proto-check`, `make build`, `go test -race ./...`,
  `cd web && flutter analyze`, `cd web && flutter test`.

---

## M1 — Identity, taxonomy, and data core

Goal: the full data layer, bootstrap/invite auth, categories RPC, and no REST.

### Domain and store

- [ ] Replace `internal/domain` types with `Category`, `Subcategory`,
      `WorkEntry`, `Milestone`, `Note`, `CheckIn`, and `Settings`; delete
      `Initiative`, `EntryKind`, and `SupportDetail` (`person`/`team` move onto
      the entry).
- [ ] Add enums with validity checks: category role
      (`initiative|support|other`), check-in kind (`manager|personal`), check-in
      state, and audience.
- [ ] Rewrite validation: category role is immutable; a subcategory must belong
      to its category; a support-role category requires a person; minutes and
      overlap rules follow `plan.md` §8.3.
- [ ] Rewrite `internal/store` for the buckets in `plan.md` §8.2, including the
      per-user entry indexes.
- [ ] Seed `Initiatives`, `Support` (+ `Review`, `Pair`, `Unblock`, `Mentor`,
      `Incident`, `Other`), and `Other` (+ `Meetings`, `Admin`, `Learning`,
      `Unplanned`) at account creation.
- [ ] Set `sys:meta.schema_version = 1`; no migration code (no data).
- [ ] Tests: round-trip every bucket, cross-user isolation, seeds, archive-only
      when referenced, role immutability, subcategory/category constraint, and
      support person requirement.

### Identity and invites

- [ ] Replace `WDID_REGISTRATION_SECRET` with `WDID_BOOTSTRAP_SECRET`; the first
      account becomes `admin`.
- [ ] Add `sys:invites` and single-use invite codes.
- [ ] Add CLI: `wdid invite create|list|revoke`.
- [ ] Update `auth.proto` and `AuthService.RegisterAccount` to accept an invite
      code, or the bootstrap secret for the first account; update
      `GetAuthConfig`.
- [ ] Keep the Zitadel OIDC path unchanged.
- [ ] Tests: first account admin, a later account requires an invite, invites are
      single-use, and missing/invalid invites map to the right Connect code.

### Surface cleanup

- [ ] Delete `internal/api` and its tests; keep `/healthz` as the only non-RPC
      route.
- [ ] Remove `gorilla/mux` if nothing else uses it; update `cmd/wdid/main.go`.
- [ ] Remove the legacy REST sections from `README.md` once the routes are gone.

### Contracts and RPC

- [ ] Add `categories.proto` (`CategoryService`) and `settings.proto`
      (`GetSettings`, `UpdateSettings`; backup methods arrive in M7).
- [ ] Implement `CategoryService` in `internal/rpc/`.
- [ ] Regenerate Go and Dart stubs; run `make proto-check`.
- [ ] Tests: Connect unary and gRPC-Web, auth strategy, and Connect error
      mapping.

### UI

- [ ] Replace demo auth with generated `AuthService` clients; login and
      invite-code registration.
- [ ] Wire Settings → Categories to `CategoryService` (list, create, rename,
      archive, subcategories, role selection).
- [ ] Keep the demo adapter for screens without a service yet.

### Acceptance

- Two accounts cannot read each other's data.
- Invite codes are single-use and the first account is admin.
- Categories and subcategories round-trip; roles cannot change.
- Settings timezone and review cadence persist.
- No domain REST route remains.
- `make check` passes.

---

## M2 — Capture

- [ ] Add `entries.proto` and `timer.proto`; implement `EntryService` and
      `TimerService`.
- [ ] Add `summaries.proto` with `GetPeriodReport` — the only aggregation
      source.
- [ ] Timer lifecycle: start, pause, resume, stop; paused time excluded; stops
      under one minute rejected unless `discard`; block limit returns keep/trim/
      discard.
- [ ] Wire Today: timer card, quick add, today list, and week bars from
      `GetPeriodReport`.
- [ ] Use settings for default duration, long-timer threshold, timezone, and week
      start.
- [ ] Tests: timer transitions, block limit, entry validation, gRPC-Web.

**Acceptance:** a full day can be logged and corrected without touching BoltDB.

---

## M3 — Organise

- [ ] Add `milestones.proto` and `notes.proto`; implement `MilestoneService` and
      `NoteService`.
- [ ] Wire Log: filters (today, this week, last 7 days, this month, since last
      manager check-in, custom), category and subcategory filters, inline edit,
      and the overlap marker.
- [ ] Wire Initiatives: role-filtered portfolio; project detail with Timeline,
      Notes, Milestones, and Report (from `GetPeriodReport`).
- [ ] Tests: filters, inline edit, overlap flag, milestone and note CRUD.

**Acceptance:** a quarter of historical data can be entered and corrected.

---

## M4 — Support

- [ ] Wire Support: quick form (person, team, mode subcategory, duration,
      outcome), feed, and rollups by person and mode.
- [ ] Enforce person-required validation in the service.
- [ ] Tests: support rollups, missing person rejected, cross-role reporting.

**Acceptance:** support appears correctly in aggregates and the check-in report.

---

## M5 — Check-ins and exports

- [ ] Add `check_ins.proto`; implement `CheckInService` (create, update,
      finalize, list, get, delete personal).
- [ ] Extend `summaries.proto` with `BuildExport`, `DownloadExport`, and
      `BuildPrompt`.
- [ ] Manager check-in boundary: last final manager check-in; audience `1:1` or
      `performance review`.
- [ ] Personal review: timeframe presets, live view from `GetPeriodReport`, saved
      on demand, editable indefinitely, weekly/monthly prompt setting.
- [ ] Export bundle: `summary.md`, `data.json`, `entries.csv`, `support.csv`.
- [ ] Wire the Check-ins list and detail; mark final (manager only).
- [ ] Tests: boundary logic, kind filtering, save/discard, export contents.

**Acceptance:** a pasted prompt produces a usable review draft; a personal review
can be saved or discarded.

---

## M6 — Built-in AI

- [ ] Add streaming `GenerateSummary` and prompt variants (manager 1:1, manager
      performance review, personal review).
- [ ] OpenAI-compatible provider; environment-only key; URL and note redaction.
- [ ] Stream into the editable summary; failures leave the existing summary
      untouched.
- [ ] Wire Settings → AI and the check-in summary actions.
- [ ] Tests with a fake provider: prompt selection, redaction, failure path.

**Acceptance:** generation persists model and prompt version; failures are
non-destructive.

---

## M7 — Durability

- [ ] Extend `settings.proto` with `BackupNow`, `GetBackupStatus`,
      `ListBackups`, and `RestoreBackup`.
- [ ] Implement snapshots (`tx.WriteTo`, fsync, atomic rename), verification,
      retention (scheduled only), restore with a pre-restore copy, and index
      rebuild.
- [ ] Add CLI `wdid backup` and `wdid restore`.
- [ ] Wire Settings → Data & backups and the overdue warning.
- [ ] Tests: snapshot verification, retention, restore round-trip.

**Acceptance:** restore from a backup in a test instance; the overdue warning
works.

---

## M8 — Polish

- [ ] Themes (System/Light/Dark/High Contrast), density, tabular figures.
- [ ] Keyboard shortcuts and visible focus rings.
- [ ] Empty, loading, and error states everywhere; accessibility pass (AA).
- [ ] Delete `DemoWdidRepository`; every screen uses generated clients.
- [ ] Browser gRPC-Web smoke test against the running service.

**Acceptance:** keyboard-only manager check-in flow; AA contrast verified.

---

## Cross-cutting rules

- Contracts are additive with stable field numbers, enum zero values, UTC
  timestamps, `YYYY-MM-DD` local dates, and `google.protobuf.Duration`.
- Errors use Connect codes with `google.rpc.BadRequest` field violations.
- Identity comes from the token, never a request field; data lives in per-user
  buckets.
- No parallel REST for any RPC; no hand-written JSON DTOs in Flutter.
- Update `plan.md` before changing a decision; record hard-to-reverse decisions
  in `docs/adr/`.

## Known non-blocking notes

- goslow logs `code":"unknown"` for successful RPCs.
- `ReadObject` panics on a missing bucket; the store wrapper must use
  `ReadAllObjects`.
- goslow opens BoltDB with `os.ModeExclusive`; pre-create the database file with
  `0600`.
- `cmd/wdid/dist` contains only `.gitkeep` until `make buildweb`.
- Remaining goslow follow-ups are listed in `GOSLOW-UPDATES.md`.

## Deferred

See `plan.md` §14.2. Do not pull these into v1: admin UI, offsite backup push,
backup encryption, webhooks, WebAuthn, review-readiness score, cross-attribution
links, arbitrary nesting, shared categories, notifications, mobile/PWA, and
calendar or issue-tracker imports.

## Ticket creation

Run the `to-tickets` skill against this plan. Create one ticket per checklist
item that can be reviewed independently, and link every ticket to its milestone
and acceptance criterion.
