# 20: AI summary generation

**What to build:** A user can generate a check-in summary with an OpenAI-compatible provider. The response streams into the editable summary, the API key comes only from the environment, and the prompt variant follows the check-in kind and audience. A failure leaves the existing summary untouched and offers a retry.

**Blocked by:** 05 (Settings preferences end-to-end), 18 (Check-in summary editing and audience), 19 (Export bundle and copy prompt)

**Status:** ready-for-human

- [x] Generation streams from an OpenAI-compatible endpoint into the summary editor.
- [x] Prompt variants exist for manager 1:1, manager performance review, and personal review.
- [x] The API key is read from the environment only and is never stored, exported, or logged.
- [x] The redaction setting can strip URLs and notes from the payload.
- [x] A failure leaves the existing summary untouched and offers a retry.
- [x] A successful generation persists the model name and the prompt version.
- [x] Settings → AI configures the provider base URL, model, and redaction; it never stores a key.
- [x] Tests use a fake provider and cover prompt selection, redaction, success, and failure.

## Comments

Implemented the full generation path: proto/RPC, provider abstraction, redaction, config, Flutter client/state/UI, and tests.

- **Streaming generation.** `internal/contracts/summaries.proto` adds server-streaming `SummaryService.GenerateSummary` (`GenerateSummaryRequest`/`GenerateSummaryDelta`). `internal/rpc/summary_service.go` streams provider deltas with `connect.ServerStream` and `internal/ai/provider.go` implements the OpenAI-compatible `POST {baseURL}/chat/completions` SSE protocol. `web/lib/data/summary_api.dart`, `web/lib/state/app_state.dart` and `web/lib/screens/checkin_detail_screen.dart` consume the stream and render it live in the summary panel. Evidence: `internal/ai/provider_test.go`, `internal/rpc/summary_service_test.go` (`...StreamsAndPersistsMetadata`), `web/test/summary_api_test.dart`, `web/test/checkin_flow_test.dart`.
- **Prompt variants.** The existing versioned templates in `internal/domain/checkin_prompt.go` now also expose `PromptTemplate` for the service-owned preview. `GenerateSummary` selects via `domain.PromptVariantFor(checkIn)`, so manager 1:1, manager performance review and personal review each reach the provider. Evidence: `TestSummaryServiceGenerateSummarySelectsThePromptVariant`, `TestSummaryServiceGetPromptTemplate`, plus the existing `internal/domain/checkin_prompt_test.go`.
- **Environment-only key.** `internal/config/config.go` reads `WDID_OPENAI_API_KEY` into an in-memory field; `cmd/wdid/main.go` passes it to the service. The key is never in the settings proto/domain model, never written to the database, never included in exports (verified by `TestSummaryServiceExportNeverContainsTheAIKey`), and no code logs it. `TestLoadReadsTheOpenAIKeyFromTheEnvironmentOnly` covers the config read.
- **Redaction.** `internal/domain/redaction.go` copies the export input and clears day/project notes, focus notes and check-in summaries, drops link lists, and replaces URL text with `[link removed]`. `GenerateSummary` applies it only when `settings.AIRedact` is set, so exports still keep complete data. Evidence: `internal/domain/redaction_test.go`, `TestSummaryServiceGenerateSummaryRedactionStripsURLsAndNotes`.
- **Non-destructive failure + retry.** The server persists only after the provider stream completes successfully; a provider/empty response leaves the stored summary, model and prompt version untouched and ends the stream with an error. The Flutter screen discards the partial preview, keeps the existing summary, shows the error inline and adds a `Retry` action. Evidence: `TestSummaryServiceGenerateSummaryFailureIsNonDestructiveAndRetryable`, `TestSummaryServiceGenerateSummaryRequiresConfirmationForManualEdits`, `web/test/checkin_flow_test.dart` (`a failed generation keeps the summary and offers a retry`).
- **Generation metadata.** On success the service writes the accumulated Markdown, the provider-reported model (falling back to the configured model) and `domain.PromptVersion` through `store.SaveCheckIn`, marks the check-in `generated`, and returns the persisted check-in in the final delta. Evidence: `TestSummaryServiceGenerateSummaryStreamsAndPersistsMetadata`.
- **Settings → AI.** The panel in `web/lib/screens/settings_screen.dart` edits only base URL, model and redaction, displays the fixed OpenAI-compatible provider and the `WDID_OPENAI_API_KEY` source, and has no stored-key option. The prompt preview now calls the service (`GetPromptTemplate`) instead of duplicating prompt text. Evidence: `web/test/settings_ai_test.dart`, `web/test/summary_api_test.dart`.
- **Tests.** RPC tests inject `fakeAIProvider` (no network); the provider has its own `httptest` protocol test; Flutter tests use `FakeSummaryApi`. Coverage spans prompt selection, redaction on/off, success, provider failure, retry, manual-edit confirmation, missing key and key non-export.

`make check` passes (exit 0): proto-check (fresh generation), `go vet`, Flutter analyze, the Go suite and the Flutter suite (223 tests).
