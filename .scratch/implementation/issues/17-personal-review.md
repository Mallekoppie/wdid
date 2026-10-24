# 17: Personal review

**What to build:** A user can review their own work for the last week, last month, this week, this month, since the last manager check-in, or a custom range. The review opens live; saving it creates a personal check-in that stays editable and can be deleted. Personal reviews never move the manager boundary. The configured cadence offers a non-blocking review prompt and never creates drafts automatically.

**Blocked by:** 05 (Settings preferences end-to-end), 16 (Manager check-in create and finalize)

**Status:** ready-for-human

- [x] The timeframe picker offers last 7 days, last 30 days, this week, this month, since last manager check-in, and a custom range.
- [x] The review opens live with the same aggregates as a check-in.
- [x] Saving creates a personal review; leaving without saving discards it.
- [x] A saved personal review remains editable and can be deleted.
- [x] Personal reviews never change the manager boundary.
- [x] The weekly or monthly cadence produces a non-blocking prompt; no draft is created automatically.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover save, discard, edit, delete, and boundary independence.

## Comments

Implemented the personal-review flow end to end on top of issue 16's check-in slice.

**Service and contracts**
- `internal/contracts/check_ins.proto`: added `DeleteCheckIn` and regenerated Go/Connect/Dart stubs with `make proto`. Deleting uses the existing store rule: a personal review or draft can be removed; a final manager check-in returns `failed_precondition`.
- `internal/rpc/checkin_service.go`: added `DeleteCheckIn`; a summary edit now moves a personal review from `draft` to `edited` (it still can never become `final`). No boundary code changed: `LastFinalManagerCheckIn` already ignores personal reviews.
- Tests in `internal/rpc/checkin_service_test.go`: `TestCheckInServicePersonalReviewLifecycle` runs over both Connect and gRPC-Web and covers defaults-without-a-draft (discard), save, edit, delete, and boundary independence before/after every mutation, plus rejection of deleting a final manager check-in. `TestCheckInServiceRequiresAuthentication` now also covers delete.

**Client and state**
- `web/lib/data/checkin_api.dart` (+ generated stubs): `deleteCheckIn`; `checkin_api_test.dart` covers the request id and refused-delete mapping.
- `web/lib/data/{repository,demo_repository}.dart`, `web/lib/state/app_state.dart`: `deleteCheckIn`, live `loadReviewReport`, `latestPersonalReview`, `reviewPromptDue`/`reviewPromptPeriod`/`reviewPromptPeriodKey` and a session dismissal. Boundary getters still read only final manager check-ins.
- `web/lib/utils/review_timeframe.dart`: the six presets, week-start-aware "this week", clamped "since last manager check-in", custom range, cadence prompt range, and range validation. Unit-tested in `review_timeframe_test.dart`.
- `web/lib/widgets/forms/review_timeframe_dialog.dart`: the picker. It only resolves dates and never calls the write path.
- `web/lib/screens/review_screen.dart`: the live, unsaved review (`/checkins/review?start=…&end=…&timeframe=…`). It reads the authoritative period report, renders the shared aggregates, edits focus notes and the Markdown summary, and only `Save review` calls `CreateCheckIn` (+ `UpdateCheckIn` for a summary). Back, "Discard" and "Leave without saving" create nothing.
- `web/lib/widgets/checkin_aggregates.dart`: the four aggregate panels extracted from the check-in detail, now shared by the saved detail and the live review so their numbers cannot drift.
- `web/lib/screens/checkin_detail_screen.dart`: personal reviews get `Edit review` (period + focus notes) and `Delete review` (confirmation), while the summary editor remains available. Final manager check-ins remain read-only.
- `web/lib/screens/today_screen.dart`: an inline, dismissible "Last week/last month is ready to review" panel. It opens the live review and creates no draft. Dismissal is in-memory for the current cadence period.
- `web/lib/screens/checkins_screen.dart`: `New review` opens the timeframe picker before the live review.

**Tests**
- `web/test/personal_review_flow_test.dart`: picker offers all six presets; live open reads the same report range; save creates a personal review with notes and summary; leaving without saving sends no create; edit (focus and summary) and delete; loading, aggregate error/retry, empty period, save failure; weekly and monthly prompts, dismiss, and "Review now" with no automatic draft.
- `web/test/personal_review_state_test.dart`: save/edit/delete never move the boundary; cadence due rules for weekly, monthly and off; saved review satisfies the period.
- `web/test/review_timeframe_test.dart`, `web/test/checkin_api_test.dart`, `web/test/personal_review_flow_test.dart` all pass.

**Gate:** `GOTOOLCHAIN=auto make check` passes from `/workspaces/wdid` (proto-check, Go vet, Flutter analyze, Go tests, Flutter tests; exit 0).
