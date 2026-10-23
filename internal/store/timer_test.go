package store_test

import (
	"errors"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func newTimerOwner(t *testing.T) (database *store.Store, userID string, categoryID, subcategoryID string) {
	t.Helper()

	database = newStore(t)
	userID = "user-timer"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}
	return database, userID, category.ID, subcategory.ID
}

func startTestTimer(t *testing.T, database *store.Store, userID, categoryID, subcategoryID string, start time.Time) {
	t.Helper()

	err := database.StartTimer(domain.ActiveTimer{
		UserID:           userID,
		CategoryID:       categoryID,
		SubcategoryID:    subcategoryID,
		Description:      "Backfill script",
		StartedAt:        start,
		SegmentStartedAt: start,
	})
	if err != nil {
		t.Fatalf("start timer: %v", err)
	}
}

func TestTimerLifecycleExcludesPausedTime(t *testing.T) {
	database, userID, categoryID, subcategoryID := newTimerOwner(t)
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	startTestTimer(t, database, userID, categoryID, subcategoryID, start)

	paused, err := database.PauseTimer(userID, start.Add(10*time.Minute))
	if err != nil {
		t.Fatalf("pause timer: %v", err)
	}
	if !paused.Paused() {
		t.Fatal("timer is not paused after PauseTimer")
	}

	// Pausing twice is idempotent; the elapsed total does not move.
	again, err := database.PauseTimer(userID, start.Add(15*time.Minute))
	if err != nil {
		t.Fatalf("pause again: %v", err)
	}
	if got := again.Elapsed(start.Add(60 * time.Minute)); got != 10*time.Minute {
		t.Fatalf("paused elapsed = %v, want 10m", got)
	}

	resumed, err := database.ResumeTimer(userID, start.Add(20*time.Minute))
	if err != nil {
		t.Fatalf("resume timer: %v", err)
	}
	if resumed.Paused() {
		t.Fatal("timer is still paused after ResumeTimer")
	}

	entry, discarded, err := database.StopTimer(userID, start.Add(35*time.Minute), domain.TimerStopSave, 240)
	if err != nil {
		t.Fatalf("stop timer: %v", err)
	}
	if discarded {
		t.Fatal("stop saved nothing")
	}
	if entry.Minutes != 25 {
		t.Fatalf("entry minutes = %d, want 25 (paused 10m excluded)", entry.Minutes)
	}
	if entry.StartedAt != start {
		t.Fatalf("entry start = %v, want %v", entry.StartedAt, start)
	}
	if entry.EndedAt != start.Add(25*time.Minute) {
		t.Fatalf("entry end = %v, want start plus 25m", entry.EndedAt)
	}
	if entry.CategoryID != categoryID || entry.SubcategoryID != subcategoryID {
		t.Fatalf("entry attribution = %s/%s, want %s/%s", entry.CategoryID, entry.SubcategoryID, categoryID, subcategoryID)
	}
	if entry.Source != domain.EntrySourceTimer {
		t.Fatalf("entry source = %q, want timer", entry.Source)
	}
	if entry.Description != "Backfill script" {
		t.Fatalf("entry description = %q", entry.Description)
	}

	if _, active, err := database.ActiveTimer(userID); err != nil || active {
		t.Fatalf("timer still active = %v, err = %v", active, err)
	}
	stored, err := database.WorkEntry(userID, entry.ID)
	if err != nil {
		t.Fatalf("read saved entry: %v", err)
	}
	if stored.Minutes != 25 || stored.LocalDate != "2026-10-18" {
		t.Fatalf("stored entry = %+v, want 25 minutes on the start day", stored)
	}
}

