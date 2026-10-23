package store_test

import (
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func testConfig(t *testing.T) config.Config {
	t.Helper()

	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid-test.db"),
		BootstrapSecret:      "test-registration-secret",
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("test config invalid: %v", err)
	}
	return cfg
}

func newStore(t *testing.T) *store.Store {
	t.Helper()

	database, err := store.Open(testConfig(t))
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		_ = database.Close()
	})
	return database
}

func TestUserRoundTrip(t *testing.T) {
	database := newStore(t)

	user := domain.User{
		ID:          domain.NewID(),
		Email:       "Dev@Example.com",
		DisplayName: "Dev",
		Role:        domain.RoleAdmin,
		CreatedAt:   time.Now().UTC(),
	}
	user.Normalize()

	if err := database.CreateUser(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	byEmail, err := database.UserByEmail("dev@example.com")
	if err != nil {
		t.Fatalf("user by email: %v", err)
	}
	if byEmail.ID != user.ID {
		t.Fatalf("id = %q, want %q", byEmail.ID, user.ID)
	}

	byID, err := database.UserByID(user.ID)
	if err != nil {
		t.Fatalf("user by id: %v", err)
	}
	if byID.Role != domain.RoleAdmin {
		t.Fatalf("role = %q, want admin", byID.Role)
	}

	if err := database.CreateUser(user); !errors.Is(err, store.ErrEmailExists) {
		t.Fatalf("duplicate create error = %v, want ErrEmailExists", err)
	}

	count, err := database.CountUsers()
	if err != nil {
		t.Fatalf("count users: %v", err)
	}
	if count != 1 {
		t.Fatalf("count = %d, want 1", count)
	}
}

func TestInitiativeAndEntryQueries(t *testing.T) {
	database := newStore(t)
	userID := "user-1"

	initiative := domain.Initiative{
		ID:        domain.NewID(),
		UserID:    userID,
		Name:      "Billing migration",
		Status:    domain.InitiativeActive,
		Progress:  40,
		CreatedAt: time.Now().UTC(),
		UpdatedAt: time.Now().UTC(),
	}
	if err := database.SaveInitiative(initiative); err != nil {
		t.Fatalf("save initiative: %v", err)
	}

	base := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	entries := []domain.Entry{
		{
			ID: domain.NewID(), UserID: userID, Kind: domain.EntryInitiative,
			InitiativeID: initiative.ID, Description: "Backfill script",
			StartedAt: base, EndedAt: base.Add(45 * time.Minute), Minutes: 45,
			CreatedAt: base, UpdatedAt: base,
		},
		{
			ID: domain.NewID(), UserID: userID, Kind: domain.EntryOther,
			Description: "Sprint planning",
			StartedAt:   base.Add(2 * time.Hour), EndedAt: base.Add(3 * time.Hour), Minutes: 60,
			CreatedAt: base, UpdatedAt: base,
		},
	}
	for _, entry := range entries {
		if err := database.SaveEntry(entry); err != nil {
			t.Fatalf("save entry: %v", err)
		}
	}

	all, err := database.Entries(userID, store.EntryFilter{})
	if err != nil {
		t.Fatalf("list entries: %v", err)
	}
	if len(all) != 2 {
		t.Fatalf("entries = %d, want 2", len(all))
	}
	if all[0].Description != "Sprint planning" {
		t.Fatalf("first entry = %q, want newest entry", all[0].Description)
	}

	byKind, err := database.Entries(userID, store.EntryFilter{Kind: domain.EntryInitiative})
	if err != nil {
		t.Fatalf("filter by kind: %v", err)
	}
	if len(byKind) != 1 || byKind[0].InitiativeID != initiative.ID {
		t.Fatalf("unexpected kind filter result: %+v", byKind)
	}

	window, err := database.Entries(userID, store.EntryFilter{
		From: base.Add(-time.Minute),
		To:   base.Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("filter by window: %v", err)
	}
	if len(window) != 1 {
		t.Fatalf("window entries = %d, want 1", len(window))
	}

	search, err := database.Entries(userID, store.EntryFilter{Query: "backfill"})
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if len(search) != 1 {
		t.Fatalf("search entries = %d, want 1", len(search))
	}

	otherUser, err := database.Entries("user-2", store.EntryFilter{})
	if err != nil {
		t.Fatalf("other user entries: %v", err)
	}
	if len(otherUser) != 0 {
		t.Fatalf("cross-tenant entries = %d, want 0", len(otherUser))
	}

	if err := database.DeleteEntry(userID, entries[0].ID); err != nil {
		t.Fatalf("delete entry: %v", err)
	}
	remaining, err := database.Entries(userID, store.EntryFilter{})
	if err != nil {
		t.Fatalf("list after delete: %v", err)
	}
	if len(remaining) != 1 {
		t.Fatalf("remaining entries = %d, want 1", len(remaining))
	}
}

func TestTimerLifecycleStorage(t *testing.T) {
	database := newStore(t)
	userID := "user-timer"

	if _, active, err := database.ActiveTimer(userID); err != nil || active {
		t.Fatalf("initial timer active=%v err=%v, want inactive", active, err)
	}

	now := time.Now().UTC()
	timer := domain.ActiveTimer{
		UserID:           userID,
		Description:      "Writing tests",
		StartedAt:        now,
		SegmentStartedAt: now,
	}
	if err := database.SaveTimer(timer); err != nil {
		t.Fatalf("save timer: %v", err)
	}

	stored, active, err := database.ActiveTimer(userID)
	if err != nil {
		t.Fatalf("read timer: %v", err)
	}
	if !active || stored.Description != "Writing tests" {
		t.Fatalf("unexpected timer: active=%v timer=%+v", active, stored)
	}

	if err := database.ClearTimer(userID); err != nil {
		t.Fatalf("clear timer: %v", err)
	}
	if _, active, err := database.ActiveTimer(userID); err != nil || active {
		t.Fatalf("after clear active=%v err=%v, want inactive", active, err)
	}
}
