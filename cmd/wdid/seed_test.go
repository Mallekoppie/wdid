package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/demo"
	"github.com/Mallekoppie/wdid/internal/store"
)

func seedStorageConfig(dbPath string) config.Config {
	return config.Config{DBPath: dbPath, StorageOnly: true}
}

func setSeedEnv(t *testing.T) string {
	t.Helper()

	dbPath := filepath.Join(t.TempDir(), "wdid-demo.db")
	t.Setenv("WDID_DB_PATH", dbPath)
	t.Setenv("WDID_DEV_MODE", "true")
	return dbPath
}

func TestSeedCommandRequiresDevMode(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wdid-demo.db")
	t.Setenv("WDID_DB_PATH", dbPath)
	t.Setenv("WDID_DEV_MODE", "false")

	var out bytes.Buffer
	err := runSeed([]string{"empty"}, &out)
	if err == nil {
		t.Fatal("seed without dev mode succeeded, want a refusal")
	}
	if !strings.Contains(err.Error(), "development-only") {
		t.Fatalf("error = %q, want the development-only refusal", err)
	}
	if _, statErr := os.Stat(dbPath); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("database at %s exists after a dev-mode refusal", dbPath)
	}
	if out.Len() != 0 {
		t.Fatalf("output = %q, want no output on refusal", out.String())
	}
}

func TestSeedCommandRejectsUnknownScenario(t *testing.T) {
	dbPath := setSeedEnv(t)

	err := runSeed([]string{"nope"}, &bytes.Buffer{})
	if err == nil || !strings.Contains(err.Error(), "unknown scenario") {
		t.Fatalf("error = %v, want an unknown scenario error", err)
	}
	if _, statErr := os.Stat(dbPath); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("database at %s exists after an unknown-scenario refusal", dbPath)
	}
}

func TestSeedCommandRequiresResetForExistingDatabase(t *testing.T) {
	dbPath := setSeedEnv(t)

	if err := runSeed([]string{"--reset", "--anchor", "2026-03-09", "empty"}, &bytes.Buffer{}); err != nil {
		t.Fatalf("first seed: %v", err)
	}
	before, err := os.ReadFile(dbPath)
	if err != nil {
		t.Fatalf("read seeded database: %v", err)
	}

	err = runSeed([]string{"empty"}, &bytes.Buffer{})
	if err == nil || !strings.Contains(err.Error(), "--reset") {
		t.Fatalf("error = %v, want a --reset refusal", err)
	}

	after, err := os.ReadFile(dbPath)
	if err != nil {
		t.Fatalf("read database after refusal: %v", err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("database changed after a refusal without --reset")
	}
}

func TestSeedCommandPrintsCredentialsAndCounts(t *testing.T) {
	dbPath := setSeedEnv(t)

	var out bytes.Buffer
	if err := runSeed([]string{"--reset", "--anchor", "2026-03-09", "empty"}, &out); err != nil {
		t.Fatalf("seed empty scenario: %v", err)
	}

	for _, want := range []string{
		"Seeded scenario: empty",
		"Database: " + dbPath,
		"Anchor: 2026-03-09",
		"Email: demo@wdid.local",
		"Password: demo-password-123",
		"Users: 1",
		"Categories: 3",
		"Subcategories: 10",
		"Entries: 0",
		"Notes: 0",
		"Milestones: 0",
		"Check-ins: 0",
		"Active timer: none",
	} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("output = %q, want %q", out.String(), want)
		}
	}

	database, err := store.Open(seedStorageConfig(dbPath))
	if err != nil {
		t.Fatalf("open seeded database: %v", err)
	}
	defer database.Close()

	if _, err := database.UserByEmail(demo.DemoEmail); err != nil {
		t.Fatalf("seeded account missing: %v", err)
	}
}

func TestSeedCommandResetsAnExistingDatabase(t *testing.T) {
	dbPath := setSeedEnv(t)

	if err := runSeed([]string{"--reset", "--anchor", "2026-03-09", "empty"}, &bytes.Buffer{}); err != nil {
		t.Fatalf("first seed: %v", err)
	}

	var out bytes.Buffer
	if err := runSeed([]string{"--reset", "--anchor", "2026-04-20", "empty"}, &out); err != nil {
		t.Fatalf("reset seed: %v", err)
	}
	if !strings.Contains(out.String(), "Anchor: 2026-04-20") {
		t.Fatalf("output = %q, want the new anchor", out.String())
	}

	database, err := store.Open(seedStorageConfig(dbPath))
	if err != nil {
		t.Fatalf("open reset database: %v", err)
	}
	defer database.Close()

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("seeded account missing: %v", err)
	}
	want := time.Date(2026, time.April, 20, 0, 0, 0, 0, time.UTC)
	if !user.CreatedAt.Equal(want) {
		t.Fatalf("account created at = %s, want the new anchor %s", user.CreatedAt, want)
	}
	if count, err := database.CountUsers(); err != nil || count != 1 {
		t.Fatalf("users = %d (%v), want exactly one after reset", count, err)
	}
}

func TestSeedCommandLeavesExistingDatabaseOnFailure(t *testing.T) {
	dbPath := setSeedEnv(t)

	if err := runSeed([]string{"--reset", "empty"}, &bytes.Buffer{}); err != nil {
		t.Fatalf("first seed: %v", err)
	}
	before, err := os.ReadFile(dbPath)
	if err != nil {
		t.Fatalf("read seeded database: %v", err)
	}

	original := seedScenario
	seedScenario = func(*store.Store, demo.Options) (demo.Summary, error) {
		return demo.Summary{}, errors.New("injected seed failure")
	}
	t.Cleanup(func() { seedScenario = original })

	err = runSeed([]string{"--reset", "empty"}, &bytes.Buffer{})
	if err == nil || !strings.Contains(err.Error(), "injected seed failure") {
		t.Fatalf("error = %v, want the injected failure", err)
	}

	after, err := os.ReadFile(dbPath)
	if err != nil {
		t.Fatalf("read database after failure: %v", err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("a failed seed changed the existing database")
	}

	matches, err := filepath.Glob(filepath.Join(filepath.Dir(dbPath), ".wdid-seed-*.db"))
	if err != nil {
		t.Fatalf("glob temporary databases: %v", err)
	}
	if len(matches) != 0 {
		t.Fatalf("temporary databases left behind: %v", matches)
	}

	// The process must not keep a handle on the deleted temp database.
	seedScenario = original
	if err := runSeed([]string{"--reset", "empty"}, &bytes.Buffer{}); err != nil {
		t.Fatalf("seed after a failed seed: %v", err)
	}
}

func TestSeedCommandLeavesNoTemporaryDatabaseOnSuccess(t *testing.T) {
	dbPath := setSeedEnv(t)

	if err := runSeed([]string{"--reset", "empty"}, &bytes.Buffer{}); err != nil {
		t.Fatalf("seed empty scenario: %v", err)
	}

	matches, err := filepath.Glob(filepath.Join(filepath.Dir(dbPath), ".wdid-seed-*.db"))
	if err != nil {
		t.Fatalf("glob temporary databases: %v", err)
	}
	if len(matches) != 0 {
		t.Fatalf("temporary databases left behind: %v", matches)
	}
}