func TestTimerAllowsOneActiveTimerPerUser(t *testing.T) {
	database, userID, categoryID, subcategoryID := newTimerOwner(t)
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	startTestTimer(t, database, userID, categoryID, subcategoryID, start)

	err := database.StartTimer(domain.ActiveTimer{
		UserID:           userID,
		CategoryID:       categoryID,
		StartedAt:        start.Add(time.Minute),
		SegmentStartedAt: start.Add(time.Minute),
	})
	if !errors.Is(err, store.ErrTimerRunning) {
		t.Fatalf("second start error = %v, want ErrTimerRunning", err)
	}

	if _, err := database.PauseTimer("another-user", start); !errors.Is(err, store.ErrTimerNotRunning) {
		t.Fatalf("cross-user pause error = %v, want ErrTimerNotRunning", err)
	}
}

func TestTimerRejectsStopsUnderOneMinuteUnlessDiscarded(t *testing.T) {
	database, userID, categoryID, subcategoryID := newTimerOwner(t)
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	startTestTimer(t, database, userID, categoryID, subcategoryID, start)

	_, _, err := database.StopTimer(userID, start.Add(30*time.Second), domain.TimerStopSave, 240)
	var conflict domain.TimerConflictError
	if !errors.As(err, &conflict) || conflict.Reason != domain.TimerConflictTooShort {
		t.Fatalf("short stop error = %v, want a too-short conflict", err)
	}
	if _, active, _ := database.ActiveTimer(userID); !active {
		t.Fatal("a rejected stop must leave the timer running")
	}

	entry, discarded, err := database.StopTimer(userID, start.Add(30*time.Second), domain.TimerStopDiscard, 240)
	if err != nil {
		t.Fatalf("discard short timer: %v", err)
	}
	if !discarded || entry.ID != "" {
		t.Fatalf("discard returned entry %+v, discarded %v", entry, discarded)
	}
	if _, active, _ := database.ActiveTimer(userID); active {
		t.Fatal("discard must clear the timer")
	}
}

func TestTimerBlockLimitOffersKeepTrimAndDiscard(t *testing.T) {
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)

	t.Run("save above the limit conflicts", func(t *testing.T) {
		database, userID, categoryID, subcategoryID := newTimerOwner(t)
		startTestTimer(t, database, userID, categoryID, subcategoryID, start)

		_, _, err := database.StopTimer(userID, start.Add(5*time.Hour), domain.TimerStopSave, 240)
		var conflict domain.TimerConflictError
		if !errors.As(err, &conflict) || conflict.Reason != domain.TimerConflictBlockLimit {
			t.Fatalf("long stop error = %v, want a block-limit conflict", err)
		}
		if conflict.ElapsedMinutes != 300 || conflict.BlockLimitMinutes != 240 {
			t.Fatalf("conflict = %+v, want 300 over 240", conflict)
		}
		if _, active, _ := database.ActiveTimer(userID); !active {
			t.Fatal("a conflicting stop must leave the timer running")
		}
	})

	t.Run("just past the limit still conflicts", func(t *testing.T) {
		database, userID, categoryID, subcategoryID := newTimerOwner(t)
		startTestTimer(t, database, userID, categoryID, subcategoryID, start)

		_, _, err := database.StopTimer(userID, start.Add(240*time.Minute+30*time.Second), domain.TimerStopSave, 240)
		var conflict domain.TimerConflictError
		if !errors.As(err, &conflict) || conflict.Reason != domain.TimerConflictBlockLimit {
			t.Fatalf("just-over stop error = %v, want a block-limit conflict", err)
		}
	})

	t.Run("keep stores the full length", func(t *testing.T) {
		database, userID, categoryID, subcategoryID := newTimerOwner(t)
		startTestTimer(t, database, userID, categoryID, subcategoryID, start)

		entry, _, err := database.StopTimer(userID, start.Add(5*time.Hour), domain.TimerStopKeep, 240)
		if err != nil {
			t.Fatalf("keep timer: %v", err)
		}
		if entry.Minutes != 300 {
			t.Fatalf("kept minutes = %d, want 300", entry.Minutes)
		}
	})

	t.Run("trim stores the block limit", func(t *testing.T) {
		database, userID, categoryID, subcategoryID := newTimerOwner(t)
		startTestTimer(t, database, userID, categoryID, subcategoryID, start)

		entry, _, err := database.StopTimer(userID, start.Add(5*time.Hour), domain.TimerStopTrim, 240)
		if err != nil {
			t.Fatalf("trim timer: %v", err)
		}
		if entry.Minutes != 240 {
			t.Fatalf("trimmed minutes = %d, want 240", entry.Minutes)
		}
		if entry.EndedAt != start.Add(240*time.Minute) {
			t.Fatalf("trimmed end = %v, want start plus 240m", entry.EndedAt)
		}
	})

	t.Run("discard stores nothing", func(t *testing.T) {
		database, userID, categoryID, subcategoryID := newTimerOwner(t)
		startTestTimer(t, database, userID, categoryID, subcategoryID, start)

		entry, discarded, err := database.StopTimer(userID, start.Add(5*time.Hour), domain.TimerStopDiscard, 240)
		if err != nil {
			t.Fatalf("discard timer: %v", err)
		}
		if !discarded || entry.ID != "" {
			t.Fatalf("discard returned entry %+v, discarded %v", entry, discarded)
		}
		entries, err := database.WorkEntries(userID, store.WorkEntryFilter{})
		if err != nil {
			t.Fatalf("list entries: %v", err)
		}
		if len(entries) != 0 {
			t.Fatalf("entries = %d, want none", len(entries))
		}
	})
}

