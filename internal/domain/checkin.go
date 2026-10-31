package domain

import (
	"strings"
	"time"
)

// CheckInKind separates manager-facing check-ins from personal reviews.
type CheckInKind string

const (
	CheckInKindManager  CheckInKind = "manager"
	CheckInKindPersonal CheckInKind = "personal"
)

// Valid reports whether the check-in kind is known.
func (k CheckInKind) Valid() bool {
	switch k {
	case CheckInKindManager, CheckInKindPersonal:
		return true
	default:
		return false
	}
}

// CheckInState is where a check-in sits in its editing lifecycle.
type CheckInState string

const (
	CheckInStateDraft     CheckInState = "draft"
	CheckInStateGenerated CheckInState = "generated"
	CheckInStateEdited    CheckInState = "edited"
	CheckInStateFinal     CheckInState = "final"
)

// Valid reports whether the check-in state is known.
func (s CheckInState) Valid() bool {
	switch s {
	case CheckInStateDraft, CheckInStateGenerated, CheckInStateEdited, CheckInStateFinal:
		return true
	default:
		return false
	}
}

// Audience is who a manager check-in is prepared for.
type Audience string

const (
	AudienceOneOnOne          Audience = "one_on_one"
	AudiencePerformanceReview Audience = "performance_review"
)

// Valid reports whether the audience is known.
func (a Audience) Valid() bool {
	switch a {
	case AudienceOneOnOne, AudiencePerformanceReview:
		return true
	default:
		return false
	}
}

// CheckInTotals is the period snapshot taken when a check-in is created.
type CheckInTotals struct {
	Minutes         int            `json:"minutes"`
	ByCategory      map[string]int `json:"byCategory,omitempty"`
	BySubcategory   map[string]int `json:"bySubcategory,omitempty"`
	SupportByPerson map[string]int `json:"supportByPerson,omitempty"`
	// SupportMinutes and SupportInteractions are the authoritative support
	// totals captured from the period report. SupportByPerson rows credit each
	// name the full entry minutes, so their sum may exceed SupportMinutes.
	SupportMinutes      int `json:"supportMinutes"`
	SupportInteractions int `json:"supportInteractions"`
}

// EffectiveSupportMinutes returns the support minutes to display. Check-ins
// written before the authoritative totals existed store only SupportByPerson,
// so a zero stored total falls back to the row sum, which is exact for
// single-person legacy data. New snapshots keep their authoritative value.
func (t CheckInTotals) EffectiveSupportMinutes() int {
	if t.SupportMinutes == 0 && len(t.SupportByPerson) > 0 {
		total := 0
		for _, minutes := range t.SupportByPerson {
			total += minutes
		}
		return total
	}
	return t.SupportMinutes
}

// EffectiveSupportInteractions returns the support interaction count to
// display. Legacy check-ins have no stored count, so a zero falls back to the
// number of distinct people rows, which is what the pre-upgrade UI showed.
func (t CheckInTotals) EffectiveSupportInteractions() int {
	if t.SupportInteractions == 0 && len(t.SupportByPerson) > 0 {
		return len(t.SupportByPerson)
	}
	return t.SupportInteractions
}

// CheckInTotalsFromReport snapshots the authoritative period report into the
// totals a check-in stores at creation. Rows are keyed by category and
// subcategory ID; support people keep their display spelling.
func CheckInTotalsFromReport(report PeriodReport) CheckInTotals {
	totals := CheckInTotals{
		Minutes:             report.TotalMinutes,
		ByCategory:          make(map[string]int, len(report.Categories)),
		BySubcategory:       make(map[string]int, len(report.Subcategories)),
		SupportByPerson:     make(map[string]int, len(report.SupportPeople)),
		SupportMinutes:      report.SupportMinutes,
		SupportInteractions: report.SupportInteractions,
	}
	for _, category := range report.Categories {
		totals.ByCategory[category.CategoryID] = category.Minutes
	}
	for _, subcategory := range report.Subcategories {
		totals.BySubcategory[subcategory.SubcategoryID] = subcategory.Minutes
	}
	for _, person := range report.SupportPeople {
		totals.SupportByPerson[person.Person] = person.Minutes
	}
	return totals
}

// SummarySource says whether a summary update is the user's own text or
// generated output. Only generated text is blocked from replacing a manual
// edit without confirmation.
type SummarySource string

const (
	SummarySourceManual    SummarySource = "manual"
	SummarySourceGenerated SummarySource = "generated"
)

// CheckIn is a saved artifact covering a period, with focus notes, aggregates,
// an optional additional context and an optional summary. Only final manager
// check-ins move the boundary.
type CheckIn struct {
	ID              string       `json:"id"`
	UserID          string       `json:"userId"`
	Kind            CheckInKind  `json:"kind"`
	PeriodStart     string       `json:"periodStart"`
	PeriodEnd       string       `json:"periodEnd"`
	State           CheckInState `json:"state"`
	Audience        Audience     `json:"audience,omitempty"`
	FocusNotes      string       `json:"focusNotes,omitempty"`
	SummaryMarkdown string       `json:"summaryMarkdown,omitempty"`
	SummaryModel    string       `json:"summaryModel,omitempty"`
	PromptVersion   string       `json:"promptVersion,omitempty"`
	// AdditionalContext is the user's own supplied facts, recorded alongside
	// the ledger data. It is authoritative input for generation and is never
	// redacted.
	AdditionalContext string `json:"additionalContext,omitempty"`
	// GenerationPrompt is the exact transcript sent to the provider for the
	// current summary. It is the provenance record for the generated text.
	GenerationPrompt string `json:"generationPrompt,omitempty"`
	// PreviousSummaryMarkdown holds the summary replaced by the last generate
	// or refine, so one revert can restore it. Manual edits do not use it.
	PreviousSummaryMarkdown string        `json:"previousSummaryMarkdown,omitempty"`
	Totals                  CheckInTotals `json:"totals"`
	CreatedAt               time.Time     `json:"createdAt"`
	UpdatedAt               time.Time     `json:"updatedAt"`
}

// Normalize trims check-in input into its canonical form. A manager check-in
// always records an audience: one-on-one is the product default when the
// caller leaves it unspecified.
func (c *CheckIn) Normalize() {
	c.PeriodStart = strings.TrimSpace(c.PeriodStart)
	c.PeriodEnd = strings.TrimSpace(c.PeriodEnd)
	c.FocusNotes = strings.TrimSpace(c.FocusNotes)
	c.SummaryMarkdown = strings.TrimSpace(c.SummaryMarkdown)
	c.SummaryModel = strings.TrimSpace(c.SummaryModel)
	c.PromptVersion = strings.TrimSpace(c.PromptVersion)
	c.AdditionalContext = strings.TrimSpace(c.AdditionalContext)
	c.GenerationPrompt = strings.TrimSpace(c.GenerationPrompt)
	c.PreviousSummaryMarkdown = strings.TrimSpace(c.PreviousSummaryMarkdown)
	if c.Kind == CheckInKindManager && c.Audience == "" {
		c.Audience = AudienceOneOnOne
	}
	c.CreatedAt = utc(c.CreatedAt)
	c.UpdatedAt = utc(c.UpdatedAt)
}
