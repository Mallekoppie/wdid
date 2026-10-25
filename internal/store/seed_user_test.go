package store_test

import (
	"errors"
	"testing"

	"golang.org/x/crypto/bcrypt"

	"github.com/Mallekoppie/wdid/internal/store"
)

// assertUnseededAccount proves an account created through the seed-safe path has
// no user-owned records: the demo seeder writes those itself.
func assertUnseededAccount(t *testing.T, database *store.Store, userID string) {
	t.Helper()

	categories, err := database.Categories(userID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	if len(categories) != 0 {
		t.Fatalf("categories = %+v, want none for a seed-safe account", categories)
	}

	subcategories, err := database.Subcategories(userID, "")
	if err != nil {
		t.Fatalf("list subcategories: %v", err)
	}
	if len(subcategories) != 0 {
		t.Fatalf("subcategories = %+v, want none for a seed-safe account", subcategories)
	}

	if _, err := database.Settings(userID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("settings error = %v, want ErrNotFound", err)
	}
}

func TestCreateSeedUserCreatesLoginableAccountWithoutDefaults(t *testing.T) {
	database := newStore(t)

	user := newUser("demo@wdid.local")
	const password = "demo-password-1234"
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}

	if err := database.CreateSeedUser(user, string(hash)); err != nil {
		t.Fatalf("create seed user: %v", err)
	}

	stored, err := database.UserByEmail("demo@wdid.local")
	if err != nil {
		t.Fatalf("user by email: %v", err)
	}
	if stored.ID != user.ID || stored.DisplayName != user.DisplayName {
		t.Fatalf("stored user = %+v, want the created account %+v", stored, user)
	}

	storedHash, err := database.PasswordHash(user.ID)
	if err != nil {
		t.Fatalf("password hash: %v", err)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(password)); err != nil {
		t.Fatalf("stored credential does not verify: %v", err)
	}

	assertUnseededAccount(t, database, user.ID)
}

func TestCreateSeedUserRejectsDuplicateEmail(t *testing.T) {
	database := newStore(t)

	first := newUser("demo@wdid.local")
	if err := database.CreateSeedUser(first, "hash"); err != nil {
		t.Fatalf("create seed user: %v", err)
	}

	duplicate := newUser(" Demo@WDID.local ")
	if err := database.CreateSeedUser(duplicate, "other-hash"); !errors.Is(err, store.ErrEmailExists) {
		t.Fatalf("duplicate email error = %v, want ErrEmailExists", err)
	}

	stored, err := database.UserByEmail("demo@wdid.local")
	if err != nil {
		t.Fatalf("user by email: %v", err)
	}
	if stored.ID != first.ID {
		t.Fatalf("stored user = %+v, want the original account %s", stored, first.ID)
	}
	if _, err := database.UserByID(duplicate.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("duplicate account error = %v, want ErrNotFound after rollback", err)
	}
	if _, err := database.PasswordHash(duplicate.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("duplicate credential error = %v, want ErrNotFound after rollback", err)
	}
}

func TestMissingUserReadsKeepErrNotFound(t *testing.T) {
	database := newStore(t)

	if _, err := database.UserByID("missing-user"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("UserByID error = %v, want ErrNotFound", err)
	}
	if _, err := database.UserByEmail("missing@example.com"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("UserByEmail error = %v, want ErrNotFound", err)
	}
	if _, err := database.PasswordHash("missing-user"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("PasswordHash error = %v, want ErrNotFound", err)
	}
}

func TestProductionAccountCreationStillSeedsDefaults(t *testing.T) {
	database := newStore(t)

	seedUser := newUser("seed@example.com")
	if err := database.CreateSeedUser(seedUser, "hash"); err != nil {
		t.Fatalf("create seed user: %v", err)
	}

	productionUser := newUser("production@example.com")
	if err := database.CreateUser(productionUser); err != nil {
		t.Fatalf("create production user: %v", err)
	}
	assertSeededTaxonomy(t, database, productionUser.ID)

	// Creating a production account must not seed another account's records.
	assertUnseededAccount(t, database, seedUser.ID)
}
