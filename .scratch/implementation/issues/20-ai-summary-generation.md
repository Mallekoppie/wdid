# 20: AI summary generation

**What to build:** A user can generate a check-in summary with an OpenAI-compatible provider. The response streams into the editable summary, the API key comes only from the environment, and the prompt variant follows the check-in kind and audience. A failure leaves the existing summary untouched and offers a retry.

**Blocked by:** 05 (Settings preferences end-to-end), 18 (Check-in summary editing and audience), 19 (Export bundle and copy prompt)

**Status:** ready-for-agent

- [ ] Generation streams from an OpenAI-compatible endpoint into the summary editor.
- [ ] Prompt variants exist for manager 1:1, manager performance review, and personal review.
- [ ] The API key is read from the environment only and is never stored, exported, or logged.
- [ ] The redaction setting can strip URLs and notes from the payload.
- [ ] A failure leaves the existing summary untouched and offers a retry.
- [ ] A successful generation persists the model name and the prompt version.
- [ ] Settings → AI configures the provider base URL, model, and redaction; it never stores a key.
- [ ] Tests use a fake provider and cover prompt selection, redaction, success, and failure.