func TestTimerStopFallsBackToAttributionName(t *testing.T) {
	database, userID, categoryID, subcategoryID := newTimerOwner(t)
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	if err := database.StartTimer(domain.ActiveTimer{
		UserID:           userID,
		CategoryID:       categoryID,
		SubcategoryID:    subcategoryID,
		StartedAt:        start,
		SegmentStartedAt: start,
	}); err != nil {
		t.Fatalf("start timer: %v", err)
	}

	entry, _, err := database.StopTimer(userID, start.Add(30*time.Minute), domain.TimerStopSave, 240)
	if err != nil {
		t.Fatalf("stop timer: %v", err)
	}
	if entry.Description != "Billing migration" {
		t.Fatalf("description = %q, want the subcategory name", entry.Description)
	}
}

func TestTimerStartRequiresPersonForSupportCategory(t *testing.T) {
	database := newStore(t)
	userID := "user-support-timer"
	category := testCategory(userID, "Support", domain.CategoryRoleSupport)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)

	err := database.StartTimer(domain.ActiveTimer{
		UserID:           userID,
		CategoryID:       category.ID,
		StartedAt:        start,
		SegmentStartedAt: start,
	})
	var validation domain.ValidationError
	if !errors.As(err, &validation) || validation.Field != "person" {
		t.Fatalf("start error = %v, want a person field error", err)
	}

	if err := database.StartTimer(domain.ActiveTimer{
		UserID:           userID,
		CategoryID:       category.ID,
		Person:           "Priya",
		StartedAt:        start,
		SegmentStartedAt: start,
	}); err != nil {
		t.Fatalf("start support timer with person: %v", err)
	}

	entry, _, err := database.StopTimer(userID, start.Add(30*time.Minute), domain.TimerStopSave, 240)
	if err != nil {
		t.Fatalf("stop support timer: %v", err)
	}
	if entry.Person != "Priya" {
		t.Fatalf("entry person = %q, want Priya", entry.Person)
	}
}

func TestTimerStartRejectsUnknownAttribution(t *testing.T) {
	database, userID, _, _ := newTimerOwner(t)
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)

	err := database.StartTimer(domain.ActiveTimer{
		UserID:           userID,
		CategoryID:       "missing",
		StartedAt:        start,
		SegmentStartedAt: start,
	})
	if !errors.Is(err, store.ErrCategoryNotFound) {
		t.Fatalf("unknown category error = %v, want ErrCategoryNotFound", err)
	}

	err = database.StartTimer(domain.ActiveTimer{
		UserID:     userID,
		CategoryID: "",
	})
	if err == nil {
		t.Fatal("empty category was accepted")
	}
}
