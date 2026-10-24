package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func TestBackupCommandCreatesManualSnapshot(t *testing.T) {
	root := t.TempDir()
	backupDir := filepath.Join(root, "backups")
	t.Setenv("WDID_DB_PATH", filepath.Join(root, "wdid.db"))
	t.Setenv("WDID_BACKUP_DIR", backupDir)

	var out bytes.Buffer
	if err := runBackup(nil, &out); err != nil {
		t.Fatalf("run backup: %v", err)
	}
	if !strings.Contains(out.String(), "Created backup") {
		t.Fatalf("output = %q, want the created backup path", out.String())
	}

	entries, err := os.ReadDir(backupDir)
	if err != nil {
		t.Fatalf("read backup directory: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("backups = %v, want one manual snapshot", entries)
	}
	name := entries[0].Name()
	if !strings.HasPrefix(name, "wdid-") || !strings.HasSuffix(name, "-manual.db") {
		t.Fatalf("name = %q, want a manual snapshot name", name)
	}

	out.Reset()
	if err := runBackup([]string{"status"}, &out); err != nil {
		t.Fatalf("run backup status: %v", err)
	}
	status := out.String()
	for _, want := range []string{
		"Directory: " + backupDir,
		"Last backup:",
		"manual",
		"Overdue: true",
	} {
		if !strings.Contains(status, want) {
			t.Fatalf("status = %q, want %q", status, want)
		}
	}

	out.Reset()
	if err := runBackup([]string{"list"}, &out); err != nil {
		t.Fatalf("run backup list: %v", err)
	}
	if !strings.Contains(out.String(), name) {
		t.Fatalf("list = %q, want %q", out.String(), name)
	}
}

func TestRestoreCommandRestoresNamedSnapshot(t *testing.T) {
	root := t.TempDir()
	dbPath := filepath.Join(root, "wdid.db")
	backupDir := filepath.Join(root, "backups")
	t.Setenv("WDID_DB_PATH", dbPath)
	t.Setenv("WDID_BACKUP_DIR", backupDir)

	var out bytes.Buffer
	if err := runBackup(nil, &out); err != nil {
		t.Fatalf("run backup: %v", err)
	}
	entries, err := os.ReadDir(backupDir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("backups = %v, %v, want one snapshot", entries, err)
	}
	name := entries[0].Name()

	// Add an account after the snapshot. A successful restore removes it.
	database, err := openCLIStore()
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	user := domain.User{
		ID:          domain.NewID(),
		Email:       "after-snapshot@example.com",
		DisplayName: "After",
		Role:        domain.RoleUser,
		CreatedAt:   time.Now().UTC(),
	}
	user.Normalize()
	if err := database.CreateUser(user); err != nil {
		database.Close()
		t.Fatalf("create user: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close store: %v", err)
	}

	out.Reset()
	if err := runRestore([]string{name}, &out); err != nil {
		t.Fatalf("run restore: %v", err)
	}
	output := out.String()
	if !strings.Contains(output, "Restored "+name) {
		t.Fatalf("restore output = %q, want the snapshot name", output)
	}
	if !strings.Contains(output, "wdid-before-restore-") {
		t.Fatalf("restore output = %q, want the pre-restore copy", output)
	}

	database, err = openCLIStore()
	if err != nil {
		t.Fatalf("reopen store after restore: %v", err)
	}
	if _, err := database.UserByEmail(user.Email); !errors.Is(err, store.ErrNotFound) {
		database.Close()
		t.Fatalf("post-snapshot account after restore error = %v, want ErrNotFound", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close store after restore: %v", err)
	}

	// A name that is not a snapshot is refused.
	if err := runRestore([]string{"not-a-backup.db"}, &out); err == nil {
		t.Fatal("expected an unknown snapshot name to fail")
	}
}

func TestRestoreCommandRequiresName(t *testing.T) {
	if err := runRestore(nil, &bytes.Buffer{}); err == nil {
		t.Fatal("expected a usage error without a name")
	}
}
