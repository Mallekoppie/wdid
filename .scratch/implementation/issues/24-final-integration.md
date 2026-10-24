# 24: Final integration

**What to build:** The demo adapter is gone. Every screen reads and writes through generated Connect clients over gRPC-Web, the embedded app is served on the same origin as the RPCs, and the full loop works in a browser: capture a day, review a week, create and finalize a manager check-in, export, and restore a backup.

**Blocked by:** 23 (UI polish)

**Status:** ready-for-human

- [x] `DemoWdidRepository` is deleted and every screen uses generated clients.
- [x] A real browser gRPC-Web request reaches the service.
- [x] The embedded app and the RPC surface are served on the same origin.
- [x] No REST or hand-written JSON path remains for a capability that has an RPC.
- [x] The full loop works: capture, personal review, manager check-in, export, backup/restore.
- [x] `make check` passes and the browser smoke test is recorded.

## Comments

### 1. `DemoWdidRepository` is deleted and every screen uses generated clients

- Deleted `web/lib/data/demo_repository.dart` and the now-dead `WdidRepository`
  seam in `web/lib/data/repository.dart`. Also removed the demo-only model and
  UI surface: `models/work_item.dart`, `models/initiative.dart` (its `LinkRef`
  moved to `models/link_ref.dart`), `utils/attribution.dart`,
  `widgets/entry_row.dart`, `widgets/quick_add_bar.dart`,
  `widgets/forms/entry_dialog.dart`, `widgets/forms/initiative_dialog.dart`, and
  `screens/initiative_detail_screen.dart`.
- `AppState` no longer takes a repository. It takes the generated clients only
  (`categoryApi`, `settingsApi`, `entryApi`, `timerApi`, `summaryApi`, `noteApi`,
  `milestoneApi`, `checkInApi`); every former repository fallback now calls the
  corresponding client or raises `ServicePendingException` instead of inventing
  local data. `main.dart` wires all nine generated `Grpc*` clients.
- Demo branches are gone from Today, Log, Support, Initiatives, the router, the
  header/shell, the login screen and Settings. The shell's "New entry" action
  now uses the new service-backed `EntryForm`/`showServiceEntryDialog`
  (`web/lib/widgets/forms/entry_form.dart`) instead of the old repository form.
- `app_state.dart` lost `isDemo`, the local timer/work-item/initiative/note/
  check-in fallbacks, demo backups and the demo badge; Settings → About now says
  "Connect service" unconditionally.
- Tests were migrated to the in-memory fakes that implement the API interfaces;
  demo-only tests were rewritten or removed. `grep -rn
  "DemoWdidRepository|WdidRepository|demo_repository" web` returns nothing.

### 2. A real browser gRPC-Web request reaches the service

- Browser run: Playwright Chromium loaded `http://127.0.0.1:19101/`, enabled
  Flutter's semantics tree, bootstrapped the first admin, and drove the app.
  Recorded from `page.on('response')`: **43 gRPC-Web responses, all 43 successful,
  across 8 services** — `AuthService`, `CategoryService`, `CheckInService`,
  `EntryService`, `NoteService`, `SettingsService`, `SummaryService`,
  `TimerService`.
- HTTP-level cross-check against the same server:
  `POST /wdid.v1.AuthService/GetAuthConfig` with
  `Content-Type: application/grpc-web+proto` and `X-Grpc-Web: 1` returned
  `HTTP/1.1 200`, `Content-Type: application/grpc-web+proto`, `grpc-status: 0`.

### 3. The embedded app and the RPC surface are served on the same origin

- `cmd/wdid/main.go` still starts one listener
  (`platform.StartApplicationServerWithContext`) carrying the nine Connect
  services, `nonRPCRoutes()`, and the embedded `dist` SPA on the single
  `WDID_HTTP_ADDR`.
- Observed on that one origin:
  `GET /` → `200 text/html; charset=utf-8` (embedded Flutter app) and
  `GET /healthz` → `200 application/json`, while the browser's generated clients
  sent their gRPC-Web calls to the same `127.0.0.1:19101` origin
  (`lib/data/grpc_channel.dart` defaults to `Uri.base`).
