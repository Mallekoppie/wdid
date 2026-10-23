package store_test

import (
	"errors"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func testWorkEntry(userID string, category domain.Category, subcategory string, start time.Time, description string) domain.WorkEntry {
	return domain.WorkEntry{
		ID:            domain.NewID(),
		UserID:        userID,
		CategoryID:    category.ID,
		SubcategoryID: subcategory,
		Description:   description,
		Outcome:       "Outcome for " + description,
		StartedAt:     start,
		EndedAt:       start.Add(42 * time.Minute),
		Minutes:       42,
		Source:        domain.EntrySourceManual,
		CreatedAt:     start,
		UpdatedAt:     start,
	}
}

func TestWorkEntryRoundTripDerivesLocalDate(t *testing.T) {
	database := newStore(t)
	userID := "user-entries"

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

	// 23:30 UTC is already the next day in Amsterdam.
	start := time.Date(2026, 10, 17, 23, 30, 0, 0, time.UTC)
	entry := testWorkEntry(userID, category, subcategory.ID, start, "Backfill script skeleton")
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save entry: %v", err)
	}

	stored, err := database.WorkEntry(userID, entry.ID)
	if err != nil {
		t.Fatalf("read entry: %v", err)
	}
	if stored.LocalDate != "2026-10-18" {
		t.Fatalf("localDate = %q, want the Amsterdam day 2026-10-18", stored.LocalDate)
	}
	if stored.CategoryID != category.ID || stored.SubcategoryID != subcategory.ID {
		t.Fatalf("stored attribution = %+v, want category and subcategory", stored)
	}
	if stored.Minutes != 42 || stored.DurationMinutes() != 42 {
		t.Fatalf("stored minutes = %d, want 42", stored.Minutes)
	}

	// Changing the start instant re-derives the grouping day on save.
	entry.StartedAt = time.Date(2026, 10, 18, 21, 30, 0, 0, time.UTC)
	entry.EndedAt = entry.StartedAt.Add(42 * time.Minute)
	entry.UpdatedAt = entry.StartedAt
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("resave entry: %v", err)
	}
	stored, err = database.WorkEntry(userID, entry.ID)
	if err != nil {
		t.Fatalf("read resaved entry: %v", err)
	}
	if stored.LocalDate != "2026-10-18" {
		t.Fatalf("localDate after resave = %q, want 2026-10-18", stored.LocalDate)
	}
}

func TestWorkEntryRequiresItsCategoryAndSubcategory(t *testing.T) {
	database := newStore(t)
	userID := "user-entries"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	other := testCategory(userID, "Other", domain.CategoryRoleOther)
	if err := database.SaveCategory(other); err != nil {
		t.Fatalf("save other category: %v", err)
	}
	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}

	start := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC)

	missing := testWorkEntry(userID, category, "", start, "No category")
	missing.CategoryID = "missing-category"
	if err := database.SaveWorkEntry(missing); !errors.Is(err, store.ErrCategoryNotFound) {
		t.Fatalf("missing category error = %v, want ErrCategoryNotFound", err)
	}

	wrongParent := testWorkEntry(userID, other, subcategory.ID, start, "Wrong parent")
	if err := database.SaveWorkEntry(wrongParent); err == nil || err.Error() != "subcategoryId: subcategory must belong to its category" {
		t.Fatalf("wrong parent error = %v, want a subcategoryId validation error", err)
	}

	// Support-role categories require a person.
	support := testCategory(userID, "Support", domain.CategoryRoleSupport)
	if err := database.SaveCategory(support); err != nil {
		t.Fatalf("save support category: %v", err)
	}
	mode := testSubcategory(userID, support.ID, "Review")
	if err := database.SaveSubcategory(mode); err != nil {
		t.Fatalf("save support mode: %v", err)
	}

	supportEntry := testWorkEntry(userID, support, mode.ID, start, "Reviewed the migration plan")
	if err := database.SaveWorkEntry(supportEntry); err == nil || err.Error() != "person: is required for support entries" {
		t.Fatalf("support without person error = %v, want a person validation error", err)
	}

	supportEntry.Person = "Priya"
	if err := database.SaveWorkEntry(supportEntry); err != nil {
		t.Fatalf("save support entry with person: %v", err)
	}
	stored, err := database.WorkEntry(userID, supportEntry.ID)
	if err != nil {
		t.Fatalf("read support entry: %v", err)
	}
	if stored.Person != "Priya" {
		t.Fatalf("person = %q, want Priya", stored.Person)
	}
}

