package domain_test

import (
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func reportCategory(userID, id, name string, role domain.CategoryRole) domain.Category {
	return domain.Category{
		ID:     id,
		UserID: userID,
		Name:   name,
		Role:   role,
	}
}

func reportSubcategory(userID, id, categoryID, name string) domain.Subcategory {
	return domain.Subcategory{
		ID:         id,
		UserID:     userID,
		CategoryID: categoryID,
		Name:       name,
		Status:     domain.SubcategoryActive,
	}
}

func reportEntry(userID, categoryID, subcategoryID string, start time.Time, minutes int, person string) domain.WorkEntry {
	return domain.WorkEntry{
		ID:            domain.NewID(),
		UserID:        userID,
		CategoryID:    categoryID,
		SubcategoryID: subcategoryID,
		Description:   "Work",
		StartedAt:     start,
		EndedAt:       start.Add(time.Duration(minutes) * time.Minute),
		Minutes:       minutes,
		Person:        person,
		Source:        domain.EntrySourceManual,
	}
}

func TestBuildPeriodReportAggregatesThePeriod(t *testing.T) {
	const userID = "user-report"
	categories := []domain.Category{
		reportCategory(userID, "cat-init", "Initiatives", domain.CategoryRoleInitiative),
		reportCategory(userID, "cat-support", "Support", domain.CategoryRoleSupport),
		reportCategory(userID, "cat-other", "Other", domain.CategoryRoleOther),
	}
	subcategories := []domain.Subcategory{
		reportSubcategory(userID, "sub-billing", "cat-init", "Billing migration"),
		reportSubcategory(userID, "sub-unblock", "cat-support", "Unblock"),
		reportSubcategory(userID, "sub-meetings", "cat-other", "Meetings"),
	}
	monday := time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC)
	entries := []domain.WorkEntry{
		reportEntry(userID, "cat-init", "sub-billing", monday, 60, ""),
		reportEntry(userID, "cat-init", "sub-billing", monday.Add(time.Hour), 30, ""),
		reportEntry(userID, "cat-support", "sub-unblock", monday.Add(2*time.Hour), 30, "Priya"),
		reportEntry(userID, "cat-support", "sub-unblock", monday.Add(3*time.Hour), 20, "priya"),
		reportEntry(userID, "cat-other", "sub-meetings", monday.Add(4*time.Hour), 45, ""),
	}
	notes := []domain.Note{
		{ID: "note-day", UserID: userID, Date: "2026-10-20", Text: "Shipped the backfill", CreatedAt: monday.Add(6 * time.Hour)},
		{ID: "note-untouched", UserID: userID, Date: "2026-10-21", Text: "Outside the period", CreatedAt: monday.Add(7 * time.Hour)},
		{ID: "note-project", UserID: userID, SubcategoryID: "sub-billing", Text: "Decision recorded", CreatedAt: monday.Add(8 * time.Hour)},
		// A note may carry both; either match includes it.
		{ID: "note-both", UserID: userID, Date: "2026-10-21", SubcategoryID: "sub-billing", Text: "Dated project note", CreatedAt: monday.Add(9 * time.Hour)},
	}

	report, err := domain.BuildPeriodReport(
		"2026-10-19",
		"2026-10-20",
		time.UTC,
		int(time.Monday),
		entries,
		categories,
		subcategories,
		notes,
	)
	if err != nil {
		t.Fatalf("build report: %v", err)
	}

	if report.FromDate != "2026-10-19" || report.ToDate != "2026-10-20" {
		t.Fatalf("period = %s..%s, want the requested dates", report.FromDate, report.ToDate)
	}
	if report.TotalMinutes != 185 || report.EntryCount != 5 {
		t.Fatalf("totals = %dm across %d entries, want 185m across 5", report.TotalMinutes, report.EntryCount)
	}

	if got := categoryTotals(report.Categories); got != "Initiatives=90,Support=50,Other=45" {
		t.Fatalf("categories = %s, want Initiatives=90,Support=50,Other=45", got)
	}
	if got := subcategoryTotals(report.Subcategories); got != "Billing migration=90,Unblock=50,Meetings=45" {
		t.Fatalf("subcategories = %s, want Billing migration=90,Unblock=50,Meetings=45", got)
	}
	if got := supportPeople(report.SupportPeople); got != "Priya=50/2" {
		t.Fatalf("support people = %s, want Priya=50/2 (case-insensitive grouping)", got)
	}
	if got := supportModes(report.SupportModes); got != "Unblock=50/2" {
		t.Fatalf("support modes = %s, want Unblock=50/2", got)
	}

	if len(report.Weeks) != 1 {
		t.Fatalf("weeks = %d, want one week", len(report.Weeks))
	}
	week := report.Weeks[0]
	if week.WeekStartDate != "2026-10-19" || week.Minutes != 185 || week.TopCategoryName != "Initiatives" {
		t.Fatalf("week = %+v, want 2026-10-19 with 185m topped by Initiatives", week)
	}

	// Day notes in the period and notes on a project worked in the period are
	// context; an untouched day and an untouched project are not.
	if got := noteIDs(report.Notes); got != "note-both,note-project,note-day" {
		t.Fatalf("notes = %s, want the dated project note, project note and day note", got)
	}
}

