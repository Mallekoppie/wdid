# 25: Code-review fixes

**What to build:** Resolve every confirmed finding from the 2026-10-24 code-review pass. The findings were produced by two independent sweeps against `9f673cf` and verified against the source before this ticket was written.

**Blocked by:** None (code review ran on the completed implementation).

**Status:** ready-for-human

## Production correctness

- [x] **1. Deleting taxonomy used by the active timer.** `internal/store/taxonomy.go:257-274`: `entryReferencesCategoryTx` and `subcategoryReferencedTx` ignore the timer bucket. Include `timer` in both checks so deleting a category or subcategory an active timer points at returns `ErrCategoryInUse` / `ErrSubcategoryInUse`. Test: start a timer, attempt delete of its category and subcategory, both rejected; delete succeeds after stop/discard.
- [x] **2. Settings can overwrite stored preferences with defaults.** `web/lib/screens/settings_screen.dart:57-80`: controllers seed once in `didChangeDependencies`, so opening Settings before preferences load (or after a transient failure) makes Save Time/AI write defaults over stored values. Re-sync the editors when the loaded settings change while the user has not edited them, and do not allow a save that would replace settings that never loaded. Widget test: open Settings while `GetSettings` is delayed, deliver the real settings, save, and assert the stored values (not defaults) are sent.
- [x] **3. Mark final discards an open summary draft.** `web/lib/screens/checkin_detail_screen.dart:416` and `_finalize` at :230: the button is enabled while `_editing`, and finalize never saves. Disable/hide Mark final while editing (or save the draft first with confirmation); after finalizing, the editor must not be stranded in read-only mode. Widget test: open the editor, type, and assert Mark final cannot finalize over the draft.
- [x] **4. Log reload silently drops an inline edit.** `web/lib/screens/log_screen.dart:512`, `web/lib/state/app_state.dart:1084`: `loadLog` sets `logLoading`, which unmounts the rows, while `_editing` survives. Preserve the draft across filter/search/retry/mutation reloads, or make the discard explicit (confirmation). The edited row must never silently revert to server values. Widget test: edit a row, trigger a filter/search reload, assert the draft is still present (or that the user was asked before it was discarded).
- [x] **5. Stopping a timer leaves Log and Support stale.** `web/lib/state/app_state.dart:981`: `stopTimer` updates `entries` and reports but not `logEntries`, `supportEntries` or `supportReport`. After a successful stop, refresh the active Log query and the loaded Support listing/rollups. State test: with a log query and support range loaded, stop a timer and assert both refresh and contain the new entry.
- [x] **6. Project report shows all-time support as "this quarter" on failure.** `web/lib/screens/project_detail_screen.dart:378`: when `report == null`, `_entryFallsIn` is bypassed and every person-tagged entry is listed under the quarter subtitle. Gate the interaction list on a non-null report (show the error without a misleading list), or label the fallback period honestly. Widget test: report failure shows no all-time interactions under "This quarter".
- [x] **7. Archived categories are selectable for new entries.** `web/lib/widgets/forms/entry_form.dart:73-78, 203-212`: the category dropdown iterates every category and preselects `lastCategoryId` even when archived. Offer only selectable (non-archived) categories and subcategories, and preselect only when the remembered pair is still selectable. Widget test: archived category is absent from the dropdown and never preselected.

## Privacy and consistency

- [x] **8. Redaction misses non-HTTP URLs.** `internal/domain/redaction.go:14`: only `https?://` is replaced. Match any URL scheme (`[a-z][a-z0-9+.-]*://…`) plus `mailto:`, so `ftp://user:pass@host`, `file://`, `ssh://` and `mailto:` are redacted. Tests for each scheme, and confirm the export bundle itself is unchanged.
- [x] **9. Export is not one consistent snapshot.** `internal/rpc/summary_service.go:357`: report, entries, taxonomy, milestones, check-ins and settings are read in separate transactions. Add a store method that gathers the whole export input inside one `View` transaction and use it from `exportInput`. Test: the export reads one consistent snapshot (including a concurrency-shaped test where feasible) and existing export contents are unchanged.
- [x] **10. Paged entry loading can duplicate or omit rows.** `web/lib/data/entry_api.dart:182`: concatenate pages by id, de-duplicating entries (first occurrence wins) and merging overlapping ids. Test: a fake RPC returns an overlapping page and the listing has no duplicate and no double-counted minutes.

