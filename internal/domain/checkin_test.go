package domain_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestNormalizeTrimsTheCheckInAIFields(t *testing.T) {
	checkIn := domain.CheckIn{
		Kind:                    domain.CheckInKindManager,
		AdditionalContext:       "  The outage was caused by a bad deploy.  ",
		GenerationPrompt:        "\n[user]\nPrompt\n",
		PreviousSummaryMarkdown: "  # Previous summary\n  ",
	}

	checkIn.Normalize()

	if checkIn.AdditionalContext != "The outage was caused by a bad deploy." {
		t.Fatalf("additional context = %q, want it trimmed", checkIn.AdditionalContext)
	}
	if checkIn.GenerationPrompt != "[user]\nPrompt" {
		t.Fatalf("generation prompt = %q, want it trimmed", checkIn.GenerationPrompt)
	}
	if checkIn.PreviousSummaryMarkdown != "# Previous summary" {
		t.Fatalf("previous summary = %q, want it trimmed", checkIn.PreviousSummaryMarkdown)
	}
}

// TestLegacyCheckInJSONRoundTripsWithoutTheNewFields pins backwards
// compatibility: records written before additional context, the generation
// prompt and the revert slot existed must load, normalize and save without
// acquiring or changing any other field.
func TestLegacyCheckInJSONRoundTripsWithoutTheNewFields(t *testing.T) {
	const legacy = `{
		"id": "checkin-legacy",
		"userId": "user-1",
		"kind": "manager",
		"periodStart": "2026-10-01",
		"periodEnd": "2026-10-07",
		"state": "generated",
		"audience": "one_on_one",
		"focusNotes": "Freight billing",
		"summaryMarkdown": "# Summary\n- Shipped",
		"summaryModel": "claude-sonnet-5-5",
		"promptVersion": "v1",
		"totals": {"minutes": 120},
		"createdAt": "2026-10-07T17:00:00Z",
		"updatedAt": "2026-10-07T17:00:00Z"
	}`

	var checkIn domain.CheckIn
	if err := json.Unmarshal([]byte(legacy), &checkIn); err != nil {
		t.Fatalf("unmarshal legacy check-in: %v", err)
	}
	if checkIn.AdditionalContext != "" || checkIn.GenerationPrompt != "" || checkIn.PreviousSummaryMarkdown != "" {
		t.Fatalf("legacy check-in gained AI fields: %+v", checkIn)
	}
	checkIn.Normalize()

	encoded, err := json.Marshal(checkIn)
	if err != nil {
		t.Fatalf("marshal legacy check-in: %v", err)
	}
	for _, field := range []string{"additionalContext", "generationPrompt", "previousSummaryMarkdown"} {
		if strings.Contains(string(encoded), field) {
			t.Fatalf("saved legacy check-in contains empty %q: %s", field, encoded)
		}
	}
	for _, expected := range []string{
		`"focusNotes":"Freight billing"`,
		`"summaryMarkdown":"# Summary\n- Shipped"`,
		`"promptVersion":"v1"`,
	} {
		if !strings.Contains(string(encoded), expected) {
			t.Fatalf("saved legacy check-in is missing %s: %s", expected, encoded)
		}
	}
}

func TestCheckInTotalsFromReportKeepsSupportTotalsAuthoritative(t *testing.T) {
	// Per-person rows credit each name the full entry minutes, so they add up
	// to 120 here. The snapshot's totals must stay at the entry total of 75.
	report := domain.PeriodReport{
		TotalMinutes:        75,
		SupportMinutes:      75,
		SupportInteractions: 2,
		SupportPeople: []domain.SupportPersonTotal{
			{Person: "Alex", Minutes: 75, Interactions: 2},
			{Person: "Sam", Minutes: 45, Interactions: 1},
		},
	}

	totals := domain.CheckInTotalsFromReport(report)

	if totals.SupportMinutes != 75 || totals.SupportInteractions != 2 {
		t.Fatalf("support totals = %dm/%d interactions, want the authoritative 75m across 2 entries",
			totals.SupportMinutes, totals.SupportInteractions)
	}
	if got := totals.SupportByPerson["Alex"] + totals.SupportByPerson["Sam"]; got != 120 {
		t.Fatalf("support by person sums to %dm, want full credit per person (120m)", got)
	}
}

func TestCheckInTotalsLegacySupportFallback(t *testing.T) {
	// Legacy check-ins written before the authoritative totals existed store
	// only per-person rows. Single-person data makes the sum exact and the row
	// count the interaction count.
	legacy := domain.CheckInTotals{
		SupportByPerson: map[string]int{"Priya": 30},
	}
	if got := legacy.EffectiveSupportMinutes(); got != 30 {
		t.Fatalf("legacy effective minutes = %d, want the 30m row sum", got)
	}
	if got := legacy.EffectiveSupportInteractions(); got != 1 {
		t.Fatalf("legacy effective interactions = %d, want the single row", got)
	}

	// A fresh multi-person snapshot keeps its authoritative totals even though
	// the rows credit each name the full entry minutes.
	fresh := domain.CheckInTotals{
		SupportMinutes:      45,
		SupportInteractions: 2,
		SupportByPerson:     map[string]int{"Priya": 45, "Sam": 45},
	}
	if got := fresh.EffectiveSupportMinutes(); got != 45 {
		t.Fatalf("fresh effective minutes = %d, want the authoritative 45m", got)
	}
	if got := fresh.EffectiveSupportInteractions(); got != 2 {
		t.Fatalf("fresh effective interactions = %d, want the authoritative 2", got)
	}

	// With no rows at all the stored zero is the answer.
	empty := domain.CheckInTotals{}
	if empty.EffectiveSupportMinutes() != 0 || empty.EffectiveSupportInteractions() != 0 {
		t.Fatalf("empty effective totals = %dm/%d, want 0/0",
			empty.EffectiveSupportMinutes(), empty.EffectiveSupportInteractions())
	}
}
