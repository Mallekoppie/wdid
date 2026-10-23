package store_test

import (
	"errors"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func testTaxonomy(t *testing.T, database *store.Store, userID string) (domain.Category, domain.Subcategory) {
	t.Helper()

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}
	return category, subcategory
}

func TestMilestoneRoundTrip(t *testing.T) {
	database := newStore(t)
	userID := "user-milestones"
	_, subcategory := testTaxonomy(t, database, userID)

	now := time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)
	milestone := domain.Milestone{
		ID:            domain.NewID(),
		UserID:        userID,
		SubcategoryID: subcategory.ID,
		Title:         "Ship backfill to staging",
		DueDate:       "2026-10-31",
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	if err := database.SaveMilestone(milestone); err != nil {
		t.Fatalf("save milestone: %v", err)
	}

	stored, err := database.Milestone(userID, milestone.ID)
	if err != nil {
		t.Fatalf("read milestone: %v", err)
	}
	if stored.Title != milestone.Title || stored.DueDate != "2026-10-31" || stored.Done {
		t.Fatalf("stored milestone = %+v, want the saved milestone", stored)
	}

	second := milestone
	second.ID = domain.NewID()
	second.Title = "Backfill production"
	second.DueDate = "2026-11-15"
	if err := database.SaveMilestone(second); err != nil {
		t.Fatalf("save second milestone: %v", err)
	}

	list, err := database.Milestones(userID, subcategory.ID)
	if err != nil {
		t.Fatalf("list milestones: %v", err)
	}
	if len(list) != 2 || list[0].ID != milestone.ID {
		t.Fatalf("milestones = %+v, want the earlier due date first", list)
	}

	if _, err := database.Milestone("user-other", milestone.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("cross-user milestone error = %v, want ErrNotFound", err)
	}

	missing := milestone
	missing.ID = domain.NewID()
	missing.SubcategoryID = "missing-subcategory"
	if err := database.SaveMilestone(missing); !errors.Is(err, store.ErrSubcategoryNotFound) {
		t.Fatalf("missing subcategory error = %v, want ErrSubcategoryNotFound", err)
	}

	if err := database.DeleteMilestone(userID, milestone.ID); err != nil {
		t.Fatalf("delete milestone: %v", err)
	}
	if _, err := database.Milestone(userID, milestone.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("read deleted milestone error = %v, want ErrNotFound", err)
	}
}

func TestNoteRoundTrip(t *testing.T) {
	database := newStore(t)
	userID := "user-notes"
	_, subcategory := testTaxonomy(t, database, userID)

	now := time.Date(2026, 10, 17, 18, 0, 0, 0, time.UTC)
	notes := []domain.Note{
		{
			ID: domain.NewID(), UserID: userID, Date: "2026-10-17",
			SubcategoryID: subcategory.ID, Text: "Track backfill by project.", CreatedAt: now,
		},
		{
			ID: domain.NewID(), UserID: userID, Date: "2026-10-18",
			Text: "A day note.", CreatedAt: now.Add(time.Hour),
		},
		{
			ID: domain.NewID(), UserID: userID, SubcategoryID: subcategory.ID,
			Text: "A project note.", CreatedAt: now.Add(2 * time.Hour),
		},
	}
	for _, note := range notes {
		if err := database.SaveNote(note); err != nil {
			t.Fatalf("save note: %v", err)
		}
	}

	stored, err := database.Note(userID, notes[0].ID)
	if err != nil {
		t.Fatalf("read note: %v", err)
	}
	if stored.Text != notes[0].Text || stored.SubcategoryID != subcategory.ID {
		t.Fatalf("stored note = %+v, want %+v", stored, notes[0])
	}

	byDate, err := database.Notes(userID, store.NoteFilter{Date: "2026-10-18"})
	if err != nil {
		t.Fatalf("notes by date: %v", err)
	}
	if len(byDate) != 1 || byDate[0].ID != notes[1].ID {
		t.Fatalf("notes by date = %+v, want the day note", byDate)
	}

	bySubcategory, err := database.Notes(userID, store.NoteFilter{SubcategoryID: subcategory.ID})
	if err != nil {
		t.Fatalf("notes by subcategory: %v", err)
	}
	if len(bySubcategory) != 2 {
		t.Fatalf("notes by subcategory = %+v, want both project notes", bySubcategory)
	}

	otherNotes, err := database.Notes("user-other", store.NoteFilter{})
	if err != nil {
		t.Fatalf("other user notes: %v", err)
	}
	if len(otherNotes) != 0 {
		t.Fatalf("other user notes = %+v, want none", otherNotes)
	}

	missing := notes[0]
	missing.ID = domain.NewID()
	missing.SubcategoryID = "missing-subcategory"
	if err := database.SaveNote(missing); !errors.Is(err, store.ErrSubcategoryNotFound) {
		t.Fatalf("missing subcategory error = %v, want ErrSubcategoryNotFound", err)
	}

	if err := database.DeleteNote(userID, notes[0].ID); err != nil {
		t.Fatalf("delete note: %v", err)
	}
	if _, err := database.Note(userID, notes[0].ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("read deleted note error = %v, want ErrNotFound", err)
	}
}