## Smoke tooling and test hygiene

- [x] **11. Bootstrap detection races the config spinner.** `scripts/browser-smoke.cjs:105`: wait for either the bootstrap input or the Sign in button before branching, rather than a non-waiting `count()` after fixed delays.
- [x] **12. `make run` + `make smoke-web` cannot bootstrap a fresh DB.** `Makefile:100`: forward the smoke credentials, at minimum defaulting `WDID_SMOKE_BOOTSTRAP_SECRET` to `$(WDID_BOOTSTRAP_SECRET)` and exporting it for the target, so the documented pair works.
- [x] **13. Capture hard-codes the "Initiatives" category.** `scripts/browser-smoke.cjs:146-158`: choose the first available category menuitem and remember its name for the confirmation assertion; fail loudly if no category can be selected.
- [x] **14. Timer-state test disposes inline.** `web/test/ui_polish_test.dart:446`: register `addTearDown(state.dispose)` when the state is created so a failing expectation cannot leave a pending ticker that masks the real failure.
- [x] **15. Restore tabular-figures coverage.** The `fontFeatures` assertion was deleted with the old entry row. Add a test that asserts times/durations in the current entry rows use `FontFeature.tabularFigures` (or assert the shared themes/tokens do, if driving the widget is impractical).

## Gate

- [x] `make check` passes (proto-check, `go vet`, Go tests, `flutter analyze`, Flutter tests).
- [x] Record the per-finding outcome, commands, and any remaining decision in `## Comments`; set the status to `ready-for-human`.

## Comments

Implemented all 15 findings against `9f673cf`. Product/UX decisions:

- **Finding 2 (preserve, do not discard):** each settings section tracks whether the user has edited it. A preferences load re-syncs only untouched editors; Save Time/AI is disabled while preferences are loading or failed, and the save handlers also refuse so a stale defaults view can never overwrite stored values.
- **Finding 3 (disable, do not auto-save):** Mark final is disabled while the summary editor is open, `_finalize` defensively returns, and a successful finalize clears `_editing` so no editor is stranded read-only.
- **Finding 4 (preserve the draft):** rows stay mounted while a reload is in flight when an editor is open, the edited row is kept visible even when the new filter result excludes it, and rows are keyed by entry id so the `EntryForm` state (the draft) survives reordering. No confirmation prompt; nothing is silently discarded.
- **Finding 6:** with no report the interaction list is empty and the subtitle reads "Report unavailable" instead of mislabelling all-time entries as this quarter.
- **Finding 7:** selectors offer only non-archived rows; a remembered pair is preselected only when still selectable. An entry already filed under an archived category/subcategory still shows that attribution as a disabled "(archived)" item while editing.

Per-finding evidence:

