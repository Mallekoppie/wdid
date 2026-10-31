# Per-user prompt templates with locked server rules

**Status:** Accepted — 2026-10-31

Users may edit the instruction body for each of the three check-in prompt
variants. The server keeps two things that a user can never edit or remove:

- the built-in body for every variant (`promptInstructions` in
  `internal/domain/checkin_prompt.go`), which is the default and the fallback;
- `domain.PromptRules`, the data-honesty suffix that closes every instruction
  (use only the supplied data, invent nothing, cite links only when present,
  output Markdown).

The resolved instruction is always `custom body (trimmed) + "\n\n" +
PromptRules`, or the built-in body plus the same rules when the user has no
non-blank override. A stored override therefore cannot omit, replace or
reorder the rules. Settings gains `PromptTemplates map[PromptVariant]string`
(JSON `promptTemplates`) inside the existing per-user record, so no store
migration is needed and an absent or empty map means "all built-ins". Blank
bodies are normalised away, and Reset (not a blank save) clears an override.

The check-in records the exact transcript sent to the provider
(`GenerationPrompt`, rendered by `RenderPromptSnapshot`) and the summary it
replaced (`PreviousSummaryMarkdown`, the one-step revert slot).
`PromptVersion` remains a label only: `v1` for a built-in body and `custom`
when an override was used; the snapshot is the real provenance record.

**Contradicts plan.md §9.3** ("the exact prompt text lives in one versioned
place in the service") **and the original `checkin_prompt.go:6` comment**
("the client never composes a prompt of its own"). The server still owns
resolution and the rules, but the instruction body is now per-user data. Both
statements need revisiting: plan §9.3 should describe the default bodies plus
the locked rules, and the code comment has been updated to say the server
resolves the body and always appends the rules.

**Considered options:** keeping prompts service-owned (rejected: users cannot
tune the output for their role or team); storing the whole resolved
instruction, rules included (rejected: a later rules change could be
overwritten by an old custom copy); letting a blank body mean "empty prompt"
(rejected: it would silently remove the instruction, and blank saves are
mistakes rather than intent); a separate prompt bucket (rejected: no benefit
over the settings record); redacting additional context from prompts (rejected:
it is deliberate user-supplied data for the model); snapshotting only the
instruction (rejected: no proof of what the model actually saw).

**Consequences:** existing settings and check-ins load unchanged; new JSON
fields are omitempty so an old record exports identically. Settings delivery
and the prompt RPCs are follow-up work. A custom body is still subject to the
locked rules, and the assembled prompt remains server-composed, so the
copy-prompt path and generation path can never disagree.
