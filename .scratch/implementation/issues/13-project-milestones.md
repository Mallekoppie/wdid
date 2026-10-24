# 13: Project milestones

**What to build:** A user can add milestones to a project with a title, an optional due date, and a done flag, then edit, complete, and delete them. The project report shows milestone completion alongside the time invested.

**Blocked by:** 11 (Project detail: timeline and report)

**Status:** ready-for-human

- [x] A milestone can be created with a title, optional due date, and done flag.
- [x] A milestone can be edited, marked done or not done, and deleted.
- [x] Milestones appear on the project detail and can be added from it.
- [x] The project report shows how many milestones are complete.
- [x] Milestones survive a restart.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover create, update, complete, delete, and report counts.

## Comments

Built on the milestone domain model and store that already shipped with the
taxonomy data core (`domain.Milestone`, `ValidateMilestone`, `SaveMilestone`,
`Milestones`, `DeleteMilestone`). The one domain change was making the due date
optional, as the issue specifies: `ValidateMilestone` now accepts an empty due
date and only validates the format when one is supplied. The existing domain
test case was updated to match.

Contract and service:
- `internal/contracts/milestones.proto` adds `MilestoneService` with
  `ListMilestones`, `CreateMilestone`, `UpdateMilestone` (title, optional due
  date, done; the project is immutable) and `DeleteMilestone`. Generated Go and
  Dart stubs were regenerated with `make proto`.
- `internal/rpc/milestone_service.go` derives the account from the bearer token,
  paginates listings, returns trimmed records, and maps store errors through the
  shared Connect error mapper. Registered in `cmd/wdid/main.go`,
  `internal/config/config.go`, and the RPC test handler.
- Report counts: `summaries.proto` adds `MilestoneProgress` to `PeriodReport`;
  `store.PeriodReport` reads the milestones bucket and `domain.BuildMilestoneProgress`
  produces per-project total/done counts. Completion belongs to the project, so
  counts are returned even when the project has no time inside the period. The
  Flutter report reads these counts rather than recomputing them.

Flutter web:
- `web/lib/models/milestone.dart`, `MilestoneDraft` in `models/drafts.dart`, and
  `web/lib/data/milestone_api.dart` mirror the note client (abstract API,
  generated-RPC seam, gRPC error mapping, draft/model mapping).
- `AppState` gains `milestoneApi`, per-project milestone loading with stale-reply
  guards, create/update/toggle/delete methods, ordering by due date with undated
  last, and `milestoneProgressForProject` from the authoritative report.
  Milestone mutations refresh the report so completion counts stay in sync.
- `project_detail_screen.dart` gains a fourth `Milestones` tab with a done
  checkbox, due date, edit/delete actions, add button, and loading/error/empty/
  validation states; archived projects are read-only. The Report tab shows
  `N of M complete`.
- `widgets/forms/milestone_dialog.dart` handles title validation, an optional
  date picker, the done flag, and service errors. Wired through `app.dart` and
  `main.dart`.

Test evidence:
- Go: `TestMilestoneServiceServesConnectAndGRPCWeb` runs the full create, list,
  update, complete/uncomplete, delete and report-count flow over both Connect and
  gRPC-Web; plus validation, account isolation, restart persistence, and store/
  domain report-count tests.
- Flutter: `test/milestone_api_test.dart` covers contract mapping, pagination,
  optional due date/done, update/delete, validation and unavailable errors;
  `test/project_detail_test.dart` covers list/create, complete/uncomplete, edit,
  delete, empty, loading, error/retry, validation, report counts, and archived
  read-only; `test/fake_milestone_api.dart` is the in-memory test double.
- `make check` (go vet, flutter analyze, proto-check, go test ./..., flutter
  test) passes with exit code 0; 160 Flutter tests pass.

Nothing was committed; all changes are in the working tree.
