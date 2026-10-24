package store_test

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func openStoreWithConfig(t *testing.T) (*store.Store, config.Config) {
	t.Helper()

	cfg := testConfig(t)
	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		_ = database.Close()
	})
	return database, cfg
}

// snapshotFile writes a consistent copy of the live database to a file.
func snapshotFile(t *testing.T, database *store.Store) string {
	t.Helper()

	var copy bytes.Buffer
	if err := database.Snapshot(&copy); err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	path := filepath.Join(t.TempDir(), "snapshot.db")
	if err := os.WriteFile(path, copy.Bytes(), 0o600); err != nil {
		t.Fatalf("write snapshot file: %v", err)
	}
	return path
}

func createRestoreUser(t *testing.T, database *store.Store, email string) domain.User {
	t.Helper()

	user := newUser(email)
	user.Normalize()
	if err := database.CreateUser(user); err != nil {
		t.Fatalf("create user %s: %v", email, err)
	}
	return user
}

func listFiles(t *testing.T, dir string) []string {
	t.Helper()

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read directory %s: %v", dir, err)
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	return names
}

func TestRestoreRoundTripPreservesPreRestoreDatabase(t *testing.T) {
	database, cfg := openStoreWithConfig(t)
	before := createRestoreUser(t, database, "before@example.com")

	snapshotPath := snapshotFile(t, database)

	after := createRestoreUser(t, database, "after@example.com")

	result, err := database.Restore(snapshotPath)
	if err != nil {
		t.Fatalf("restore: %v", err)
	}
	if result.SchemaVersion != 1 {
		t.Fatalf("schema version = %d, want 1", result.SchemaVersion)
	}
	if result.PreRestorePath == "" {
		t.Fatal("pre-restore path is empty")
	}
	if filepath.Dir(result.PreRestorePath) != filepath.Dir(cfg.DBPath) {
		t.Fatalf("pre-restore path = %q, want it next to the database", result.PreRestorePath)
	}
	if !strings.HasPrefix(filepath.Base(result.PreRestorePath), "wdid-before-restore-") {
		t.Fatalf("pre-restore name = %q, want the wdid-before-restore prefix", result.PreRestorePath)
	}

	// The restored database is the snapshot: the later account is gone and the
	// earlier one still exists.
	if _, err := database.UserByEmail("after@example.com"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("post-snapshot user after restore error = %v, want ErrNotFound", err)
	}
	if user, err := database.UserByID(before.ID); err != nil || user.Email != before.Email {
		t.Fatalf("pre-snapshot user after restore = %+v, %v", user, err)
	}

	// The pre-restore copy is the database as it was immediately before the
	// restore, including the later account.
	copied, err := bbolt.Open(result.PreRestorePath, 0o600, &bbolt.Options{ReadOnly: true})
	if err != nil {
		t.Fatalf("open pre-restore copy: %v", err)
	}
	defer copied.Close()
	if err := copied.View(func(tx *bbolt.Tx) error {
		users := tx.Bucket([]byte("sys:users"))
		if users == nil {
			t.Fatal("pre-restore copy has no users bucket")
		}
		if users.Get([]byte(after.ID)) == nil {
			t.Fatal("pre-restore copy is missing the post-snapshot account")
		}
		if users.Get([]byte(before.ID)) == nil {
			t.Fatal("pre-restore copy is missing the pre-snapshot account")
		}
		return nil
	}); err != nil {
		t.Fatalf("read pre-restore copy: %v", err)
	}

	// No staging files are left behind.
	for _, name := range listFiles(t, filepath.Dir(cfg.DBPath)) {
		if strings.HasPrefix(name, ".wdid-restore-") {
			t.Fatalf("staging file left behind: %s", name)
		}
	}
}

func TestRestoreRefusesInvalidSnapshotBeforeChangingAnything(t *testing.T) {
	database, cfg := openStoreWithConfig(t)
	user := createRestoreUser(t, database, "intact@example.com")

	invalid := filepath.Join(t.TempDir(), "not-a-backup.db")
	if err := os.WriteFile(invalid, []byte("this is not a bolt database"), 0o600); err != nil {
		t.Fatalf("write invalid snapshot: %v", err)
	}

	if _, err := database.Restore(invalid); err == nil {
		t.Fatal("expected an invalid snapshot to be refused")
	} else if !errors.Is(err, store.ErrInvalidSnapshot) {
		t.Fatalf("error = %v, want ErrInvalidSnapshot", err)
	}

	// The live database still serves and no pre-restore copy was written.
	if stored, err := database.UserByID(user.ID); err != nil || stored.Email != user.Email {
		t.Fatalf("user after refused restore = %+v, %v", stored, err)
	}
	for _, name := range listFiles(t, filepath.Dir(cfg.DBPath)) {
		if strings.HasPrefix(name, "wdid-before-restore-") {
			t.Fatalf("a refused restore wrote a pre-restore copy: %s", name)
		}
	}
}

func TestRestoreRebuildsEntryIndexes(t *testing.T) {
	database, _ := openStoreWithConfig(t)
	user := createRestoreUser(t, database, "indexed@example.com")

	categories, err := database.Categories(user.ID)
	if err != nil || len(categories) == 0 {
		t.Fatalf("categories = %v, %v", categories, err)
	}
	started := time.Date(2026, 2, 3, 9, 0, 0, 0, time.UTC)
	entry := domain.WorkEntry{
		ID:          domain.NewID(),
		UserID:      user.ID,
		CategoryID:  categories[0].ID,
		Description: "Indexed work",
		StartedAt:   started,
		EndedAt:     started.Add(45 * time.Minute),
		Minutes:     45,
		Source:      domain.EntrySourceManual,
		CreatedAt:   started,
		UpdatedAt:   started,
	}
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save work entry: %v", err)
	}

	snapshotPath := snapshotFile(t, database)

	// Remove the day index from the snapshot. A restore that only reused the
	// snapshot's index version would leave filtered listings empty.
	snapshotDB, err := bbolt.Open(snapshotPath, 0o600, nil)
	if err != nil {
		t.Fatalf("open snapshot for editing: %v", err)
	}
	indexBucket := "user_" + user.ID + ":idx_entries_day"
	if err := snapshotDB.Update(func(tx *bbolt.Tx) error {
		return tx.DeleteBucket([]byte(indexBucket))
	}); err != nil {
		snapshotDB.Close()
		t.Fatalf("delete index bucket from snapshot: %v", err)
	}
	if err := snapshotDB.Close(); err != nil {
		t.Fatalf("close edited snapshot: %v", err)
	}

	// A later account proves the restore actually replaced the database.
	after := createRestoreUser(t, database, "after@example.com")

	if _, err := database.Restore(snapshotPath); err != nil {
		t.Fatalf("restore: %v", err)
	}
	if _, err := database.UserByID(after.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("post-snapshot user after restore error = %v, want ErrNotFound", err)
	}

	// The rebuilt day index is present and serves the filtered listing.
	entries, err := database.WorkEntries(user.ID, store.WorkEntryFilter{LocalDate: "2026-02-03"})
	if err != nil {
		t.Fatalf("list entries by local date: %v", err)
	}
	if len(entries) != 1 || entries[0].ID != entry.ID {
		t.Fatalf("entries by local date = %+v, want the restored entry", entries)
	}
}