func TestBuildPeriodReportReportsLastActivityPerSubcategory(t *testing.T) {
	const userID = "user-report"
	categories := []domain.Category{
		reportCategory(userID, "cat-init", "Initiatives", domain.CategoryRoleInitiative),
	}
	subcategories := []domain.Subcategory{
		reportSubcategory(userID, "sub-billing", "cat-init", "Billing migration"),
		reportSubcategory(userID, "sub-platform", "cat-init", "Platform hardening"),
	}

	described := func(entry domain.WorkEntry, description string) domain.WorkEntry {
		entry.Description = description
		return entry
	}
	day := func(dayOfMonth, hour int) time.Time {
		return time.Date(2026, 10, dayOfMonth, hour, 0, 0, 0, time.UTC)
	}

	entries := []domain.WorkEntry{
		described(reportEntry(userID, "cat-init", "sub-billing", day(19, 9), 30, ""), "Backfill skeleton"),
		described(reportEntry(userID, "cat-init", "sub-billing", day(20, 9), 30, ""), "Migration plan"),
		// An earlier entry on the latest day must not replace the later one.
		described(reportEntry(userID, "cat-init", "sub-billing", day(20, 8), 30, ""), "Stand-up"),
		described(reportEntry(userID, "cat-init", "sub-platform", day(19, 11), 30, ""), "Dependency spike"),
	}

	report, err := domain.BuildPeriodReport(
		"2026-10-19",
		"2026-10-20",
		time.UTC,
		int(time.Monday),
		entries,
		categories,
		subcategories,
		nil,
	)
	if err != nil {
		t.Fatalf("build report: %v", err)
	}

	lastActivity := make(map[string]string, len(report.Subcategories))
	for _, total := range report.Subcategories {
		lastActivity[total.SubcategoryID] = total.LastActivityDate + "/" + total.LastActivityDescription
	}
	if got := lastActivity["sub-billing"]; got != "2026-10-20/Migration plan" {
		t.Fatalf("billing last activity = %q, want the latest entry on its last day", got)
	}
	if got := lastActivity["sub-platform"]; got != "2026-10-19/Dependency spike" {
		t.Fatalf("platform last activity = %q, want the only entry", got)
	}
}

func TestBuildPeriodReportReturnsZeroTotalsForAnEmptyPeriod(t *testing.T) {
	report, err := domain.BuildPeriodReport(
		"2026-10-19",
		"2026-10-25",
		time.UTC,
		int(time.Monday),
		nil,
		[]domain.Category{reportCategory("user", "cat-init", "Initiatives", domain.CategoryRoleInitiative)},
		nil,
		nil,
	)
	if err != nil {
		t.Fatalf("build empty report: %v", err)
	}

	if report.TotalMinutes != 0 || report.EntryCount != 0 {
		t.Fatalf("empty totals = %dm/%d entries, want zero", report.TotalMinutes, report.EntryCount)
	}
	if len(report.Categories) != 0 || len(report.Subcategories) != 0 ||
		len(report.SupportPeople) != 0 || len(report.SupportModes) != 0 {
		t.Fatalf("empty period returned allocations: %+v", report)
	}
	if len(report.Weeks) != 1 || report.Weeks[0].Minutes != 0 || report.Weeks[0].TopCategoryID != "" {
		t.Fatalf("weeks = %+v, want one zeroed week", report.Weeks)
	}
}

func TestBuildPeriodReportUsesTheUsersLocalWeeks(t *testing.T) {
	const userID = "user-report"
	categories := []domain.Category{
		reportCategory(userID, "cat-init", "Initiatives", domain.CategoryRoleInitiative),
	}

	// Sunday 23:30 UTC is Monday 01:30 in Amsterdam, so the entry belongs to
	// the week starting Monday 19 October, not the UTC week before it.
	amsterdam, err := time.LoadLocation("Europe/Amsterdam")
	if err != nil {
		t.Fatalf("load location: %v", err)
	}
	entry := reportEntry(userID, "cat-init", "", time.Date(2026, 10, 18, 23, 30, 0, 0, time.UTC), 30, "")

	report, err := domain.BuildPeriodReport(
		"2026-10-19",
		"2026-10-19",
		amsterdam,
		int(time.Monday),
		[]domain.WorkEntry{entry},
		categories,
		nil,
		nil,
	)
	if err != nil {
		t.Fatalf("build report: %v", err)
	}

	if len(report.Weeks) != 1 || report.Weeks[0].WeekStartDate != "2026-10-19" {
		t.Fatalf("weeks = %+v, want the Amsterdam week starting 2026-10-19", report.Weeks)
	}
}

