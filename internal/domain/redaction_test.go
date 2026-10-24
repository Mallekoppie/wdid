package domain_test

import (
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func redactionFixture() domain.ExportInput {
	return domain.ExportInput{
		Report: domain.PeriodReport{
			FromDate:     "2026-10-19",
			ToDate:       "2026-10-25",
			TotalMinutes: 90,
			EntryCount:   1,
			Categories: []domain.CategoryTotal{
				{CategoryID: "cat-1", Name: "Projects", Role: domain.CategoryRoleInitiative, Minutes: 90, EntryCount: 1},
			},
			Subcategories: []domain.SubcategoryTotal{
				{SubcategoryID: "sub-1", CategoryID: "cat-1", Name: "Billing migration", Minutes: 90, EntryCount: 1},
			},
			Notes: []domain.Note{
				{ID: "note-1", Date: "2026-10-19", Text: "Private note at https://internal.example/notes"},
			},
		},
		Entries: []domain.WorkEntry{
			{
				ID:            "entry-1",
				CategoryID:    "cat-1",
				SubcategoryID: "sub-1",
				Description:   "Backfill script https://internal.example/runbook",
				Outcome:       "Shipped it https://internal.example/runbook",
				Minutes:       90,
			},
		},
		Categories: []domain.Category{
			{ID: "cat-1", Name: "Projects", Role: domain.CategoryRoleInitiative},
		},
		Subcategories: []domain.Subcategory{
			{
				ID:         "sub-1",
				CategoryID: "cat-1",
				Name:       "Billing migration",
				Links:      []domain.Link{{Label: "runbook", URL: "https://internal.example/runbook"}},
			},
		},
		FocusNotes:  "Manager focus https://internal.example/focus",
		GeneratedAt: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC),
	}
}

func TestRedactExportInputStripsURLsAndNotes(t *testing.T) {
	input := redactionFixture()
	redacted := domain.RedactExportInput(input)

	if len(redacted.Report.Notes) != 0 {
		t.Fatalf("notes = %+v, want none", redacted.Report.Notes)
	}
	if redacted.FocusNotes != "" {
		t.Fatalf("focus notes = %q, want none", redacted.FocusNotes)
	}
	if len(redacted.Subcategories[0].Links) != 0 {
		t.Fatalf("links = %+v, want none", redacted.Subcategories[0].Links)
	}
	if strings.Contains(redacted.Entries[0].Description, "https://") {
		t.Fatalf("description still holds a URL: %q", redacted.Entries[0].Description)
	}

	summary := domain.BuildExportSummary(redacted)
	for _, forbidden := range []string{
		"https://internal.example",
		"Private note",
		"Manager focus",
		"runbook",
	} {
		if strings.Contains(summary, forbidden) {
			t.Fatalf("redacted summary contains %q:\n%s", forbidden, summary)
		}
	}
	if !strings.Contains(summary, "[link removed]") {
		t.Fatalf("redacted summary = %q, want a visible redaction marker", summary)
	}

	// Redaction is a copy: the input the export uses keeps every field.
	if len(input.Report.Notes) != 1 || input.FocusNotes == "" ||
		len(input.Subcategories[0].Links) != 1 ||
		!strings.Contains(input.Entries[0].Description, "https://internal.example") {
		t.Fatal("RedactExportInput mutated its input")
	}
}

func TestBuildExportSummaryKeepsNotesAndURLsWithoutRedaction(t *testing.T) {
	summary := domain.BuildExportSummary(redactionFixture())

	for _, expected := range []string{
		"Private note at https://internal.example/notes",
		"Manager focus https://internal.example/focus",
		"https://internal.example/runbook",
	} {
		if !strings.Contains(summary, expected) {
			t.Fatalf("unredacted summary is missing %q:\n%s", expected, summary)
		}
	}
}
