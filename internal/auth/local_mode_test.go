package auth_test

import (
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func localModeConfig(t *testing.T, path string) config.Config {
	t.Helper()

	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               path,
		AuthMode:             config.AuthModeLocal,
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("local config invalid: %v", err)
	}
	return cfg
}

func serverModeConfig(t *testing.T, path string) config.Config {
	t.Helper()

	cfg := localModeConfig(t, path)
	cfg.AuthMode = config.AuthModeServer
	cfg.BootstrapSecret = testBootstrapSecret
	if err := cfg.Validate(); err != nil {
		t.Fatalf("server config invalid: %v", err)
	}
	return cfg
}

// seedLegacyServerAccount writes a server-mode account (no username) and
// closes the database so the caller can reopen it in local mode.
func seedLegacyServerAccount(t *testing.T, path string) {
	t.Helper()

	database, err := store.Open(serverModeConfig(t, path))
	if err != nil {
		t.Fatalf("open server database: %v", err)
	}

	user := domain.User{
		ID:          domain.NewID(),
		Email:       "admin@example.com",
		DisplayName: "Admin",
		Role:        domain.RoleAdmin,
		CreatedAt:   time.Now().UTC(),
	}
	if err := database.CreateBootstrapUser(user, "not-used-by-this-test"); err != nil {
		_ = database.Close()
		t.Fatalf("create legacy server account: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close server database: %v", err)
	}
}

func TestEnsureLocalModeCompatibleAcceptsAFreshLocalDatabase(t *testing.T) {
	cfg := localModeConfig(t, filepath.Join(t.TempDir(), "fresh-local.db"))
	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open local database: %v", err)
	}
	t.Cleanup(func() { _ = database.Close() })

	if err := auth.EnsureLocalModeCompatible(database, cfg); err != nil {
		t.Fatalf("a fresh local database must start: %v", err)
	}
}

func TestEnsureLocalModeCompatibleRejectsLegacyServerAccounts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "legacy-server.db")
	seedLegacyServerAccount(t, path)

	cfg := localModeConfig(t, path)
	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("reopen database in local mode: %v", err)
	}
	t.Cleanup(func() { _ = database.Close() })

	err = auth.EnsureLocalModeCompatible(database, cfg)
	if !errors.Is(err, auth.ErrLegacyServerDatabase) {
		t.Fatalf("error = %v, want ErrLegacyServerDatabase", err)
	}
	if !strings.Contains(err.Error(), "WDID_AUTH_MODE=server") {
		t.Fatalf("error = %q, want actionable instructions to set WDID_AUTH_MODE=server", err)
	}
}

func TestEnsureLocalModeCompatibleIsSkippedInDevMode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "legacy-dev.db")
	seedLegacyServerAccount(t, path)

	cfg := localModeConfig(t, path)
	// Development mode resolves to server mode, so the guard must not block
	// make run or the seeded demo paths.
	cfg.DevMode = true
	cfg.BootstrapSecret = testBootstrapSecret
	if err := cfg.Validate(); err != nil {
		t.Fatalf("dev config invalid: %v", err)
	}

	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("reopen database in dev mode: %v", err)
	}
	t.Cleanup(func() { _ = database.Close() })

	if err := auth.EnsureLocalModeCompatible(database, cfg); err != nil {
		t.Fatalf("dev mode must not be blocked: %v", err)
	}
}
