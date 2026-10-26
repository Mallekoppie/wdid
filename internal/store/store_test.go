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
		AuthMode:             config.AuthModeServer,
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
