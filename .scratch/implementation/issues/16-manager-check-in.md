# 16: Manager check-in create and finalize

**What to build:** A user can create a manager check-in that covers everything since the last final manager check-in. The detail view shows time by category and project, support, and progress. Marking it final makes it read-only and moves the boundary for the next manager check-in. The list can be filtered by kind, and an audience of 1:1 or performance review can be chosen.

**Blocked by:** 03 (Category taxonomy data core), 04 (Category management end-to-end), 09 (Period report)

**Status:** ready-for-human

- [x] The period is prefilled from the last final manager check-in, or the journal start date, to today, and is editable.
- [x] Focus notes can be added when creating the check-in.
- [x] The check-in list shows manager and personal check-ins and can filter by kind.
- [x] The detail shows totals by category, by project, support by person, and weekly rhythm.
- [x] Marking final makes the check-in read-only and moves the next boundary.
- [x] A manager check-in can choose the 1:1 or performance-review audience.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover creation, boundary calculation, finalization, and audience.

## Comments

The feature was already implemented in the working tree; this pass verified every
checkbox against the code and tests, then fixed three defects that kept the
Flutter suite from passing.

Verification (evidence per checkbox):

- Period prefill and edit: `GetCheckInDefaults` in
  `internal/rpc/checkin_service.go` starts at the day after the last final
  manager check-in, else the settings journal start date, else today, in the
  user's timezone, and clamps a future boundary to today. The dialog
  (`web/lib/widgets/forms/checkin_dialog.dart`) renders both dates as editable
  date pickers and refuses a reversed period. Covered by
  `TestCheckInServiceDefaultsStartAtTheJournalStartAndUseTheUsersDay` and the
  "create dialog prefills the server boundary" widget test.
- Focus notes: `CreateCheckInRequest.focus_notes` on the wire, trimmed by
  `domain.CheckIn.Normalize`, entered in the dialog's focus-notes field.
  Covered by `TestCheckInServiceSnapshotsTheAuthoritativeReport` and the same
  widget test.
- List and kind filter: an unspecified kind lists both kinds; `store.CheckIns`
  narrows by kind. `web/lib/screens/checkins_screen.dart` renders both kinds and
  an All/Manager/Personal `ChoiceChip` filter backed by
  `AppState.setCheckInKindFilter`. Covered by
  `TestCheckInServiceFiltersByKindAndProtectsPersonalReviews` and the "lists
  manager and personal check-ins and filters by kind" widget test.
- Detail aggregates: `_ReportAggregates` in
  `web/lib/screens/checkin_detail_screen.dart` renders time by category, time by
  project, support by person, and weekly rhythm, all from the authoritative
  `PeriodReport`. Covered by "detail renders every aggregate from the period
  report".
- Final read-only and boundary: `FinalizeCheckIn` only accepts manager
  check-ins; `store.SaveCheckIn`/`DeleteCheckIn` reject a final manager
  check-in with `ErrFinalCheckInReadOnly`; the UI hides finalize and edit and
  shows the read-only banner. The next `GetCheckInDefaults` starts the day
  after the finalized period. Covered over both protocols by
  `TestCheckInServiceCreationFinalizationAndBoundary`, by
  `TestFinalManagerCheckInIsReadOnly`, and by the "marking final makes the
  check-in read-only" widget test.
- Audience: `CheckInAudience` one-on-one (default) or performance review in the
  proto and domain; the dialog exposes both for manager check-ins and clears it
  for personal reviews; create/update map it both ways. An audience on a
  personal review is a field violation. Covered by the lifecycle test (both
  protocols), `TestCheckInServiceFiltersByKindAndProtectsPersonalReviews`, and
  the Dart API tests.
- Loading, empty, error and validation states: the list has a loading panel,
  a per-filter empty state, an inline refresh error with retry and a full error
  with retry; the detail has loading, not-found, error-with-retry; the create
  dialog has loading, boundary-load error with retry, create failure, and local
  date validation. Validation surfaces rejected fields through
  `grpc_errors.dart`. Covered by the widget tests and the API failure-mapping
  tests.
- Connect and gRPC-Web: `TestCheckInServiceCreationFinalizationAndBoundary`
  runs creation, boundary movement and finalization under both the unary
  Connect and gRPC-Web protocols; audience is asserted in both. The Dart client
  is tested through `web/test/checkin_api_test.dart`.

Changes made in this pass:

- `web/lib/widgets/forms/checkin_dialog.dart`: the dialog's action row put an
  unconstrained helper text beside the buttons and overflowed by 305 px,
  pushing "Create check-in" off-screen (three widget tests failed). Wrapped the
  text in `Expanded` with ellipsis.
- `web/lib/screens/checkin_detail_screen.dart`: a failed detail read was hidden
  by the cached listing row, so the retry state never appeared. `detailFailed`
  now surfaces the error when the detail request for this id failed.
- `web/test/checkin_api_test.dart`: the pagination fake returned
  `next_page_token` forever, so the client's paging loop never terminated; the
  suite hung and grew past 20 GB. The fake now returns the token only for the
  first page, like a real service.

`make check` passes with exit code 0: proto-check, `go vet`, `flutter analyze`,
all Go tests, and all Flutter tests (184 passed). Nothing was committed; all
changes remain in the working tree.
