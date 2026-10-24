# 12: Project notes

**What to build:** A user can add, edit, and delete notes on a project, and can save an end-of-day note from Today. Notes provide context that the work entries alone do not capture.

**Blocked by:** 11 (Project detail: timeline and report)

**Status:** ready-for-human

- [x] A project note can be created, edited, and deleted from the project detail.
- [x] The end-of-day note on Today is saved as a day note.
- [x] Day notes and project notes use the same note model and survive a restart.
- [x] Notes appear in the project detail in newest-first order.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover create, update, delete, and the two note contexts.

## Comments

- Added `internal/contracts/notes.proto` with one `Note` model and
  `NoteService` (`ListNotes`, `CreateNote`, `UpdateNote`, `DeleteNote`). A note
  carries a date, a subcategory id, or both; list filters by either.
- Added `internal/rpc/note_service.go`, registered it in `cmd/wdid/main.go` and
  in the domain test harness (`internal/rpc/domain_service_test.go`), and gave it
  a `NoteServiceName` in `internal/config/config.go`. The existing
  `internal/domain.Note`, `store.SaveNote`/`Notes`/`DeleteNote` and
  `domain.ValidateNote` were reused rather than duplicated; the store already
  returns notes newest first.
- The Flutter client gets `web/lib/data/note_api.dart` (`NoteApi`,
  `GrpcNoteApi`, `GrpcNoteRpc`, `noteFromProto`). A wire `subcategory_id` maps to
  the existing `Note.initiativeId` slot, so day notes and project notes share
  one UI model. `main.dart` wires the service-backed note client.
- `AppState` now owns today's notes plus a per-project note listing with
  loading/error/id guards, and create/update/delete paths that use `NoteApi`
  when present and the demo adapter otherwise. `WdidRepository` and
  `DemoWdidRepository` gained `deleteNote`.
- The project detail's third tab is Notes: newest first, empty/loading/error
  states, retry, and Edit/Delete actions behind a confirmation. `Add note` is
  always visible for open projects; archived projects keep notes read-only.
  `showNoteDialog` now accepts an existing note for editing.
- The Today end-of-day card loads the day note from the service, shows
  loading/error with Retry, rejects an empty save ("Write a note first."), and
  updates an existing day note instead of creating a duplicate.
- Tests: `internal/rpc/note_service_test.go` covers auth, create/list/update/
  delete for both contexts, newest-first ordering, validation fields, account
  isolation, restart persistence, and the full flow over gRPC-Web. Flutter tests
  cover proto mapping/pagination/errors (`web/test/note_api_test.dart`), project
  notes create/edit/delete/empty/loading/error/validation/archived
  (`web/test/project_detail_test.dart`), and day-note save/update/validation/
  error states (`web/test/today_quick_capture_test.dart`).
- `make check` passes: proto-check, `go vet`, `flutter analyze`, all Go tests,
  and all 144 Flutter tests.
