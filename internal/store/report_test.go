package store_test

import (
	"errors"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func reportFixture(t *testing.T, database *store.Store, userID string) (domain.Category, domain.Subcategory) {
	t.Helper()

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}

	settings := domain.DefaultSettings(userID)
	settings.Timezone = "Europe/Amsterdam"
	if err := database.SaveSettings(settings); err != nil {
		t.Fatalf("save settings: %v", err)
	}
	return category, subcategory
}

func TestPeriodReportFiltersByTheUsersLocalDates(t *testing.T) {
	database := newStore(t)
	userID := "user-report"
	category, subcategory := reportFixture(t, database, userID)

	entries := []domain.WorkEntry{
		// 22:30 UTC on 18 October is 00:30 on 19 October in Amsterdam.
		testWorkEntry(userID, category, subcategory.ID, time.Date(2026, 10, 18, 22, 30, 0, 0, time.UTC), "After midnight"),
		// 20:00 UTC on 19 October is 22:00 the same local day.
		testWorkEntry(userID, category, subcategory.ID, time.Date(2026, 10, 19, 20, 0, 0, 0, time.UTC), "Evening work"),
		// 22:30 UTC on 19 October is already 20 October in Amsterdam.
		testWorkEntry(userID, category, subcategory.ID, time.Date(2026, 10, 19, 22, 30, 0, 0, time.UTC), "Next local day"),
	}
	for _, entry := range entries {
		if err := database.SaveWorkEntry(entry); err != nil {
			t.Fatalf("save entry: %v", err)
		}
	}

	if err := database.SaveNote(domain.Note{
		ID:        "note-in-period",
		UserID:    userID,
		Date:      "2026-10-19",
		Text:      "Shipped it",
		CreatedAt: time.Date(2026, 10, 19, 21, 0, 0, 0, time.UTC),
	}); err != nil {
		t.Fatalf("save note: %v", err)
	}
	if err := database.SaveNote(domain.Note{
		ID:        "note-outside",
		UserID:    userID,
		Date:      "2026-10-20",
		Text:      "Tomorrow",
		CreatedAt: time.Date(2026, 10, 20, 8, 0, 0, 0, time.UTC),
	}); err != nil {
		t.Fatalf("save note: %v", err)
	}

	report, err := database.PeriodReport(userID, "2026-10-19", "2026-10-19")
	if err != nil {
		t.Fatalf("period report: %v", err)
	}

	if report.TotalMinutes != 84 || report.EntryCount != 2 {
		t.Fatalf("report totals = %dm/%d entries, want the two local-day entries (84m)", report.TotalMinutes, report.EntryCount)
	}
	if len(report.Categories) != 1 || report.Categories[0].Name != "Initiatives" || report.Categories[0].Minutes != 84 {
		t.Fatalf("categories = %+v, want Initiatives with 84m", report.Categories)
	}
	if len(report.Subcategories) != 1 || report.Subcategories[0].Name != "Billing migration" {
		t.Fatalf("subcategories = %+v, want Billing migration", report.Subcategories)
	}
	if len(report.Notes) != 1 || report.Notes[0].ID != "note-in-period" {
		t.Fatalf("notes = %+v, want only the note dated inside the period", report.Notes)
	}
}

func TestPeriodReportIsPerUserAndEmptyPeriodsAreZero(t *testing.T) {
	database := newStore(t)
	category, subcategory := reportFixture(t, database, "user-report")
	if err := database.SaveWorkEntry(testWorkEntry("user-report", category, subcategory.ID, time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC), "Mine")); err != nil {
		t.Fatalf("save entry: %v", err)
	}

	// The other account has no entries, so its report must not see them.
	other, err := database.PeriodReport("user-other", "2026-10-19", "2026-10-19")
	if err != nil {
		t.Fatalf("other report: %v", err)
	}
	if other.TotalMinutes != 0 || other.EntryCount != 0 {
		t.Fatalf("other user totals = %dm/%d, want zero", other.TotalMinutes, other.EntryCount)
	}

	empty, err := database.PeriodReport("user-report", "2026-01-01", "2026-01-07")
	if err != nil {
		t.Fatalf("empty period: %v", err)
	}
	if empty.TotalMinutes != 0 || len(empty.Categories) != 0 || len(empty.Notes) != 0 {
		t.Fatalf("empty period = %+v, want zero totals", empty)
	}
	if len(empty.Weeks) != 2 || empty.Weeks[0].Minutes != 0 || empty.Weeks[1].Minutes != 0 {
		t.Fatalf("empty weeks = %+v, want the two weeks the period touches, both zeroed", empty.Weeks)
	}
}

