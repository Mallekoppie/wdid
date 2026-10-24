package store_test

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestExportSnapshotMatchesTheListingReads(t *testing.T) {
	database := newStore(t)
	userID := "user-export"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	category.SortOrder = 2
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	other := testCategory(userID, "Other", domain.CategoryRoleOther)
	other.SortOrder = 1
	if err := database.SaveCategory(other); err != nil {
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

	inside := testWorkEntry(userID, category, subcategory.ID, time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC), "Inside")
	if err := database.SaveWorkEntry(inside); err != nil {
		t.Fatalf("save inside entry: %v", err)
	}
	outside := testWorkEntry(userID, category, subcategory.ID, time.Date(2026, 9, 20, 9, 0, 0, 0, time.UTC), "Outside")
	if err := database.SaveWorkEntry(outside); err != nil {
		t.Fatalf("save outside entry: %v", err)
	}

	created := time.Date(2026, 10, 1, 8, 0, 0, 0, time.UTC)
	milestone := domain.Milestone{
		ID: domain.NewID(), UserID: userID, SubcategoryID: subcategory.ID,
		Title: "Ship backfill", DueDate: "2026-10-31", CreatedAt: created, UpdatedAt: created,
	}
	if err := database.SaveMilestone(milestone); err != nil {
		t.Fatalf("save milestone: %v", err)
	}

	scoped := domain.CheckIn{
		ID: domain.NewID(), UserID: userID, Kind: domain.CheckInKindManager,
		State: domain.CheckInStateDraft, PeriodStart: "2026-10-19", PeriodEnd: "2026-10-25",
		FocusNotes: "Focus", CreatedAt: created, UpdatedAt: created,
	}
	if err := database.SaveCheckIn(scoped); err != nil {
		t.Fatalf("save check-in: %v", err)
	}

	snapshot, err := database.ExportSnapshot(userID, "2026-10-19", "2026-10-25", "")
	if err != nil {
		t.Fatalf("export snapshot: %v", err)
	}

	if snapshot.Report.FromDate != "2026-10-19" || snapshot.Report.ToDate != "2026-10-25" {
		t.Fatalf("report period = %s..%s", snapshot.Report.FromDate, snapshot.Report.ToDate)
	}
	if len(snapshot.Entries) != 1 || snapshot.Entries[0].ID != inside.ID {
		t.Fatalf("entries = %+v, want only the in-period entry", snapshot.Entries)
	}
	if snapshot.Report.EntryCount != 1 || snapshot.Report.TotalMinutes != 42 {
		t.Fatalf("report totals = %d entries, %d minutes", snapshot.Report.EntryCount, snapshot.Report.TotalMinutes)
	}
	if len(snapshot.Categories) != 2 || snapshot.Categories[0].ID != other.ID {
		t.Fatalf("categories = %+v, want sort order then name", snapshot.Categories)
	}
	if len(snapshot.Subcategories) != 1 || snapshot.Subcategories[0].ID != subcategory.ID {
		t.Fatalf("subcategories = %+v", snapshot.Subcategories)
	}
	if len(snapshot.Milestones) != 1 || snapshot.Milestones[0].ID != milestone.ID {
		t.Fatalf("milestones = %+v", snapshot.Milestones)
	}
	if len(snapshot.CheckIns) != 1 || snapshot.CheckIns[0].ID != scoped.ID {
		t.Fatalf("check-ins = %+v", snapshot.CheckIns)
	}
	if snapshot.Settings.Timezone != "Europe/Amsterdam" {
		t.Fatalf("settings timezone = %q", snapshot.Settings.Timezone)
	}

	// The combined snapshot must equal what the separate listing reads return.
	report, err := database.PeriodReport(userID, "2026-10-19", "2026-10-25")
	if err != nil {
		t.Fatalf("period report: %v", err)
	}
	if fmt.Sprintf("%+v", report) != fmt.Sprintf("%+v", snapshot.Report) {
		t.Fatalf("snapshot report differs from the standalone report:\n%+v\n%+v", snapshot.Report, report)
	}
	entries, err := database.WorkEntriesInDateRange(userID, "2026-10-19", "2026-10-25")
	if err != nil {
		t.Fatalf("entries in range: %v", err)
	}
	if fmt.Sprintf("%+v", entries) != fmt.Sprintf("%+v", snapshot.Entries) {
		t.Fatalf("snapshot entries differ from the standalone listing:\n%+v\n%+v", snapshot.Entries, entries)
	}
}