func TestWorkEntryFiltersFollowIndexes(t *testing.T) {
	database := newStore(t)
	userID := "user-filters"

	initiatives := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	support := testCategory(userID, "Support", domain.CategoryRoleSupport)
	for _, category := range []domain.Category{initiatives, support} {
		if err := database.SaveCategory(category); err != nil {
			t.Fatalf("save category: %v", err)
		}
	}

	billing := testSubcategory(userID, initiatives.ID, "Billing migration")
	review := testSubcategory(userID, support.ID, "Review")
	for _, subcategory := range []domain.Subcategory{billing, review} {
		if err := database.SaveSubcategory(subcategory); err != nil {
			t.Fatalf("save subcategory: %v", err)
		}
	}

	dayOne := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC)
	dayTwo := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)

	backfill := testWorkEntry(userID, initiatives, billing.ID, dayOne, "Backfill script skeleton")
	priya := testWorkEntry(userID, support, review.ID, dayTwo, "Reviewed the billing plan")
	priya.Person = "Priya"
	for _, entry := range []domain.WorkEntry{backfill, priya} {
		if err := database.SaveWorkEntry(entry); err != nil {
			t.Fatalf("save entry: %v", err)
		}
	}

	tests := []struct {
		name   string
		filter store.WorkEntryFilter
		wantID string
	}{
		{name: "by day", filter: store.WorkEntryFilter{LocalDate: "2026-10-17"}, wantID: backfill.ID},
		{name: "by category", filter: store.WorkEntryFilter{CategoryID: support.ID}, wantID: priya.ID},
		{name: "by subcategory", filter: store.WorkEntryFilter{SubcategoryID: billing.ID}, wantID: backfill.ID},
		{name: "by person", filter: store.WorkEntryFilter{Person: "Priya"}, wantID: priya.ID},
		{name: "by query", filter: store.WorkEntryFilter{Query: "backfill"}, wantID: backfill.ID},
		{name: "by range", filter: store.WorkEntryFilter{From: dayTwo.Add(-time.Hour), To: dayTwo.Add(time.Hour)}, wantID: priya.ID},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			entries, err := database.WorkEntries(userID, test.filter)
			if err != nil {
				t.Fatalf("list entries: %v", err)
			}
			if len(entries) != 1 || entries[0].ID != test.wantID {
				t.Fatalf("entries = %+v, want %s", entries, test.wantID)
			}
		})
	}

	all, err := database.WorkEntries(userID, store.WorkEntryFilter{})
	if err != nil {
		t.Fatalf("list all entries: %v", err)
	}
	if len(all) != 2 || all[0].ID != priya.ID || all[1].ID != backfill.ID {
		t.Fatalf("all entries = %+v, want newest first", all)
	}

	limited, err := database.WorkEntries(userID, store.WorkEntryFilter{Limit: 1})
	if err != nil {
		t.Fatalf("limited list: %v", err)
	}
	if len(limited) != 1 || limited[0].ID != priya.ID {
		t.Fatalf("limited entries = %+v, want the newest entry", limited)
	}

	// Moving an entry updates its index: the old category and day stop matching.
	backfill.CategoryID = support.ID
	backfill.SubcategoryID = review.ID
	backfill.Person = "Sam"
	backfill.StartedAt = dayTwo
	backfill.EndedAt = dayTwo.Add(42 * time.Minute)
	if err := database.SaveWorkEntry(backfill); err != nil {
		t.Fatalf("move entry: %v", err)
	}

	oldCategory, err := database.WorkEntries(userID, store.WorkEntryFilter{CategoryID: initiatives.ID})
	if err != nil {
		t.Fatalf("old category: %v", err)
	}
	if len(oldCategory) != 0 {
		t.Fatalf("old category entries = %+v, want none after the move", oldCategory)
	}
	oldDay, err := database.WorkEntries(userID, store.WorkEntryFilter{LocalDate: "2026-10-17"})
	if err != nil {
		t.Fatalf("old day: %v", err)
	}
	if len(oldDay) != 0 {
		t.Fatalf("old day entries = %+v, want none after the move", oldDay)
	}
	priyaOnly, err := database.WorkEntries(userID, store.WorkEntryFilter{Person: "Priya"})
	if err != nil {
		t.Fatalf("old person: %v", err)
	}
	if len(priyaOnly) != 1 || priyaOnly[0].ID != priya.ID {
		t.Fatalf("Priya entries = %+v, want only the original support entry", priyaOnly)
	}

	// Deleting removes the entry from the indexes too.
	if err := database.DeleteWorkEntry(userID, priya.ID); err != nil {
		t.Fatalf("delete entry: %v", err)
	}
	afterDelete, err := database.WorkEntries(userID, store.WorkEntryFilter{Person: "Priya"})
	if err != nil {
		t.Fatalf("person after delete: %v", err)
	}
	if len(afterDelete) != 0 {
		t.Fatalf("entries after delete = %+v, want none", afterDelete)
	}

	// Another account cannot read the entry by id.
	if _, err := database.WorkEntry("user-other", backfill.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("cross-user entry error = %v, want ErrNotFound", err)
	}
}

