package store_test

import (
	"errors"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func localUser(username string) domain.User {
	return domain.User{
		ID:          domain.NewID(),
		Username:    username,
		DisplayName: username,
		Role:        domain.RoleAdmin,
		CreatedAt:   time.Now().UTC(),
	}
}

func TestCreateLocalUserWithoutPasswordOrEmail(t *testing.T) {
	database := newStore(t)

	user := localUser("malle")
	if err := database.CreateLocalUser(user, ""); err != nil {
		t.Fatalf("create local user: %v", err)
	}

	stored, err := database.UserByUsername("  MALLE ")
	if err != nil {
		t.Fatalf("user by username: %v", err)
	}
	if stored.ID != user.ID {
		t.Fatalf("stored user = %q, want %q", stored.ID, user.ID)
	}
	if stored.Email != "" {
		t.Fatalf("local user email = %q, want empty", stored.Email)
	}

	if _, err := database.PasswordHash(user.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("password hash error = %v, want ErrNotFound for a passwordless account", err)
	}
	if count, err := database.CountUsers(); err != nil || count != 1 {
		t.Fatalf("count users = %d, %v, want 1", count, err)
	}
}

func TestCreateLocalUserStoresAnOptionalPassword(t *testing.T) {
	database := newStore(t)

	const password = "longenough1"
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}

	user := localUser("malle")
	if err := database.CreateLocalUser(user, string(hash)); err != nil {
		t.Fatalf("create local user: %v", err)
	}

	storedHash, err := database.PasswordHash(user.ID)
	if err != nil {
		t.Fatalf("password hash: %v", err)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(password)); err != nil {
		t.Fatalf("stored credential does not verify: %v", err)
	}
}

func TestCreateLocalUserRejectsASecondAccount(t *testing.T) {
	database := newStore(t)

	if err := database.CreateLocalUser(localUser("malle"), ""); err != nil {
		t.Fatalf("create first local user: %v", err)
	}

	err := database.CreateLocalUser(localUser("someone-else"), "")
	if !errors.Is(err, store.ErrAlreadyBootstrapped) {
		t.Fatalf("second account error = %v, want ErrAlreadyBootstrapped", err)
	}
}

func TestLocalUserReturnsTheOnlyAccount(t *testing.T) {
	database := newStore(t)

	if _, err := database.LocalUser(); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("empty local user error = %v, want ErrNotFound", err)
	}

	user := localUser("malle")
	if err := database.CreateLocalUser(user, ""); err != nil {
		t.Fatalf("create local user: %v", err)
	}

	stored, err := database.LocalUser()
	if err != nil {
		t.Fatalf("local user: %v", err)
	}
	if stored.ID != user.ID {
		t.Fatalf("local user = %q, want %q", stored.ID, user.ID)
	}
}
