package domain

import "strings"

// PromptVersion identifies the prompt template set. The text lives here, in one
// versioned place, so the client never composes a prompt of its own.
const PromptVersion = "v1"

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

// PromptTemplate returns the versioned instruction for one variant. The
// generation path and the Settings preview both read this map, so the prompt
// copy is never duplicated elsewhere.
func PromptTemplate(variant PromptVariant) (string, bool) {
	instruction, ok := promptInstructions[variant]
	return instruction, ok
}

// promptRules closes every variant with the same data-honesty constraints.
const promptRules = `Use only the data supplied with this check-in. Invent nothing: no achievements, metrics, names or links that are not present. Cite links only when they appear in the data. Output Markdown.`

// promptInstructions holds the exact template text for every variant.
var promptInstructions = map[PromptVariant]string{
	PromptVariantManagerOneOnOne: `You are preparing a software engineer for a 1:1 with their manager.

From the supplied period aggregates, focus notes and summary, produce:
- Five to seven highlight bullets, each with a measurable outcome.
- One short paragraph per project covering progress, impact and evidence.
- A collaboration paragraph covering who was supported and how.
- Time allocation observations: where the time went and any imbalance.
- Risks or gaps worth discussing.
- Three ready-to-paste bullets in the first person.

Style: concise, factual, no self-congratulation, no filler.

` + promptRules,

	PromptVariantManagerPerformanceReview: `You are preparing evidence for a formal performance review of a software engineer.

From the supplied period aggregates, focus notes and summary, produce:
- Five to seven evidence bullets, each tying a measurable outcome to a rating dimension.
- One short paragraph per project emphasising scope, impact and measurable results.
- A collaboration paragraph with concrete examples of people supported and outcomes.
- Time allocation observations that support the evidence.
- Risks, gaps and growth areas worth discussing in calibration.
- Three ready-to-paste performance review bullets in the first person.

Style: formal, specific and evidence-led. Prefer numbers that appear in the data.

` + promptRules,

	PromptVariantPersonalReview: `You are reviewing your own working period.

From the supplied period aggregates, focus notes and summary, produce:
- Where the time went, by category and project.
- What moved, with evidence from the recorded outcomes.
- What did not move, and why.
- Patterns worth changing.
- Up to three concrete changes for the next period.

Style: honest, specific and non-judgemental.

` + promptRules,
}