- `flutter build web` output is copied into `cmd/wdid/dist` (rebuilt with
  `make buildweb`), so the binary serves the current client rather than a stale
  bundle.

### 4. No REST or hand-written JSON path remains for a capability that has an RPC

- The only non-RPC route in `cmd/wdid/main.go` is `/healthz`.
- `grep -rn "/api/|jsonDecode|application/json" web/lib` has no hits outside the
  generated protobuf sources; the only URL parsing is the gRPC channel base.
- Every capability is a proto service: auth, categories/subcategories, entries,
  timer, settings/backups, summaries/exports/prompts, notes, milestones and
  check-ins. There is no `WdidRepository`, `HttpClient` or manual JSON adapter
  left in `web/lib`.

### 5. The full loop works in a browser

The new repeatable test is `scripts/browser-smoke.cjs` (`make smoke-web`). It
drives the served app through the startup auth gate and all five flows. Recorded
run (fresh DB) against `http://127.0.0.1:19101`:

```
[smoke] auth gate: bootstrap first admin account
[smoke] capture: quick-capture one work entry
[smoke] capture: entry visible in Log
[smoke] personal review: open the live review and save it
[smoke] personal review: saved
[smoke] manager check-in: create, finalize
[smoke] manager check-in: finalized
[smoke] export: build the export bundle and copy the prompt
[smoke] export: copied 1400 prompt characters
[smoke] backup: take a snapshot and restore it
[smoke] backup: manual snapshot listed
[smoke] backup: restored
[smoke] gRPC-Web: 43 responses, 43 successful across 8 services
[smoke] services: AuthService, CategoryService, CheckInService, EntryService, NoteService, SettingsService, SummaryService, TimerService
[smoke] PASS
```

Server-side procedure counts for that run: `AuthService/RegisterAccount` 1,
`EntryService/CreateEntry` 1, `CheckInService/CreateCheckIn` 2 (live personal
review save + manager check-in), `CheckInService/FinalizeCheckIn` 1,
`SummaryService/BuildExport` 1, `SummaryService/BuildPrompt` 1,
`SettingsService/BackupNow` 1, `SettingsService/RestoreBackup` 1. The copied
prompt contained the service-owned instruction ("Use only the data supplied…"),
and the manual snapshot (`wdid-…-manual.db`) was listed before restore and the
"Restored …" confirmation toast was observed. Screenshots
(`01-today` … `06-restored`) were written to `/tmp/wdid-smoke/shots`.

Sign-in path used: fresh database → **bootstrap admin** through
`AuthService/RegisterAccount` (display name, email, password, deployment
bootstrap secret). The same script signs in through `AuthService/Login` when the
account already exists, so it is repeatable against a persistent dev database.

Commands used:

```bash
make buildweb
GOTOOLCHAIN=auto go build -trimpath -o /tmp/wdid-smoke/wdid ./cmd/wdid
WDID_HTTP_ADDR=127.0.0.1:19101 WDID_DB_PATH=/tmp/wdid-smoke/wdid.db \
WDID_BOOTSTRAP_SECRET=smoke-bootstrap-secret \
WDID_JWT_SECRET=smoke-jwt-secret-change-me-32chars WDID_DEV_MODE=true \
/tmp/wdid-smoke/wdid &

npx playwright install chromium          # browser binaries
# container also needed: libgbm1 libnss3 libasound2t64 etc.
NODE_PATH=/tmp/wdid-smoke/pw/node_modules WDID_BASE_URL=http://127.0.0.1:19101 \
WDID_SMOKE_SHOTS=1 node scripts/browser-smoke.cjs
```

### 6. `make check` and the recorded smoke test

- `make check` from `/workspaces/wdid` exits **0**: `go vet ./...`, proto
  regeneration diff check, all Go packages, `flutter analyze` ("No issues
  found!") and **251 Flutter tests pass**.
- `scripts/browser-smoke.cjs` is committed as the repeatable smoke test;
  `make smoke-web` runs it. It requires Node plus Playwright (documented in
  `web/README.md`), so it is intentionally not part of `make check`.
- `web/README.md` and the demo-related lines in `TODO.md` were updated to
  describe the generated-client-only client.
