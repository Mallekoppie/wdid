# 19: Export bundle and copy prompt

**What to build:** A user can export a period or a check-in as a bundle containing `summary.md`, `data.json`, `entries.csv`, and `support.csv`, and can copy the AI prompt block with the summary. Exports are generated on demand and never written into the database directory.

**Blocked by:** 16 (Manager check-in create and finalize)

**Status:** ready-for-human

- [x] A period or check-in produces `summary.md`, `data.json`, `entries.csv`, and `support.csv`.
- [x] The bundle is scoped to the selected period or check-in.
- [x] `summary.md` follows the fixed headings, ISO dates, and units in the plan.
- [x] `support.csv` contains person and mode columns; `entries.csv` is the flat work-entry sheet.
- [x] Copy prompt yields the prompt block followed by `summary.md`.
- [x] Exports are never written into the database directory.
- [x] Connect and gRPC-Web tests cover bundle contents, period scoping, and prompt text.

## Comments

Implemented the on-demand export bundle and copy-prompt slice on
`SummaryService`, reusing the versioned prompt templates rather than
duplicating their text.

Contract and server:

- `internal/contracts/summaries.proto` adds `ExportFile`,
  `BuildExport`/`BuildExportResponse` and `BuildPrompt`/`BuildPromptResponse`.
  `BuildExportRequest` and `BuildPromptRequest` accept either an inclusive
  `from_date`/`to_date` period or a `check_in_id`; the check-in's stored period
  always wins. Generated Go, Connect and Dart stubs were produced with
  `make proto` (never hand-written).
- `internal/domain/export.go` owns the renderer:
  `BuildExportBundle` returns `wdid-export-<from>_<to>/` with `summary.md`,
  `data.json`, `entries.csv`, `support.csv` in plan order. `BuildExportSummary`
  emits the fixed plan §9.2 headings (`# wdid work report — …`, `## Context`,
  `## Time allocation`, `## Initiative progress`, `## Support and
  collaboration`, `## Weekly rhythm`, `## Notes and context`, `## Source
  data`), ISO `YYYY-MM-DD` dates, and explicit `Nh NNm` durations and integer
  share percentages. `data.json` carries the stable `schemaVersion`,
  `generatedAt`, `period`, `settingsSummary`, `categories`, `subcategories`,
  `entries`, `support`, `checkIns`, `notes`, `totals` fields over `[]`-not-null
  lists. `entries.csv` is the flat work-entry sheet; `support.csv` has explicit
  `person` and `mode` columns and one row per support entry.
- `internal/store/reports.go` adds `WorkEntriesInDateRange`, which reads the
  same day index as `PeriodReport`, so CSV rows and aggregates share one
  boundary.
- `internal/rpc/summary_service.go` adds `BuildExport` and `BuildPrompt`.
  `BuildPrompt` renders the canonical `summary.md` and passes a synthetic
  check-in through the existing `domain.BuildPrompt`/`promptInstructions`
  (`PromptVersion = "v1"`), so the prompt is exactly the versioned instruction
  followed by `summary.md`. A check-in selects the variant from its stored kind
  and audience; a bare period defaults to manager 1:1; request `variant`
  overrides both. Exports are returned in the response and are never written to
  the database directory or any other file.

Flutter client:

- `web/lib/data/summary_api.dart` adds `buildExport` and `buildPrompt` to
  `SummaryApi`/`SummaryRpc` and maps the generated bundle to `ExportBundle`.
- `web/lib/state/app_state.dart` prefers `SummaryService` when connected and
  falls back to the demo adapter, adds `canExport`/`hasSummaryService`, and
  forwards a check-in id when the export belongs to one.
- `web/lib/widgets/forms/export_dialog.dart` and
  `web/lib/screens/checkin_detail_screen.dart` pass the selected check-in's id
  and period, and the check-in Export action is now available with the service
  connected (not only in demo mode).

Tests and gate:

- `internal/rpc/summary_service_test.go` runs every export/prompt assertion
  under both unary Connect and gRPC-Web via `forEachSummaryProtocol`:
  `TestSummaryServiceBuildExportBundle` (file set and order, directory,
  summary.md headings/ISO/units, `entries.csv` rows, `support.csv` person+mode,
  `data.json` keys and totals),
  `TestSummaryServiceBuildExportScopesToTheSelectedPeriodOrCheckIn` (check-in
  period wins over request dates and excludes outside entries; a bare period
  honours its dates), `TestSummaryServiceBuildPromptAppendsSummary` (prompt is
  the versioned instruction followed by `summary.md`, variants follow kind and
  audience and accept an override, unknown variant is rejected), and
  `TestSummaryServiceExportNeverWritesIntoTheDatabaseDirectory` (the database
  directory gains no files).
- `web/test/summary_api_test.dart` covers bundle mapping/request scope and the
  versioned prompt mapping; `web/test/fake_summary_api.dart` implements the new
  client methods.
- `make check` passes with exit code 0: proto-check (regenerated Go/Connect
  stubs are current), `go vet`, `flutter analyze` (no issues), all Go tests and
  all 216 Flutter tests. Nothing was committed or pushed; all changes remain in
  the working tree.
