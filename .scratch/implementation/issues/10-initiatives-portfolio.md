# 10: Initiatives portfolio

**What to build:** The Initiatives screen shows every subcategory under an initiative-role category as a project card: name, category, status, time invested in the current period, progress, target outcome, last activity, and links. Archived projects are separated and read-only.

**Blocked by:** 04 (Category management end-to-end), 09 (Period report)

**Status:** ready-for-human

- [x] Initiative-role subcategories appear as project cards.
- [x] Each card shows status, time invested this period, progress, target outcome, and last activity.
- [x] Time invested comes from the period report, not from client-side addition.
- [x] Archived projects appear in a separate read-only section and can be restored.
- [x] A project can be created from this screen with a category and role-compatible fields.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover listing, creation, and archiving.

## Comments

- 2026-10-23: Verified the slice against the committed implementation in `8fe9a2a` ("implement initiatives portfolio"); no new implementation was required. Commit `4845a0a` later added card/archived-row navigation to the project detail route but did not change portfolio behaviour.
- Initiative-role subcategories as cards: `web/lib/state/app_state.dart` derives `openProjects`/`archivedProjects` from subcategories whose category role is `initiative`, and `web/lib/screens/initiatives_screen.dart` renders each as a `_ProjectCard`. `web/test/initiatives_portfolio_test.dart` ("shows initiative projects ...") asserts initiative projects appear and the support subcategory "Unblock" does not.
- Card fields: `_ProjectCard` shows `SubcategoryStatusBadge`, report minutes ("this quarter"), manual progress percentage/bar, target outcome (falling back to description), last activity, and links. The same test asserts time, progress, target outcome, and the report's last-activity description.
- Report-sourced time: `AppState.allocationForProject` reads `initiativesReport.subcategories`; `loadInitiativesReport` calls `GetPeriodReport` for the current quarter and the screen never sums entries. The domain report now carries `LastActivityDate`/`LastActivityDescription` (`internal/domain/report.go`, `internal/contracts/summaries.proto`, `internal/gen/wdid/v1/summaries.pb.go`, `internal/rpc/summary_service.go`, `web/lib/data/summary_api.dart`, `web/lib/models/period_report.dart`). Tests: `internal/domain/report_test.go` (`TestBuildPeriodReportReportsLastActivityPerSubcategory`), `internal/rpc/summary_service_test.go` (last-activity assertions), `web/test/summary_api_test.dart` (proto mapping), and `web/test/initiatives_portfolio_test.dart` (report minutes `2h`/`30m`, header excludes support time, report failure yields "No activity this quarter" rather than local computation).
- Archived section and restore: `_ProjectsView` shows a separate "Archived (n)" `ExpansionTile` with read-only `_ArchivedProjectRow` rows and a Restore action; `AppState.archiveSubcategory` calls the category RPC with `archived: false`. Covered by `web/test/initiatives_portfolio_test.dart` ("separates archived projects and restores them", "archives a project from its card", "keeps projects visible under an archived initiative category").
- Creation: `web/lib/widgets/forms/project_dialog.dart` offers the initiative-role category selector plus name, description, target outcome, status (archived excluded), target date, progress, and links; the button is disabled when no selectable initiative category exists. Covered by `web/test/initiatives_portfolio_test.dart` ("creates a project with its category and project fields", "validates a project name before creating it", "explains that projects need an initiative category").
- Loading/empty/error/validation: loading panels for taxonomy and report, "No initiative category"/"No projects yet" empty states, retryable taxonomy and report errors, and required-name validation. Covered by the Flutter tests above plus the loading and both error tests in `web/test/initiatives_portfolio_test.dart`.
- Connect and gRPC-Web coverage: `internal/rpc/domain_service_test.go` exercises subcategory creation with project fields, listing, and archiving over the default Connect client (`TestCategoryServiceManagesSubcategories`) and over `connect.WithGRPCWeb()` (`TestCategoryServiceServesGRPCWeb`). `internal/rpc/project_detail_test.go` runs the same create/list/archive-and-restore flow under both `connect` and `grpc-web` subtests (`TestProjectDetailServesConnect`). `web/test/category_api_test.dart` covers the generated gRPC-Web client's listing and subcategory creation mapping, while the widget tests cover archive/restore through the UI.
- `make check` (go vet, flutter analyze, proto-check, `go test ./...`, `flutter test`) passed with exit code 0; all suites reported ok / "All tests passed!".
