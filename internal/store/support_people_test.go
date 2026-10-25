package store_test

import (
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

// saveSupportSeedEntry writes one entry under the given category, forcing a
// stable id so the bucket scan order (and therefore first-seen spelling) is
// deterministic.
func saveSupportSeedEntry(t *testing.T, database interface {
	SaveWorkEntry(domain.WorkEntry) error
}, userID string, category domain.Category, id string, person string) {
	t.Helper()

	start := time.Date(2026, 10, 23, 9, 0, 0, 0, time.UTC)
	entry := testWorkEntry(userID, category, "", start, "Support "+person)
	entry.ID = id
	entry.Person = person
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save support entry %q: %v", person, err)
	}
}

func seededCategory(t *testing.T, database interface {
	Categories(string) ([]domain.Category, error)
}, userID string, role domain.CategoryRole) domain.Category {
	t.Helper()

	categories, err := database.Categories(userID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	for _, category := range categories {
		if category.Role == role {
			return category
		}
	}
	t.Fatalf("no category with role %q", role)
	return domain.Category{}
}

func TestEnsureSupportPeopleSeedsOnceFromSupportEntries(t *testing.T) {
	database := newStore(t)
	user := newUser("roster@example.com")
	if err := database.CreateUser(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	support := seededCategory(t, database, user.ID, domain.CategoryRoleSupport)
	initiative := seededCategory(t, database, user.ID, domain.CategoryRoleInitiative)
	saveSupportSeedEntry(t, database, user.ID, support, "00000000-0000-7000-8000-000000000001", " Priya ")
	saveSupportSeedEntry(t, database, user.ID, support, "00000000-0000-7000-8000-000000000002", "priya")
	saveSupportSeedEntry(t, database, user.ID, support, "00000000-0000-7000-8000-000000000003", "Sam")
	// A person on a non-support entry is never part of the roster.
	saveSupportSeedEntry(t, database, user.ID, initiative, "00000000-0000-7000-8000-000000000004", "Mallory")

	seeded, err := database.EnsureSupportPeople(user.ID)
	if err != nil {
		t.Fatalf("ensure support people: %v", err)
	}
	want := []string{"Priya", "Sam"}
	if len(seeded.SupportPeople) != len(want) ||
		seeded.SupportPeople[0] != want[0] ||
		seeded.SupportPeople[1] != want[1] {
		t.Fatalf("support people = %#v, want %#v", seeded.SupportPeople, want)
	}
	if !seeded.SupportPeopleSeeded {
		t.Fatal("seeded marker = false, want true")
	}

	stored, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	if len(stored.SupportPeople) != len(want) || !stored.SupportPeopleSeeded {
		t.Fatalf("stored settings = %+v, want roster %#v and seeded marker", stored, want)
	}
}

func TestEnsureSupportPeoplePreservesDeliberatelyClearedSettings(t *testing.T) {
	database := newStore(t)
	user := newUser("cleared-settings@example.com")
	if err := database.CreateUser(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	// Every omitempty field is absent once cleared, so decoding over the
	// defaults would silently resurrect it before the record is written back.
	settings := domain.DefaultSettings(user.ID)
	settings.AIBaseURL = ""
	settings.AIModel = ""
	settings.BackupDirectory = ""
	settings.JournalStartDate = ""
	settings.Theme = domain.ThemeDark
	settings.DailyTargetMinutes = 123
	if err := database.SaveSettings(settings); err != nil {
		t.Fatalf("save cleared settings: %v", err)
	}

	support := seededCategory(t, database, user.ID, domain.CategoryRoleSupport)
	saveSupportSeedEntry(t, database, user.ID, support, "00000000-0000-7000-8000-000000000001", "Priya")

	got, err := database.EnsureSupportPeople(user.ID)
	if err != nil {
		t.Fatalf("ensure support people: %v", err)
	}
	if got.AIBaseURL != "" || got.AIModel != "" || got.BackupDirectory != "" || got.JournalStartDate != "" {
		t.Fatalf("cleared settings were resurrected: %+v", got)
	}
	if got.Theme != domain.ThemeDark || got.DailyTargetMinutes != 123 {
		t.Fatalf("stored non-empty settings changed: %+v", got)
	}
	if !got.SupportPeopleSeeded {
		t.Fatal("seeded marker = false, want true")
	}
	if len(got.SupportPeople) != 1 || got.SupportPeople[0] != "Priya" {
		t.Fatalf("support people = %#v, want [Priya]", got.SupportPeople)
	}

	stored, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	if stored.AIBaseURL != "" || stored.AIModel != "" || stored.BackupDirectory != "" || stored.JournalStartDate != "" {
		t.Fatalf("cleared settings were written back: %+v", stored)
	}
	if !stored.SupportPeopleSeeded {
		t.Fatal("stored seeded marker = false, want true")
	}
	if len(stored.SupportPeople) != 1 || stored.SupportPeople[0] != "Priya" {
		t.Fatalf("stored support people = %#v, want [Priya]", stored.SupportPeople)
	}
}

func TestEnsureSupportPeopleDoesNotReseedADeliberatelyEmptyRoster(t *testing.T) {
	database := newStore(t)
	user := newUser("empty-roster@example.com")
	if err := database.CreateUser(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	support := seededCategory(t, database, user.ID, domain.CategoryRoleSupport)
	saveSupportSeedEntry(t, database, user.ID, support, "00000000-0000-7000-8000-000000000001", "Priya")
	if _, err := database.EnsureSupportPeople(user.ID); err != nil {
		t.Fatalf("ensure support people: %v", err)
	}

	stored, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	stored.SupportPeople = nil
	if err := database.SaveSettings(stored); err != nil {
		t.Fatalf("save emptied roster: %v", err)
	}

	// A later support entry must not resurrect a roster the user cleared.
	saveSupportSeedEntry(t, database, user.ID, support, "00000000-0000-7000-8000-000000000002", "Sam")
	again, err := database.EnsureSupportPeople(user.ID)
	if err != nil {
		t.Fatalf("ensure support people again: %v", err)
	}
	if len(again.SupportPeople) != 0 {
		t.Fatalf("support people = %#v, want the deliberately emptied roster", again.SupportPeople)
	}
	if !again.SupportPeopleSeeded {
		t.Fatal("seeded marker = false after the user saved settings, want true")
	}
}