func TestPeriodReportIncludesProjectMilestoneProgress(t *testing.T) {
	database := newStore(t)
	userID := "user-report"
	_, subcategory := reportFixture(t, database, userID)
	other := testSubcategory(userID, subcategory.CategoryID, "Dependency spike")
	if err := database.SaveSubcategory(other); err != nil {
		t.Fatalf("save other subcategory: %v", err)
	}

	now := time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)
	milestones := []domain.Milestone{
		{ID: "m1", UserID: userID, SubcategoryID: subcategory.ID, Title: "Plan", Done: true, CreatedAt: now, UpdatedAt: now},
		{ID: "m2", UserID: userID, SubcategoryID: subcategory.ID, Title: "Ship", DueDate: "2026-11-15", CreatedAt: now, UpdatedAt: now},
		{ID: "m3", UserID: userID, SubcategoryID: other.ID, Title: "Spike", CreatedAt: now, UpdatedAt: now},
	}
	for _, milestone := range milestones {
		if err := database.SaveMilestone(milestone); err != nil {
			t.Fatalf("save milestone: %v", err)
		}
	}

	// No entries fall in this period, but project completion is still reported.
	report, err := database.PeriodReport(userID, "2026-01-01", "2026-01-07")
	if err != nil {
		t.Fatalf("period report: %v", err)
	}
	if len(report.Milestones) != 2 {
		t.Fatalf("milestone progress = %+v, want two projects", report.Milestones)
	}
	progressByProject := map[string]domain.MilestoneProgress{}
	for _, progress := range report.Milestones {
		progressByProject[progress.SubcategoryID] = progress
	}
	projectProgress := progressByProject[subcategory.ID]
	if projectProgress.Total != 2 || projectProgress.Done != 1 {
		t.Fatalf("project milestone progress = %+v, want 1 of 2 done", projectProgress)
	}
	otherProgress := progressByProject[other.ID]
	if otherProgress.Total != 1 || otherProgress.Done != 0 {
		t.Fatalf("other milestone progress = %+v, want 0 of 1 done", otherProgress)
	}

	otherReport, err := database.PeriodReport("user-other", "2026-01-01", "2026-01-07")
	if err != nil {
		t.Fatalf("other period report: %v", err)
	}
	if len(otherReport.Milestones) != 0 {
		t.Fatalf("other user milestone progress = %+v, want none", otherReport.Milestones)
	}
}

func TestCurrentWeekRangeUsesTheUsersSettings(t *testing.T) {
	database := newStore(t)
	userID := "user-report"
	reportFixture(t, database, userID)

	// 22:30 UTC on Sunday is already Monday in Amsterdam.
	from, to, err := database.CurrentWeekRange(userID, time.Date(2026, 10, 18, 22, 30, 0, 0, time.UTC))
	if err != nil {
		t.Fatalf("current week: %v", err)
	}
	if from != "2026-10-19" || to != "2026-10-25" {
		t.Fatalf("week = %s..%s, want the Amsterdam week 19..25 October", from, to)
	}

	// A Sunday week start moves the same instant to the week beginning 18
	// October.
	settings := domain.DefaultSettings(userID)
	settings.Timezone = "Europe/Amsterdam"
	settings.WeekStart = 7
	if err := database.SaveSettings(settings); err != nil {
		t.Fatalf("save settings: %v", err)
	}
	from, to, err = database.CurrentWeekRange(userID, time.Date(2026, 10, 18, 22, 30, 0, 0, time.UTC))
	if err != nil {
		t.Fatalf("current week: %v", err)
	}
	if from != "2026-10-18" || to != "2026-10-24" {
		t.Fatalf("week = %s..%s, want the Sunday-started week 18..24 October", from, to)
	}
}

func TestPeriodReportRejectsInvalidDates(t *testing.T) {
	database := newStore(t)
	_, err := database.PeriodReport("user-report", "2026-10-19", "")
	if err == nil {
		t.Fatal("missing end date did not fail")
	}
	var validation domain.ValidationError
	if !errors.As(err, &validation) || validation.Field != "toDate" {
		t.Fatalf("error = %v, want a toDate validation error", err)
	}
}
