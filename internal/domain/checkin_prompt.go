package domain

import "strings"

// PromptVersion identifies the built-in prompt template set. The built-in
// bodies live here; a per-user override in Settings.PromptTemplates may replace
// one, but the client still never composes a prompt of its own: the server
// resolves the body and always appends the locked PromptRules.
const PromptVersion = "v1"

// PromptVersionCustom labels a generated summary whose instruction body came
// from a per-user override rather than the built-in body. The stored prompt
// snapshot, not this label, is the provenance record.
const PromptVersionCustom = "custom"

// PromptVariant names the prompt template a check-in uses. The audience picks
// the manager variant; a personal review always uses the personal one.
type PromptVariant string

const (
	PromptVariantManagerOneOnOne          PromptVariant = "manager_one_on_one"
	PromptVariantManagerPerformanceReview PromptVariant = "manager_performance_review"
	PromptVariantPersonalReview           PromptVariant = "personal_review"
)

// Valid reports whether the prompt variant is known.
func (v PromptVariant) Valid() bool {
	switch v {
	case PromptVariantManagerOneOnOne, PromptVariantManagerPerformanceReview, PromptVariantPersonalReview:
		return true
	default:
		return false
	}
}

// PromptVariantFor selects the template from the check-in's kind and audience.
// An unset manager audience falls back to the one-on-one default.
func PromptVariantFor(checkIn CheckIn) PromptVariant {
	if checkIn.Kind == CheckInKindPersonal {
		return PromptVariantPersonalReview
	}
	if checkIn.Audience == AudiencePerformanceReview {
		return PromptVariantManagerPerformanceReview
	}
	return PromptVariantManagerOneOnOne
}

// BuildPrompt returns the prompt block for a check-in: the variant's
// instruction followed by the check-in's Markdown summary, exactly what the
// user would paste into a model. The summary is never modified.
func BuildPrompt(checkIn CheckIn) string {
	instruction, _ := PromptTemplate(PromptVariantFor(checkIn))
	summary := strings.TrimSpace(checkIn.SummaryMarkdown)
	if summary == "" {
		return instruction
	}
	return instruction + "\n\n" + summary
}

// PromptTemplate returns the built-in instruction for one variant: its default
// body followed by the locked rules. Callers that honour per-user overrides use
// ResolveInstruction instead; this stays for the built-in-only compatibility
// paths.
func PromptTemplate(variant PromptVariant) (string, bool) {
	body, ok := BuiltInPromptBody(variant)
	if !ok {
		return "", false
	}
	return body + "\n\n" + PromptRules, true
}

// BuiltInPromptBody returns one variant's built-in instruction body without the
// locked rules, and whether the variant is known. It is the fallback used when
// the caller has no override.
func BuiltInPromptBody(variant PromptVariant) (string, bool) {
	body, ok := promptInstructions[variant]
	if !ok {
		return "", false
	}
	return strings.TrimSpace(body), true
}

// ResolveInstruction returns the instruction the server sends for one variant.
// A non-blank body stored on the user's settings replaces the built-in body;
// otherwise the built-in body is used. The server-owned PromptRules are always
// appended last, so a custom body can never remove, replace or reorder them.
// An unknown variant returns an empty string.
func ResolveInstruction(variant PromptVariant, settings Settings) string {
	body := strings.TrimSpace(settings.PromptTemplates[variant])
	if body == "" {
		builtIn, ok := promptInstructions[variant]
		if !ok {
			return ""
		}
		body = strings.TrimSpace(builtIn)
	}
	return body + "\n\n" + PromptRules
}

// ResolvePromptVersion returns the label recorded with a generated summary:
// PromptVersionCustom when the variant has a non-blank user override, and
// PromptVersion when the built-in body was used.
func ResolvePromptVersion(variant PromptVariant, settings Settings) string {
	if strings.TrimSpace(settings.PromptTemplates[variant]) != "" {
		return PromptVersionCustom
	}
	return PromptVersion
}

// PromptRules closes every resolved instruction with the same server-owned
// data-honesty constraints. It is locked: users may replace the body above it
// but never edit, omit or reorder the rules.
const PromptRules = `Use only the data supplied with this check-in. Invent nothing: no achievements, metrics, names or links that are not present. Cite links only when they appear in the data. Output Markdown.`

// PromptMessage is one turn of the exact prompt sent to a provider. The
// generation path stores RenderPromptSnapshot of these messages as the
// check-in's provenance record.
type PromptMessage struct {
	Role    string
	Content string
}

// Prompt roles used in a rendered snapshot. They match the provider protocol.
const (
	PromptRoleUser      = "user"
	PromptRoleAssistant = "assistant"
)

// RenderPromptSnapshot renders the exact transcript of the messages sent to a
// provider. The output is deterministic: messages appear in slice order, each
// one preceded by a role marker, with a blank line between turns. Trailing
// newlines on a message's content are dropped so the separators are stable.
func RenderPromptSnapshot(messages []PromptMessage) string {
	parts := make([]string, 0, len(messages))
	for _, message := range messages {
		role := strings.TrimSpace(message.Role)
		content := strings.TrimRight(message.Content, "\r\n")
		parts = append(parts, "["+role+"]\n"+content)
	}
	return strings.Join(parts, "\n\n")
}

// promptInstructions holds the built-in instruction body for every variant.
// The locked PromptRules are appended by ResolveInstruction, never stored here.
var promptInstructions = map[PromptVariant]string{
	PromptVariantManagerOneOnOne: `You are preparing a software engineer for a 1:1 with their manager.

From the supplied period aggregates, focus notes and summary, produce:
- Five to seven highlight bullets, each with a measurable outcome.
- One short paragraph per project covering progress, impact and evidence.
- A collaboration paragraph covering who was supported and how.
- Time allocation observations: where the time went and any imbalance.
- Risks or gaps worth discussing.
- Three ready-to-paste bullets in the first person.

Style: concise, factual, no self-congratulation, no filler.`,

	PromptVariantManagerPerformanceReview: `You are preparing evidence for a formal performance review of a software engineer.

From the supplied period aggregates, focus notes and summary, produce:
- Five to seven evidence bullets, each tying a measurable outcome to a rating dimension.
- One short paragraph per project emphasising scope, impact and measurable results.
- A collaboration paragraph with concrete examples of people supported and outcomes.
- Time allocation observations that support the evidence.
- Risks, gaps and growth areas worth discussing in calibration.
- Three ready-to-paste performance review bullets in the first person.

Style: formal, specific and evidence-led. Prefer numbers that appear in the data.`,

	PromptVariantPersonalReview: `You are reviewing your own working period.

From the supplied period aggregates, focus notes and summary, produce:
- Where the time went, by category and project.
- What moved, with evidence from the recorded outcomes.
- What did not move, and why.
- Patterns worth changing.
- Up to three concrete changes for the next period.

Style: honest, specific and non-judgemental.`,
}