func TestCheckInRoundTrip(t *testing.T) {
	database := newStore(t)
	userID := "user-checkins"
	now := time.Date(2026, 10, 2, 17, 0, 0, 0, time.UTC)

	manager := domain.CheckIn{
		ID:          domain.NewID(),
		UserID:      userID,
		Kind:        domain.CheckInKindManager,
		PeriodStart: "2026-07-01",
		PeriodEnd:   "2026-10-02",
		State:       domain.CheckInStateFinal,
		Audience:    domain.AudiencePerformanceReview,
		Totals: domain.CheckInTotals{
			Minutes:         12780,
			ByCategory:      map[string]int{"Initiatives": 2300},
			BySubcategory:   map[string]int{"Billing migration": 2300},
			SupportByPerson: map[string]int{"Priya": 250},
		},
		CreatedAt: now,
		UpdatedAt: now,
	}
	personal := domain.CheckIn{
		ID:          domain.NewID(),
		UserID:      userID,
		Kind:        domain.CheckInKindPersonal,
		PeriodStart: "2026-10-05",
		PeriodEnd:   "2026-10-11",
		State:       domain.CheckInStateDraft,
		CreatedAt:   now.Add(24 * time.Hour),
		UpdatedAt:   now.Add(24 * time.Hour),
	}

	for _, checkIn := range []domain.CheckIn{manager, personal} {
		if err := database.SaveCheckIn(checkIn); err != nil {
			t.Fatalf("save check-in: %v", err)
		}
	}

	stored, err := database.CheckIn(userID, manager.ID)
	if err != nil {
		t.Fatalf("read check-in: %v", err)
	}
	if stored.Kind != domain.CheckInKindManager || stored.State != domain.CheckInStateFinal {
		t.Fatalf("stored check-in = %+v, want final manager", stored)
	}
	if stored.Totals.Minutes != 12780 || stored.Totals.SupportByPerson["Priya"] != 250 {
		t.Fatalf("stored totals = %+v, want the saved snapshot", stored.Totals)
	}

	managers, err := database.CheckIns(userID, domain.CheckInKindManager)
	if err != nil {
		t.Fatalf("list manager check-ins: %v", err)
	}
	if len(managers) != 1 || managers[0].ID != manager.ID {
		t.Fatalf("manager check-ins = %+v, want only the manager check-in", managers)
	}

	all, err := database.CheckIns(userID, "")
	if err != nil {
		t.Fatalf("list all check-ins: %v", err)
	}
	if len(all) != 2 || all[0].ID != personal.ID {
		t.Fatalf("all check-ins = %+v, want newest first", all)
	}

	if _, err := database.CheckIn("user-other", manager.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("cross-user check-in error = %v, want ErrNotFound", err)
	}

	invalid := personal
	invalid.ID = domain.NewID()
	invalid.State = domain.CheckInStateFinal
	if err := database.SaveCheckIn(invalid); err == nil {
		t.Fatal("a final personal review must be rejected")
	}

	if err := database.DeleteCheckIn(userID, personal.ID); err != nil {
		t.Fatalf("delete check-in: %v", err)
	}
	if _, err := database.CheckIn(userID, personal.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("read deleted check-in error = %v, want ErrNotFound", err)
	}
}

