# 18: Check-in summary editing and audience

**What to build:** A user can edit a check-in summary as Markdown, save it, and choose the audience for a manager check-in. Manual edits are never overwritten without confirmation, and the audience preset changes only the prompt, not the underlying data.

**Blocked by:** 16 (Manager check-in create and finalize)

**Status:** ready-for-human

- [x] The summary can be edited and saved as Markdown.
- [x] A manager check-in can choose 1:1 or performance review as its audience.
- [x] The audience preset is visible on the check-in and used when building the prompt.
- [x] Manual edits are not overwritten without confirmation.
- [x] An empty summary is allowed.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover save, audience selection, and overwrite protection.

## Comments

Issue 16 had already landed the audience enum, the create-dialog selector and the
`UpdateCheckIn` summary save. This pass verified those and extended the slice
with a server-owned prompt variant, post-creation audience selection, a
contract-level overwrite guard, and the UI/tests around all of it.

Evidence per checkbox:

- Summary edited and saved as Markdown: the detail screen's existing Edit/Save
  flow (`web/lib/screens/checkin_detail_screen.dart`) calls
  `AppState.saveSummary`, which now tags the update `manual` and reaches
  `UpdateCheckInRequest.summary_markdown` through `GrpcCheckInApi.updateCheckIn`
  (`web/lib/data/checkin_api.dart`). The server stores the trimmed Markdown and
  moves the lifecycle to `edited` (`internal/rpc/checkin_service.go`). Covered
  by `TestCheckInServiceSavesSummaryAndProtectsManualEdits` (Connect and
  gRPC-Web), `saves a manual summary and maps the overwrite confirmation`
  (`web/test/checkin_api_test.dart`), and
  `edits and saves the summary as Markdown, including empty`
  (`web/test/checkin_flow_test.dart`).
- Audience choice: the create dialog already offered 1:1 / performance review.
  The detail screen now also has an audience selector for manager check-ins
  backed by `AppState.setCheckInAudience`, so a saved manager check-in can be
  switched later; a final check-in renders it disabled and a personal review
  has no selector. `domain.CheckIn.Normalize` now records the 1:1 default for a
  manager check-in that omits an audience. Covered by
  `TestCheckInServiceAudienceSelectsThePromptVariant` (both protocols) and
  `changes the audience and uses it to build the prompt` /
  `a personal review has no audience selector` widget tests.
- Audience visible and used by the prompt: the audience badge and selector are
  on the detail screen, and the prompt variant is selected by the stored
  audience in `internal/domain/checkin_prompt.go`
  (`PromptVariantFor`). The new `CheckInService.BuildCheckInPrompt` RPC returns
  the prompt text, version and variant for one check-in; the client shows the
  variant in the copy dialog title (`web/lib/widgets/forms/prompt_dialog.dart`)
  and the prompt text comes from the service. The three templates (1:1,
  performance review, personal review) live in that one versioned domain file.
  Covered by `TestPromptVariantFollowsKindAndAudience`,
  `TestBuildPromptSelectsTheVariantTemplateAndKeepsTheSummary`,
  `TestCheckInServiceAudienceSelectsThePromptVariant` (both protocols), and
  `maps the prompt variant returned for the audience`.
- Manual edits protected: `UpdateCheckInRequest` now carries
  `summary_source` (manual/generated) and `overwrite_manual_edits`. A generated
  summary that would replace a non-empty summary in the `edited` state is
  refused with `FailedPrecondition` unless the confirmation flag is set; a
  manual save is always the user's own action. The UI keeps the existing
  "Replace edited summary?" confirmation before regeneration. Covered over both
  protocols by `TestCheckInServiceSavesSummaryAndProtectsManualEdits` and by
  the demo-mode widget test `regenerating asks before replacing a manual edit`.
- Empty summary allowed: the service has no non-empty requirement and
  `Normalize` trims `""` to empty; the update succeeds and the UI shows its
  "No summary yet" empty state. Covered by the same server test (save `""`)
  and the widget save test.
- Loading, empty, error and validation states: the prompt button shows a spinner
  while the RPC runs and reports a failed build in a SnackBar without changing
  the check-in; the summary panel keeps its existing loading/empty/error states;
  an audience update failure is reported inline; empty summaries are valid and
  only anonymous-source enum values are rejected (`summarySource` field
  violation). Covered by the widget tests and the server validation assertions.
- Connect and gRPC-Web: `forEachCheckInProtocol` in
  `internal/rpc/checkin_service_test.go` runs the save/overwrite and
  audience/prompt tests under unary Connect and gRPC-Web. The Dart client is
  covered by `web/test/checkin_api_test.dart` and the widget flow by
  `web/test/checkin_flow_test.dart`.

Design notes:

- Prompt text lives in `internal/domain/checkin_prompt.go` with
  `PromptVersion = "v1"`, so a later SummaryService `BuildPrompt`/generation
  slice (issues 19/20) can reuse the same variants instead of duplicating text.
  `BuildCheckInPrompt` is on `CheckInService` because the variant depends on the
  check-in's persisted kind and audience.
- An unspecified audience is treated as the 1:1 default for manager check-ins,
  and the stored record is normalised to `one_on_one`, so the visible preset and
  the prompt always agree.
- The audience update sends the stored summary unchanged; changing it never
  mutates summary text or totals (asserted in the server and widget tests).

`make check` passes with exit code 0: proto-check (generated Go and Dart stubs
are current), `go vet`, `flutter analyze`, all Go tests, and all Flutter tests
(214 passed). Nothing was committed or pushed; all changes remain in the working
tree.

