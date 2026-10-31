package domain_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func exportContextFixture() domain.ExportInput {
	return domain.ExportInput{
		Report: domain.PeriodReport{
			FromDate:     "2026-10-19",
			ToDate:       "2026-10-25",
			TotalMinutes: 60,
			EntryCount:   1,
			Notes: []domain.Note{
				{ID: "note-1", Date: "2026-10-24", Text: "Recorded by the ledger"},
			},
		},
		FocusNotes: "Land the billing migration",
		CheckIns: []domain.CheckIn{
			{
				ID:              "checkin-1",
				Kind:            domain.CheckInKindManager,
				PeriodStart:     "2026-10-19",
				PeriodEnd:       "2026-10-25",
				FocusNotes:      "Land the billing migration",
				SummaryMarkdown: "# Summary",
				PromptVersion:   "custom",
			},
		},
		Settings: domain.Settings{
			UserID:    "user-1",
			Timezone:  "UTC",
			WeekStart: 1,
			AIAPIKey:  "sk-must-not-be-exported",
		},
		GeneratedAt: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC),
	}
}

func TestBuildExportSummaryRendersAdditionalContextAfterFocusNotes(t *testing.T) {
	input := exportContextFixture()
	input.AdditionalContext = "The billing outage was caused by a bad deploy.\nIt touched three customers.\n\nWe added a canary gate."

	summary := domain.BuildExportSummary(input)

	if !strings.Contains(summary, "## Notes and context") {
		t.Fatalf("summary is missing the notes section:\n%s", summary)
	}
	if !strings.Contains(summary, "Additional context:") {
		t.Fatalf("summary is missing the additional-context label:\n%s", summary)
	}
	// Paragraph breaks are preserved, not collapsed onto one line.
	if !strings.Contains(summary, "The billing outage was caused by a bad deploy.\nIt touched three customers.\n\nWe added a canary gate.") {
		t.Fatalf("summary did not preserve the context paragraphs:\n%s", summary)
	}

	focusAt := strings.Index(summary, "- Focus notes: Land the billing migration")
	contextAt := strings.Index(summary, "Additional context:")
	noteAt := strings.Index(summary, "- 2026-10-24: Recorded by the ledger")
	if focusAt < 0 || contextAt < 0 || noteAt < 0 {
		t.Fatalf("notes section is missing an expected line:\n%s", summary)
	}
	if !(focusAt < contextAt && contextAt < noteAt) {
		t.Fatalf("additional context must follow focus notes and precede ledger notes (focus %d, context %d, note %d):\n%s",
			focusAt, contextAt, noteAt, summary)
	}
}

func TestBuildExportSummaryWithoutAdditionalContextKeepsTheNotesSection(t *testing.T) {
	input := exportContextFixture()
	input.Report.Notes = append(input.Report.Notes, domain.Note{ID: "note-2", Date: "2026-10-25", Text: "Another note"})

	summary := domain.BuildExportSummary(input)

	if strings.Contains(summary, "Additional context:") {
		t.Fatalf("summary invented a context block:\n%s", summary)
	}
	want := "## Notes and context\n" +
		"- Focus notes: Land the billing migration\n" +
		"- 2026-10-24: Recorded by the ledger\n" +
		"- 2026-10-25: Another note\n" +
		"\n## Source data\n"
	if !strings.Contains(summary, want) {
		t.Fatalf("summary notes section changed for an existing check-in:\n%s", summary)
	}
}

func TestBuildExportDataIncludesAdditionalContextAndGenerationPrompt(t *testing.T) {
	input := exportContextFixture()
	input.AdditionalContext = "The ledger missed the outage postmortem."
	input.CheckIns[0].AdditionalContext = "The ledger missed the outage postmortem."
	input.CheckIns[0].GenerationPrompt = "[user]\nInstruction\n\n# wdid work report"
	input.Settings.PromptTemplates = map[domain.PromptVariant]string{
		domain.PromptVariantManagerOneOnOne: "Write a blunt summary.",
	}

	bundle, err := domain.BuildExportBundle(input)
	if err != nil {
		t.Fatalf("build export: %v", err)
	}
	content := exportContent(t, bundle, domain.ExportDataFileName)

	var data map[string]any
	if err := json.Unmarshal([]byte(content), &data); err != nil {
		t.Fatalf("parse data.json: %v", err)
	}

	checkIns := data["checkIns"].([]any)
	if len(checkIns) != 1 {
		t.Fatalf("check-ins = %v, want one", checkIns)
	}
	checkIn := checkIns[0].(map[string]any)
	if checkIn["additionalContext"] != "The ledger missed the outage postmortem." {
		t.Fatalf("exported additionalContext = %v", checkIn["additionalContext"])
	}
	if checkIn["generationPrompt"] != "[user]\nInstruction\n\n# wdid work report" {
		t.Fatalf("exported generationPrompt = %v", checkIn["generationPrompt"])
	}

	settings := data["settingsSummary"].(map[string]any)
	templates, ok := settings["promptTemplates"].(map[string]any)
	if !ok {
		t.Fatalf("settings summary promptTemplates = %v, want a map", settings["promptTemplates"])
	}
	if templates[string(domain.PromptVariantManagerOneOnOne)] != "Write a blunt summary." {
		t.Fatalf("exported prompt templates = %v", templates)
	}
	if _, ok := settings["aiApiKey"]; ok {
		t.Fatalf("settings summary leaked an API key field: %v", settings)
	}
	if strings.Contains(content, "sk-must-not-be-exported") {
		t.Fatalf("data.json contains the API key:\n%s", content)
	}
}

func TestBuildExportDataOmitsEmptyAIProvenanceForExistingCheckIns(t *testing.T) {
	input := exportContextFixture()

	bundle, err := domain.BuildExportBundle(input)
	if err != nil {
		t.Fatalf("build export: %v", err)
	}
	content := exportContent(t, bundle, domain.ExportDataFileName)

	var data map[string]any
	if err := json.Unmarshal([]byte(content), &data); err != nil {
		t.Fatalf("parse data.json: %v", err)
	}

	checkIn := data["checkIns"].([]any)[0].(map[string]any)
	for _, field := range []string{"additionalContext", "generationPrompt"} {
		if _, ok := checkIn[field]; ok {
			t.Fatalf("legacy check-in export gained empty %q: %v", field, checkIn)
		}
	}
	for _, field := range []string{"focusNotes", "summaryMarkdown", "promptVersion"} {
		if _, ok := checkIn[field]; !ok {
			t.Fatalf("legacy check-in export lost %q: %v", field, checkIn)
		}
	}
	settings := data["settingsSummary"].(map[string]any)
	if _, ok := settings["promptTemplates"]; ok {
		t.Fatalf("settings summary gained an empty prompt template map: %v", settings)
	}
}

func exportContent(t *testing.T, bundle domain.ExportBundle, name string) string {
	t.Helper()
	for _, file := range bundle.Files {
		if file.Name == name {
			return file.Content
		}
	}
	t.Fatalf("export bundle has no %q", name)
	return ""
}