func TestBuildPeriodReportGroupsByTheStoredLocalDate(t *testing.T) {
	const userID = "user-report"
	categories := []domain.Category{
		reportCategory(userID, "cat-init", "Initiatives", domain.CategoryRoleInitiative),
	}

	// The write-time timezone put this entry on 20 October even though its
	// instant is still 18 October in UTC.
	storedDay := reportEntry(userID, "cat-init", "", time.Date(2026, 10, 18, 23, 30, 0, 0, time.UTC), 30, "")
	storedDay.LocalDate = "2026-10-20"
	// The reverse: an instant inside the period whose stored day is outside.
	outside := reportEntry(userID, "cat-init", "", time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC), 45, "")
	outside.LocalDate = "2026-10-21"

	report, err := domain.BuildPeriodReport(
		"2026-10-20",
		"2026-10-20",
		time.UTC,
		int(time.Monday),
		[]domain.WorkEntry{storedDay, outside},
		categories,
		nil,
		nil,
	)
	if err != nil {
		t.Fatalf("build report: %v", err)
	}

	if report.TotalMinutes != 30 || report.EntryCount != 1 {
		t.Fatalf("report totals = %dm/%d, want only the entry stored on 20 October", report.TotalMinutes, report.EntryCount)
	}
	if len(report.Weeks) != 1 || report.Weeks[0].WeekStartDate != "2026-10-19" {
		t.Fatalf("weeks = %+v, want the week of the stored day", report.Weeks)
	}
}

func TestBuildPeriodReportRejectsInvalidPeriods(t *testing.T) {
	cases := []struct {
		name     string
		from, to string
		field    string
	}{
		{name: "missing start", from: "", to: "2026-10-20", field: "fromDate"},
		{name: "missing end", from: "2026-10-19", to: "", field: "toDate"},
		{name: "malformed start", from: "19-10-2026", to: "2026-10-20", field: "fromDate"},
		{name: "reversed period", from: "2026-10-20", to: "2026-10-19", field: "toDate"},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := domain.BuildPeriodReport(
				testCase.from, testCase.to, time.UTC, int(time.Monday), nil, nil, nil, nil,
			)
			validation, ok := err.(domain.ValidationError)
			if !ok {
				t.Fatalf("error = %v, want a validation error", err)
			}
			if validation.Field != testCase.field {
				t.Fatalf("field = %q, want %q", validation.Field, testCase.field)
			}
		})
	}
}

func categoryTotals(totals []domain.CategoryTotal) string {
	result := ""
	for index, total := range totals {
		if index > 0 {
			result += ","
		}
		result += total.Name + "=" + strconv.Itoa(total.Minutes)
	}
	return result
}

func subcategoryTotals(totals []domain.SubcategoryTotal) string {
	result := ""
	for index, total := range totals {
		if index > 0 {
			result += ","
		}
		result += total.Name + "=" + strconv.Itoa(total.Minutes)
	}
	return result
}

func supportPeople(totals []domain.SupportPersonTotal) string {
	result := ""
	for index, total := range totals {
		if index > 0 {
			result += ","
		}
		result += total.Person + "=" + strconv.Itoa(total.Minutes) + "/" + strconv.Itoa(total.Interactions)
	}
	return result
}

func supportModes(totals []domain.SupportModeTotal) string {
	result := ""
	for index, total := range totals {
		if index > 0 {
			result += ","
		}
		result += total.Name + "=" + strconv.Itoa(total.Minutes) + "/" + strconv.Itoa(total.Interactions)
	}
	return result
}

func noteIDs(notes []domain.Note) string {
	ids := make([]string, 0, len(notes))
	for _, note := range notes {
		ids = append(ids, note.ID)
	}
	return strings.Join(ids, ",")
}

func TestBuildMilestoneProgressCountsDonePerProject(t *testing.T) {
	milestones := []domain.Milestone{
		{ID: "m1", SubcategoryID: "sub-billing", Title: "Plan", Done: true},
		{ID: "m2", SubcategoryID: "sub-billing", Title: "Ship"},
		{ID: "m3", SubcategoryID: "sub-billing", Title: "Verify", DueDate: "2026-11-01"},
		{ID: "m4", SubcategoryID: "sub-spike", Title: "Spike"},
	}

	progress := domain.BuildMilestoneProgress(milestones)
	if len(progress) != 2 {
		t.Fatalf("progress = %+v, want two projects", progress)
	}
	if progress[0].SubcategoryID != "sub-billing" || progress[0].Total != 3 || progress[0].Done != 1 {
		t.Fatalf("billing progress = %+v, want 1 of 3 done", progress[0])
	}
	if progress[1].SubcategoryID != "sub-spike" || progress[1].Total != 1 || progress[1].Done != 0 {
		t.Fatalf("spike progress = %+v, want 0 of 1 done", progress[1])
	}

	if empty := domain.BuildMilestoneProgress(nil); len(empty) != 0 {
		t.Fatalf("empty progress = %+v, want no projects", empty)
	}
}
