package export_test

import (
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/export"
)

func TestFormatMinutes(t *testing.T) {
	tests := map[int]string{
		0:   "0m",
		42:  "42m",
		60:  "1h 00m",
		245: "4h 05m",
	}

	for minutes, want := range tests {
		if got := export.FormatMinutes(minutes); got != want {
			t.Fatalf("FormatMinutes(%d) = %q, want %q", minutes, got, want)
		}
	}
}

func TestSummarize(t *testing.T) {
	from := time.Date(2026, 7, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC)
	base := from.Add(24 * time.Hour)

	initiative := domain.Initiative{ID: "init-1", Name: "Billing migration"}

	entries := []domain.Entry{
		{
			ID: "e1", Kind: domain.EntryInitiative, InitiativeID: "init-1",
			Description: "Backfill script", Outcome: "Script runs against staging",
			StartedAt: base, EndedAt: base.Add(time.Hour), Minutes: 60,
		},
		{
			ID: "e2", Kind: domain.EntrySupport,
			Description: "Unblocked CI", Outcome: "script runs against staging",
			StartedAt: base.Add(2 * time.Hour), EndedAt: base.Add(150 * time.Minute), Minutes: 30,
			Support: &domain.SupportDetail{Person: "Priya", Mode: domain.SupportUnblock},
		},
		{
			ID: "e3", Kind: domain.EntryOther,
			Description: "Sprint planning",
			StartedAt:   base.Add(3 * time.Hour), EndedAt: base.Add(195 * time.Minute), Minutes: 15,
		},
		{
			ID: "e4", Kind: domain.EntryOther,
			Description: "Outside the period",
			StartedAt:   to.Add(time.Hour), EndedAt: to.Add(2 * time.Hour), Minutes: 60,
		},
	}

	summary := export.Summarize(entries, []domain.Initiative{initiative}, from, to)

	if summary.TotalMinutes != 105 {
		t.Fatalf("total minutes = %d, want 105", summary.TotalMinutes)
	}
	if summary.EntryCount != 3 {
		t.Fatalf("entry count = %d, want 3", summary.EntryCount)
	}
	if summary.ByKind["initiative"] != 60 || summary.ByKind["support"] != 30 || summary.ByKind["other"] != 15 {
		t.Fatalf("by kind = %v", summary.ByKind)
	}
	if len(summary.ByInitiative) != 1 || summary.ByInitiative[0].Name != "Billing migration" {
		t.Fatalf("by initiative = %+v", summary.ByInitiative)
	}
	if len(summary.Support) != 1 || summary.Support[0].Person != "Priya" || summary.Support[0].Minutes != 30 {
		t.Fatalf("support = %+v", summary.Support)
	}
	if summary.SupportPeople != 1 {
		t.Fatalf("support people = %d, want 1", summary.SupportPeople)
	}
	if len(summary.Outcomes) != 1 {
		t.Fatalf("outcomes = %v, want one deduplicated outcome", summary.Outcomes)
	}
}

func TestMarkdown(t *testing.T) {
	summary := export.Summary{
		From:         time.Date(2026, 7, 1, 0, 0, 0, 0, time.UTC),
		To:           time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC),
		TotalMinutes: 105,
		EntryCount:   3,
		ByKind:       map[string]int{"initiative": 60, "support": 30, "other": 15},
		ByInitiative: []export.InitiativeTotal{{InitiativeID: "init-1", Name: "Billing migration", Minutes: 60, EntryCount: 1}},
		Support:      []export.SupportTotal{{Person: "Priya", Mode: "unblock", Minutes: 30, Count: 1}},
		Outcomes:     []string{"Script runs against staging"},
	}

	markdown := export.Markdown(summary)

	for _, expected := range []string{
		"# wdid period summary",
		"**Period:** 2026-07-01 -> 2026-10-02",
		"**Total:** 1h 45m across 3 entries",
		"- Billing migration: 1h 00m across 1 entries",
		"- Priya (unblock): 30m across 1 interactions",
		"- Script runs against staging",
	} {
		if !strings.Contains(markdown, expected) {
			t.Fatalf("markdown missing %q:\n%s", expected, markdown)
		}
	}
}
