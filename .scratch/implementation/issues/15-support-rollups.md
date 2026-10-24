# 15: Support rollups

**What to build:** The Support screen shows how much support time went to each person and each mode over a period. The rollups come from the server period report and match the support section of a manager check-in.

**Blocked by:** 09 (Period report), 14 (Support logging)

**Status:** ready-for-human

- [x] Support time is rolled up by person for the selected period.
- [x] Support time is rolled up by mode using subcategories.
- [x] The screen shows the number of people and interactions.
- [x] Rollups come from the period report, not client-side addition.
- [x] An empty period returns an empty rollup, not an error.
- [x] Connect and gRPC-Web tests cover person and mode totals and period boundaries.

## Comments

No contract or report aggregate was missing: `PeriodReport` already carries
`support_people` (person, duration, interactions) and `support_modes`
(subcategory id, name, duration, interactions), so `summaries.proto` and its
generated Go/Dart code are unchanged. Support minutes, people count and
interaction count are read directly from those report allocations; every
support entry requires a person, so the person allocation is the complete
support rollup. Nothing is recomputed from the loaded entries.

State (`web/lib/state/app_state.dart`):
- Added `supportReport`, the authoritative report for the Support screen's
  selected period.
- `loadSupport` now requests the report and the per-category entry listings in
  one `Future.wait`, so both run in parallel and either failure lands in the
  existing `supportError` state. The report is cleared when the load starts and
  stays null on failure, so a stale period's rollup never sits under an error.
- Existing mutation refreshes (`_refreshSupportIfLoaded`) already rerun
  `loadSupport`, so create, edit, split and delete reload both the feed and the
  rollups.

Flutter UI (`web/lib/screens/support_screen.dart`):
- The service view's header is `{duration} · {people} · {interactions}` from
  `supportReport.supportPeople`.
- "By person" lists the report's person allocations with minutes and an
  interaction count per person; "By mode" renders the report's mode allocations
  (subcategory name and minutes) through `AllocationBars`.
- The entry feed is still the `EntryService` listing; the demo adapter path is
  untouched.

Tests:
- `internal/rpc/summary_service_test.go` adds
  `TestSummaryServiceSupportRollupsRespectPeriodBoundaries` over Connect
  (case-insensitive person grouping, two modes, inclusive first/last days,
  excluded neighbouring days, empty period) and
  `TestSummaryServiceSupportRollupsServeGRPCWeb` over gRPC-Web (person and mode
  totals, inclusive period start/end, a day before the period and an empty
  range). The empty-period test now also asserts empty support rollup rows.
- `web/test/support_screen_test.dart` adds a test where the report's people and
  modes deliberately disagree with the loaded entries, proving the UI renders
  the report (and asserts the support report was requested for the selected
  quarter), plus an empty-period test that expects an empty rollup and no
  error. `web/test/fake_summary_api.dart` records every request.

`make check` (proto-check, lint, all Go tests, `flutter analyze`, all Flutter
tests) passes with exit code 0; 167 Flutter tests pass. Nothing was committed;
all changes remain in the working tree.