func TestReferencedTaxonomyCanBeArchivedButNotDeleted(t *testing.T) {
	database := newStore(t)
	userID := "user-archive"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}
	entry := testWorkEntry(userID, category, subcategory.ID, time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC), "Backfill")
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save entry: %v", err)
	}

	if err := database.DeleteSubcategory(userID, subcategory.ID); !errors.Is(err, store.ErrSubcategoryInUse) {
		t.Fatalf("delete referenced subcategory error = %v, want ErrSubcategoryInUse", err)
	}
	if err := database.DeleteCategory(userID, category.ID); !errors.Is(err, store.ErrCategoryInUse) {
		t.Fatalf("delete referenced category error = %v, want ErrCategoryInUse", err)
	}

	category.Archived = true
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("archive category: %v", err)
	}
	subcategory.Archived = true
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("archive subcategory: %v", err)
	}
	storedCategory, err := database.Category(userID, category.ID)
	if err != nil {
		t.Fatalf("read archived category: %v", err)
	}
	if !storedCategory.Archived {
		t.Fatal("category should be archived")
	}
	storedSubcategory, err := database.Subcategory(userID, subcategory.ID)
	if err != nil {
		t.Fatalf("read archived subcategory: %v", err)
	}
	if !storedSubcategory.Archived {
		t.Fatal("subcategory should be archived")
	}

	// Once nothing references them, both can be deleted.
	if err := database.DeleteWorkEntry(userID, entry.ID); err != nil {
		t.Fatalf("delete entry: %v", err)
	}
	if err := database.DeleteSubcategory(userID, subcategory.ID); err != nil {
		t.Fatalf("delete unused subcategory: %v", err)
	}
	if err := database.DeleteCategory(userID, category.ID); err != nil {
		t.Fatalf("delete unused category: %v", err)
	}
	if _, err := database.Category(userID, category.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("deleted category read error = %v, want ErrNotFound", err)
	}
}

func TestWorkEntryDerivesMinutesFromItsTimestamps(t *testing.T) {
	database := newStore(t)
	userID := "user-minutes"
	category, subcategory := testTaxonomy(t, database, userID)

	start := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC)
	entry := testWorkEntry(userID, category, subcategory.ID, start, "Backfill")
	entry.Minutes = 0

	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save entry: %v", err)
	}
	stored, err := database.WorkEntry(userID, entry.ID)
	if err != nil {
		t.Fatalf("read entry: %v", err)
	}
	if stored.Minutes != 42 {
		t.Fatalf("minutes = %d, want the 42 minute timestamp span", stored.Minutes)
	}
}

func TestSavedEntryTimestampsAreStoredInUTC(t *testing.T) {
	database := newStore(t)
	userID := "user-entry-utc"
	category, subcategory := testTaxonomy(t, database, userID)

	zone := time.FixedZone("CEST", 2*60*60)
	start := time.Date(2026, 10, 17, 11, 0, 0, 0, zone)
	entry := testWorkEntry(userID, category, subcategory.ID, start, "Backfill")

	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save entry: %v", err)
	}
	stored, err := database.WorkEntry(userID, entry.ID)
	if err != nil {
		t.Fatalf("read entry: %v", err)
	}
	if stored.StartedAt.Location() != time.UTC || !stored.StartedAt.Equal(start) {
		t.Fatalf("startedAt = %v, want the same instant in UTC", stored.StartedAt)
	}
	if stored.CreatedAt.Location() != time.UTC {
		t.Fatalf("createdAt = %v, want UTC", stored.CreatedAt)
	}
}
