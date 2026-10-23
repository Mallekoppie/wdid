package store_test

import (
	"testing"
	"time"

	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func assertSeededTaxonomy(t *testing.T, database interface {
	Categories(string) ([]domain.Category, error)
	Subcategories(string, string) ([]domain.Subcategory, error)
	Settings(string) (domain.Settings, error)
}, userID string) {
	t.Helper()

	categories, err := database.Categories(userID)
	if err != nil {
		t.Fatalf("list seeded categories: %v", err)
	}
	if len(categories) != 3 {
		t.Fatalf("seeded categories = %+v, want Initiatives, Support and Other", categories)
	}

	want := []struct {
		name          string
		role          domain.CategoryRole
		subcategories []string
	}{
		{name: "Initiatives", role: domain.CategoryRoleInitiative},
		{name: "Support", role: domain.CategoryRoleSupport, subcategories: []string{"Review", "Pair", "Unblock", "Mentor", "Incident", "Other"}},
		{name: "Other", role: domain.CategoryRoleOther, subcategories: []string{"Meetings", "Admin", "Learning", "Unplanned"}},
	}

	for i, expected := range want {
		category := categories[i]
		if category.Name != expected.name || category.Role != expected.role {
			t.Fatalf("category %d = %+v, want %s (%s)", i, category, expected.name, expected.role)
		}
		if category.UserID != userID {
			t.Fatalf("category %s belongs to %q, want %q", category.Name, category.UserID, userID)
		}

		subcategories, err := database.Subcategories(userID, category.ID)
		if err != nil {
			t.Fatalf("list %s subcategories: %v", expected.name, err)
		}
		if len(subcategories) != len(expected.subcategories) {
			t.Fatalf("%s subcategories = %+v, want %v", expected.name, subcategories, expected.subcategories)
		}
		for j, name := range expected.subcategories {
			if subcategories[j].Name != name || subcategories[j].CategoryID != category.ID {
				t.Fatalf("%s subcategory %d = %+v, want %s under %s", expected.name, j, subcategories[j], name, category.Name)
			}
		}
	}

	settings, err := database.Settings(userID)
	if err != nil {
		t.Fatalf("read seeded settings: %v", err)
	}
	if settings.UserID != userID || settings.Timezone != "UTC" || settings.Theme != domain.ThemeSystem {
		t.Fatalf("seeded settings = %+v, want defaults for %s", settings, userID)
	}
}

func TestCreateUserSeedsTaxonomyAndSettings(t *testing.T) {
	database := newStore(t)

	user := newUser("seeded@example.com")
	if err := database.CreateUser(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	assertSeededTaxonomy(t, database, user.ID)

	// A second account receives its own records, not a shared taxonomy.
	other := newUser("other-seeded@example.com")
	if err := database.CreateUser(other); err != nil {
		t.Fatalf("create second user: %v", err)
	}
	firstCategories, err := database.Categories(user.ID)
	if err != nil {
		t.Fatalf("first categories: %v", err)
	}
	secondCategories, err := database.Categories(other.ID)
	if err != nil {
		t.Fatalf("second categories: %v", err)
	}
	if firstCategories[0].ID == secondCategories[0].ID {
		t.Fatal("each account must receive its own category records")
	}
}

func TestBootstrapAndInvitedAccountsAreSeeded(t *testing.T) {
	database := newStore(t)

	admin := newUser("admin@example.com")
	admin.Role = domain.RoleAdmin
	if err := database.CreateBootstrapUser(admin, "hash"); err != nil {
		t.Fatalf("bootstrap user: %v", err)
	}
	assertSeededTaxonomy(t, database, admin.ID)

	newInvite(t, database, "invited@example.com", "hash-invited")
	invited := newUser("invited@example.com")
	if _, err := database.CreateInvitedUser(invited, "hash", "hash-invited", time.Now().UTC()); err != nil {
		t.Fatalf("create invited user: %v", err)
	}
	assertSeededTaxonomy(t, database, invited.ID)
}

func TestSchemaVersionIsSetOnOpen(t *testing.T) {
	database := newStore(t)

	version, err := database.SchemaVersion()
	if err != nil {
		t.Fatalf("schema version: %v", err)
	}
	if version != 1 {
		t.Fatalf("schema version = %d, want 1", version)
	}
}

func TestEntryIndexesRebuildWhenTheIndexVersionChanges(t *testing.T) {
	cfg := testConfig(t)

	first, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	user := newUser("rebuild@example.com")
	if err := first.CreateUser(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	categories, err := first.Categories(user.ID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	category := categories[0]
	subcategory := testSubcategory(user.ID, category.ID, "Billing migration")
	if err := first.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}
	entry := testWorkEntry(user.ID, category, subcategory.ID, time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC), "Backfill")
	if err := first.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save entry: %v", err)
	}
	before, err := first.InstanceID()
	if err != nil {
		t.Fatalf("instance id: %v", err)
	}
	if err := first.Close(); err != nil {
		t.Fatalf("close store: %v", err)
	}

	// Simulate stale indexes from an older index version.
	raw, err := bbolt.Open(cfg.DBPath, 0o600, nil)
	if err != nil {
		t.Fatalf("open raw database: %v", err)
	}
	err = raw.Update(func(tx *bbolt.Tx) error {
		if err := tx.Bucket([]byte("sys:meta")).Delete([]byte("index_version")); err != nil {
			return err
		}
		return tx.DeleteBucket([]byte("user_" + user.ID + ":idx_entries_category"))
	})
	if err != nil {
		t.Fatalf("corrupt indexes: %v", err)
	}
	if err := raw.Close(); err != nil {
		t.Fatalf("close raw database: %v", err)
	}

	second, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("reopen store: %v", err)
	}
	defer second.Close()

	entries, err := second.WorkEntries(user.ID, store.WorkEntryFilter{CategoryID: category.ID})
	if err != nil {
		t.Fatalf("filter rebuilt index: %v", err)
	}
	if len(entries) != 1 || entries[0].ID != entry.ID {
		t.Fatalf("entries = %+v, want the entry found through the rebuilt index", entries)
	}

	after, err := second.InstanceID()
	if err != nil {
		t.Fatalf("instance id after reopen: %v", err)
	}
	if after != before {
		t.Fatalf("instance id changed from %q to %q across reopen", before, after)
	}
}