func TestSettingsRoundTrip(t *testing.T) {
	database := newStore(t)
	userID := "user-settings"

	settings := domain.DefaultSettings(userID)
	settings.Timezone = "Europe/Amsterdam"
	settings.WeekStart = 7
	settings.DailyTargetMinutes = 400
	settings.ReviewCadence = domain.ReviewCadenceWeekly
	settings.Theme = domain.ThemeDark
	settings.Density = domain.DensityCompact
	settings.JournalStartDate = "2026-01-05"
	settings.UpdatedAt = time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)

	if err := database.SaveSettings(settings); err != nil {
		t.Fatalf("save settings: %v", err)
	}

	stored, err := database.Settings(userID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	if stored.Timezone != "Europe/Amsterdam" || stored.WeekStart != 7 || stored.DailyTargetMinutes != 400 {
		t.Fatalf("stored settings = %+v, want the saved time preferences", stored)
	}
	if stored.ReviewCadence != domain.ReviewCadenceWeekly || stored.Theme != domain.ThemeDark || stored.Density != domain.DensityCompact {
		t.Fatalf("stored settings = %+v, want the saved appearance preferences", stored)
	}

	if _, err := database.Settings("user-other"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("cross-user settings error = %v, want ErrNotFound", err)
	}

	invalid := settings
	invalid.UserID = "user-invalid"
	invalid.Timezone = "Mars/Olympus"
	if err := database.SaveSettings(invalid); err == nil {
		t.Fatal("an unknown timezone must be rejected")
	}
}

func TestFinalManagerCheckInIsReadOnly(t *testing.T) {
	database := newStore(t)
	userID := "user-final"
	now := time.Date(2026, 10, 2, 17, 0, 0, 0, time.UTC)

	checkIn := domain.CheckIn{
		ID:          domain.NewID(),
		UserID:      userID,
		Kind:        domain.CheckInKindManager,
		PeriodStart: "2026-07-01",
		PeriodEnd:   "2026-10-02",
		State:       domain.CheckInStateFinal,
		FocusNotes:  "Final notes",
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if err := database.SaveCheckIn(checkIn); err != nil {
		t.Fatalf("save final check-in: %v", err)
	}

	edited := checkIn
	edited.FocusNotes = "Rewritten after final"
	edited.UpdatedAt = now.Add(time.Hour)
	if err := database.SaveCheckIn(edited); !errors.Is(err, store.ErrFinalCheckInReadOnly) {
		t.Fatalf("edit final check-in error = %v, want ErrFinalCheckInReadOnly", err)
	}
	if err := database.DeleteCheckIn(userID, checkIn.ID); !errors.Is(err, store.ErrFinalCheckInReadOnly) {
		t.Fatalf("delete final check-in error = %v, want ErrFinalCheckInReadOnly", err)
	}

	stored, err := database.CheckIn(userID, checkIn.ID)
	if err != nil {
		t.Fatalf("read final check-in: %v", err)
	}
	if stored.FocusNotes != "Final notes" {
		t.Fatalf("focus notes = %q, want the final record unchanged", stored.FocusNotes)
	}

	// Drafts remain editable and deletable.
	draft := checkIn
	draft.ID = domain.NewID()
	draft.State = domain.CheckInStateDraft
	draft.FocusNotes = "Draft notes"
	if err := database.SaveCheckIn(draft); err != nil {
		t.Fatalf("save draft: %v", err)
	}
	draft.FocusNotes = "Updated draft"
	if err := database.SaveCheckIn(draft); err != nil {
		t.Fatalf("edit draft: %v", err)
	}
	if err := database.DeleteCheckIn(userID, draft.ID); err != nil {
		t.Fatalf("delete draft: %v", err)
	}
}