1. `internal/store/taxonomy.go` now scans `timerBucket` in both reference checks. Regression: `TestActiveTimerProtectsItsCategoryAndSubcategory` (`internal/store/taxonomy_test.go`) starts a timer, gets `ErrSubcategoryInUse` and `ErrCategoryInUse`, discards, then deletes both.
2. `web/lib/screens/settings_screen.dart` re-syncs untouched editors and blocks saves until a successful load. Regression: `settings_ai_test.dart` — "a delayed preferences load is not overwritten by editors" gates `GetSettings`, completes it, saves Time and AI, and asserts the stored timezone/targets/durations/base URL/model/redaction were sent.
3. `checkin_detail_screen.dart` disables the finalize buttons while `_editing`. Regression: "mark final cannot discard an open summary draft" asserts the button's `onPressed` is null, no confirmation/finalize request occurs, and the typed draft remains.
4. `log_screen.dart` keeps rows mounted during a reload while editing, supplies `ValueKey(entry.id)`, and re-includes the editing row when filtered out. Regression: "keeps an inline draft across a reload" edits a row, gates a search reload, and asserts the draft text survives a server-side description change and a non-matching filter.
5. `AppState.stopTimer` now calls `refreshLog()` and `_refreshSupportIfLoaded()` for saved blocks. Regression: "stopping a timer refreshes the loaded Log and Support views" loads a Log query and Support range, stops a support timer, and asserts both listings and the Support report were refreshed (`FakeTimerApi.savedEntries` feeds the fake EntryService).
6. `project_detail_screen.dart` gates the interaction list on a non-null report. Regression: "a failed report hides the interactions it cannot date" asserts the error, "Report unavailable", and no `Priya`/all-time interaction rows.
7. `entry_form.dart` uses `selectableCategories` / `selectableSubcategoriesFor` and validates the remembered pair. Regression: "archived categories are not offered or preselected" remembers an archived pair, opens the form, and asserts the first selectable category is selected, no subcategory is selected, and the archived names are absent from the menu.
8. `internal/domain/redaction.go` matches any `scheme://` plus `mailto:`. Regression: `TestRedactExportInputStripsEveryURLScheme` covers https/ftp/file/ssh/mailto and asserts a bundle built from the same input is unchanged (redaction is copy-on-write).
9. Added `store.ExportSnapshot` (`internal/store/export.go`), which reads report, entries, taxonomy, milestones, check-ins and settings in one `View`; `summary_service.exportInput` uses it, and a scoped check-in's period is resolved inside the same transaction. Sorting was factored into helpers shared with the listing methods so contents and order are unchanged. Tests: `TestExportSnapshotMatchesTheListingReads`, `TestExportSnapshotScopesToTheCheckIn`, `TestExportSnapshotIsConsistentUnderConcurrentWrites` (40 concurrent writes, 200 reads asserting report count/minutes always equal the returned rows), plus the existing export-bundle RPC tests.
10. `GrpcEntryApi.listEntries` de-duplicates by id with first occurrence winning while merging `overlappingEntryIds`. Regression: "listEntries merges overlapping pages without duplicating rows" returns an overlapping page and asserts two ids, 75 minutes, and the merged overlap set.
11. `waitForAuthGate` enables semantics once and then polls until either the bootstrap input or the Sign in button exists, failing loudly after 15s.
12. `Makefile` exports `WDID_SMOKE_EMAIL`, `WDID_SMOKE_PASSWORD` and `WDID_SMOKE_BOOTSTRAP_SECRET`, the last defaulting to `$(WDID_BOOTSTRAP_SECRET)`.
13. `captureEntry` selects the first available category menuitem, reads its accessible name for the confirmation regex, waits for the menu to detach, and fails if no category can be selected.
14. The timer-state test registers a guarded `addTearDown(disposeOnce)` before any expectation and also disposes at the end so the pending-timer invariant does not mask a real failure.
15. Regression: "entry rows align times and durations with tabular figures" renders `WorkEntryRow` and asserts both the time range and duration styles carry the `tnum` feature.

Gate results (2026-10-24):

- `make check` → exit 0. `go vet ./...` clean; `proto-check` clean; `go test ./...` all packages ok; `flutter analyze` → "No issues found!"; `flutter test` → 259 tests passed.
- `node --check scripts/browser-smoke.cjs` → ok.
- Browser smoke on a fresh temp DB (`/tmp/wdid-smoke-db/wdid.db`, service on `127.0.0.1:9101` via `make run` with Makefile defaults, no smoke env supplied): `NODE_PATH=/tmp/wdid-smoke-node/node_modules make smoke-web` → PASS through the bootstrap path, capture, personal review, manager finalize, export/copy prompt and backup/restore; 43/43 gRPC-Web responses across 8 services. A repeat run on the existing account also passed the sign-in path. Finding 12 is proven by the bootstrap succeeding without an explicit `WDID_SMOKE_BOOTSTRAP_SECRET`. Playwright was installed under `/tmp` for the run only; nothing was added to the repository.
