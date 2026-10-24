# wdid web client

Flutter web client for the wdid work journal.

## Status

This is the first UI slice, built against the canonical product model and design
documents in the repository root:

- `plan.md` (canonical product and domain model)
- `GLOSSARY.md`
- `.github/copilot-instructions.md`

Every screen reads and writes through the generated Connect clients in
`lib/data/`: `AuthService`, `CategoryService`, `EntryService`, `TimerService`,
`SettingsService`, `SummaryService`, `NoteService`, `MilestoneService`, and
`CheckInService`. The service owns validation, aggregation, exports and
summaries; the client never computes authoritative totals. The browser channel
is gRPC-Web on the page origin unless `WDID_API_BASE_URL` points elsewhere.

## Run

```bash
cd web
flutter pub get
flutter run -d chrome --dart-define=WDID_API_BASE_URL=http://127.0.0.1:8080
```

The auth client uses the page origin by default; set `WDID_API_BASE_URL` when the
service is on another origin, as with the Flutter dev server. `make serveweb`
passes it automatically.

Validation:

```bash
cd web
flutter analyze
flutter test
flutter build web
```

## Routes

| Route | Screen |
| --- | --- |
| `/today` | Timer, quick capture, today's feed, week allocation, day note |
| `/log` | Period filters, search, grouped entries, inline edit, export |
| `/initiatives` | Portfolio cards and archived initiatives |
| `/initiatives/:id` | Timeline, notes, milestones, evidence report |
| `/support` | Support rollups by mode and person, support feed |
| `/checkins` | Check-in list and create flow |
| `/checkins/:id` | Period report, summary generation/editing, export, finalize |
| `/settings` | Data/backups, time, AI, appearance, about |
| `/login` | Bootstrap admin, sign-in, and invite-code registration |

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `T` | Start or stop the timer |
| `N` | New entry |
| `S` | Log support |
| `/` | Go to Log and focus search |
| `G` then `T/L/I/C/S` | Navigate to Today, Log, Initiatives, Check-ins, Support |
| `?` | Shortcut reference |

## Design notes

- Deep Teal (`#00696D`) Material 3 seed, light/dark/system/high-contrast themes.
- Comfortable and compact densities.
- Tabular figures for all times, durations, and percentages.
- Support entries use the tertiary tint and `volunteer_activism` icon.
- Cards are 12 px, inputs 8 px, and the layout stays desktop/tablet-first.
- Loading, empty, error, and validation states are explicit on every screen.

## Service contract status

The Go service transport is Connect, which serves Connect, native gRPC, and
gRPC-Web for the browser. `/healthz` is the only non-RPC route; there is no REST
surface. The Go service embeds this client and serves it from `/`, so the app and
the RPC surface share one origin by default.

`plan.md` is the canonical contract. The generated clients in `lib/data/` cover
the full domain:

- `Category` / `Subcategory` (reporting roles, project fields, archiving)
- `Work entry` (`categoryId`, optional `subcategoryId`, authoritative minutes,
  outcome, support person/team, links, tags)
- `Milestone`
- `CheckIn` (`kind`: `manager` or `personal`, period, state, summary, totals)
- `Note`, `AppSettings`, snapshots and restore

Auth uses the generated `AuthService`: first-account bootstrap, local login and
invite-code registration. Protected RPCs carry `authorization: Bearer <token>`
metadata. The browser OIDC redirect flow is still pending and is explained in
the UI.

## Browser smoke test

`scripts/browser-smoke.cjs` (also `make smoke-web`) drives the served app in a
real Chromium through sign-in, capture, personal review, manager check-in and
finalize, export/copy prompt, and backup/restore. It enables Flutter's semantics
tree and asserts on the accessibility DOM. Run it against a freshly built
service:

```bash
make buildweb build
WDID_HTTP_ADDR=127.0.0.1:19101 WDID_DB_PATH=/tmp/wdid.db \
WDID_BOOTSTRAP_SECRET=smoke-bootstrap-secret \
WDID_JWT_SECRET=smoke-jwt-secret-change-me-32chars \
./bin/wdid &
npm install --no-save playwright
WDID_BASE_URL=http://127.0.0.1:19101 node scripts/browser-smoke.cjs
```
