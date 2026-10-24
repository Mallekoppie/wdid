package store_test

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
	"time"

	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func TestSnapshotCopiesCommittedDataAndVerifies(t *testing.T) {
	database := newStore(t)

	user := domain.User{
		ID:          domain.NewID(),
		Email:       "snapshot@example.com",
		DisplayName: "Snapshot",
		Role:        domain.RoleAdmin,
		CreatedAt:   time.Now().UTC(),
	}
	user.Normalize()
	if err := database.CreateUser(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	var copy bytes.Buffer
	if err := database.Snapshot(&copy); err != nil {
		t.Fatalf("snapshot: %v", err)
	}
	if copy.Len() == 0 {
		t.Fatal("snapshot is empty")
	}

	path := filepath.Join(t.TempDir(), "snapshot.db")
	if err := os.WriteFile(path, copy.Bytes(), 0o600); err != nil {
		t.Fatalf("write snapshot file: %v", err)
	}

	version, err := store.VerifySnapshot(path)
	if err != nil {
		t.Fatalf("verify snapshot: %v", err)
	}
	if version != 1 {
		t.Fatalf("schema version = %d, want 1", version)
	}

	// The copy contains committed data from before the read transaction.
	copied, err := bbolt.Open(path, 0o600, &bbolt.Options{ReadOnly: true})
	if err != nil {
		t.Fatalf("open copied database: %v", err)
	}
	defer copied.Close()
	err = copied.View(func(tx *bbolt.Tx) error {
		users := tx.Bucket([]byte("sys:users"))
		if users == nil {
			t.Fatal("snapshot has no users bucket")
		}
		if users.Get([]byte(user.ID)) == nil {
			t.Fatal("snapshot is missing the created user")
		}
		return nil
	})
	if err != nil {
		t.Fatalf("read copied database: %v", err)
	}
}

func TestVerifySnapshotRejectsNonDatabase(t *testing.T) {
	path := filepath.Join(t.TempDir(), "not-a-database.db")
	if err := os.WriteFile(path, []byte("this is not bolt"), 0o600); err != nil {
		t.Fatalf("write file: %v", err)
	}

	if _, err := store.VerifySnapshot(path); err == nil {
		t.Fatal("expected verification to reject a non-database file")
	}
}

func TestVerifySnapshotRejectsMissingSchemaVersion(t *testing.T) {
	path := filepath.Join(t.TempDir(), "empty.db")
	database, err := bbolt.Open(path, 0o600, nil)
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close database: %v", err)
	}

	if _, err := store.VerifySnapshot(path); err == nil {
		t.Fatal("expected verification to reject a database without a schema version")
	}
}
