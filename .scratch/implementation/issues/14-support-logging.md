# 14: Support logging

**What to build:** A user can log support work from the Support screen: who was helped, an optional team, the mode, the duration, what happened, and the outcome. A support entry cannot be saved without a person. Support rows are visually distinct from initiative work.

**Blocked by:** 04 (Category management end-to-end), 06 (Quick capture and today's list)

**Status:** ready-for-human

- [x] The support form captures person, optional team, mode, duration, description, outcome, and links.
- [x] Saving without a person is rejected with a field error.
- [x] Support modes come from the subcategories of the support-role category.
- [x] The support feed lists entries newest first and marks support rows distinctly.
- [x] Support work is not cross-attributed to a project.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover create, list, and the person-required rule.

## Comments

Built on the existing data core rather than adding a support service: work entries
already carry `person`, `team`, `subcategory_id`, `description`, `outcome` and
`links`, and `domain.ValidateWorkEntry` already rejects a support-role entry
without a person. No proto or generated-contract change was needed; Support is
an `EntryService` view over the support-role categories.

Server:
- `internal/rpc/support_service_test.go` runs the same flow over Connect and
  gRPC-Web: create a support-role category with `Unblock`/`Review` modes, create
  entries with person, team, mode, duration, description, outcome and links,
  list them newest first, list by person, reject a missing person with the
  `person` field, reject a project subcategory under a support category with the
  `subcategoryId` field, and confirm the initiative listing stays empty.

Flutter:
- `AppState` gains `supportCategories`, `supportModes`,
  `selectableSupportModes`, `isSupportCategory`, `supportModeLabel`, and a
  stale-reply-guarded `loadSupport`/`refreshSupport` listing that queries each
  support-role category for the selected local-date range and merges the result
  newest first. Support mutations refresh the loaded period automatically.
- `support_screen.dart` now dispatches: service mode renders a feed backed by
  `EntryService`, demo mode keeps the old adapter. The service view adds
  loading, empty, error/Retry and validation states, rollups by person and by
  mode, and a taxonomy-driven `Log support` / edit / delete flow. The
  by-person/by-mode panels are presentation rollups over the loaded entries;
  issue 15 will move their source to the authoritative period report.
- `widgets/support_entry_row.dart` renders support rows distinctly: a tertiary
  tint, volunteer icon, left accent bar and a `Support · person · mode`
  attribution, with expandable outcome and links.
- `widgets/forms/support_dialog.dart` adds `showServiceSupportDialog`: the mode
  dropdown lists only non-archived subcategories of support-role categories,
  the person and description are required, minutes and links are validated,
  service field errors map back onto the person field, and there is no project
  or initiative attribution anywhere in the form. The demo dialog's optional
  "Related initiative" selector was removed so support is never cross-attributed
  there either. The global header and app shell support shortcuts dispatch to
  the service dialog when `EntryService` is wired.
- Tests: `web/test/support_screen_test.dart` covers newest-first feed and
  distinct rows, taxonomy-only modes, person and description validation, service
  field errors, loading/empty/error/Retry, create with all fields, edit and
  delete. `web/test/fake_entry_api.dart` gained the date-range filter the
  service applies.

`make check` (proto-check, `go vet`, `flutter analyze`, all Go tests, Flutter
tests) passes with exit code 0; 165 Flutter tests pass. Nothing was committed;
all changes remain in the working tree.