func TestExportSnapshotScopesToTheCheckIn(t *testing.T) {
	database := newStore(t)
	userID := "user-export-scoped"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}

	entry := testWorkEntry(userID, category, subcategory.ID, time.Date(2026, 10, 5, 9, 0, 0, 0, time.UTC), "In check-in period")
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save entry: %v", err)
	}
	outside := testWorkEntry(userID, category, subcategory.ID, time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC), "Outside")
	if err := database.SaveWorkEntry(outside); err != nil {
		t.Fatalf("save outside entry: %v", err)
	}

	created := time.Date(2026, 10, 6, 8, 0, 0, 0, time.UTC)
	checkIn := domain.CheckIn{
		ID: domain.NewID(), UserID: userID, Kind: domain.CheckInKindManager,
		State: domain.CheckInStateDraft, PeriodStart: "2026-10-01", PeriodEnd: "2026-10-10",
		FocusNotes: "Scoped focus", CreatedAt: created, UpdatedAt: created,
	}
	if err := database.SaveCheckIn(checkIn); err != nil {
		t.Fatalf("save check-in: %v", err)
	}

	// The caller's dates are ignored in favour of the stored check-in period.
	snapshot, err := database.ExportSnapshot(userID, "2026-10-19", "2026-10-25", checkIn.ID)
	if err != nil {
		t.Fatalf("export snapshot: %v", err)
	}
	if snapshot.Report.FromDate != "2026-10-01" || snapshot.Report.ToDate != "2026-10-10" {
		t.Fatalf("report period = %s..%s, want the check-in period", snapshot.Report.FromDate, snapshot.Report.ToDate)
	}
	if len(snapshot.Entries) != 1 || snapshot.Entries[0].ID != entry.ID {
		t.Fatalf("entries = %+v, want the check-in period entry", snapshot.Entries)
	}
	if snapshot.ScopedCheckIn == nil || snapshot.ScopedCheckIn.ID != checkIn.ID {
		t.Fatalf("scoped check-in = %+v", snapshot.ScopedCheckIn)
	}
	if snapshot.ScopedCheckIn.FocusNotes != "Scoped focus" {
		t.Fatalf("scoped focus notes = %q", snapshot.ScopedCheckIn.FocusNotes)
	}
}

// TestExportSnapshotIsConsistentUnderConcurrentWrites pins the whole point of
// the single transaction: the report and its raw rows always describe the same
// instant, even while entries are being written.
func TestExportSnapshotIsConsistentUnderConcurrentWrites(t *testing.T) {
	database := newStore(t)
	userID := "user-export-concurrent"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}

	const writes = 40
	var writer sync.WaitGroup
	writer.Add(1)
	go func() {
		defer writer.Done()
		for index := 0; index < writes; index++ {
			start := time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC).Add(time.Duration(index) * time.Minute)
			entry := testWorkEntry(userID, category, subcategory.ID, start, fmt.Sprintf("Concurrent %d", index))
			entry.Minutes = 1
			entry.EndedAt = start.Add(time.Minute)
			if err := database.SaveWorkEntry(entry); err != nil {
				t.Errorf("save concurrent entry: %v", err)
				return
			}
		}
	}()

	deadline := time.Now().Add(10 * time.Second)
	reads := 0
	for time.Now().Before(deadline) && reads < 200 {
		snapshot, err := database.ExportSnapshot(userID, "2026-10-19", "2026-10-25", "")
		if err != nil {
			t.Fatalf("export snapshot: %v", err)
		}
		minutes := 0
		seen := make(map[string]struct{}, len(snapshot.Entries))
		for _, entry := range snapshot.Entries {
			if _, ok := seen[entry.ID]; ok {
				t.Fatalf("snapshot duplicated entry %q", entry.ID)
			}
			seen[entry.ID] = struct{}{}
			minutes += entry.Minutes
		}
		if len(snapshot.Entries) != snapshot.Report.EntryCount {
			t.Fatalf("snapshot has %d entries but the report counts %d", len(snapshot.Entries), snapshot.Report.EntryCount)
		}
		if minutes != snapshot.Report.TotalMinutes {
			t.Fatalf("snapshot entries total %d minutes but the report totals %d", minutes, snapshot.Report.TotalMinutes)
		}
		reads++
	}
	writer.Wait()
	if reads == 0 {
		t.Fatal("the consistency loop never ran")
	}
}
