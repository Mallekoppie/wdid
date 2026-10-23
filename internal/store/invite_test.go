package store_test

import (
	"errors"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func newInvite(t *testing.T, database *store.Store, email, codeHash string) domain.Invite {
	t.Helper()

	invite := domain.Invite{
		ID:        domain.NewID(),
		Email:     email,
		CreatedAt: time.Now().UTC(),
	}
	if err := database.CreateInvite(invite, codeHash); err != nil {
		t.Fatalf("create invite: %v", err)
	}
	return invite
}

func newUser(email string) domain.User {
	return domain.User{
		ID:          domain.NewID(),
		Email:       email,
		DisplayName: "Invited User",
		Role:        domain.RoleUser,
		CreatedAt:   time.Now().UTC(),
	}
}

func TestInviteRoundTripAndRevoke(t *testing.T) {
	database := newStore(t)
	invite := newInvite(t, database, "new@example.com", "hash-1")

	invites, err := database.Invites()
	if err != nil {
		t.Fatalf("list invites: %v", err)
	}
	if len(invites) != 1 || invites[0].ID != invite.ID || invites[0].Email != "new@example.com" {
		t.Fatalf("invites = %+v, want the created invite", invites)
	}
	if invites[0].UsedAt != nil {
		t.Fatal("a new invite must be unused")
	}

	if err := database.RevokeInvite(invite.ID); err != nil {
		t.Fatalf("revoke invite: %v", err)
	}

	invites, err = database.Invites()
	if err != nil {
		t.Fatalf("list invites after revoke: %v", err)
	}
	if len(invites) != 0 {
		t.Fatalf("invites after revoke = %+v, want none", invites)
	}

	if err := database.RevokeInvite(invite.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("revoke missing invite error = %v, want ErrNotFound", err)
	}
}

func TestCreateBootstrapUserOnlyOnce(t *testing.T) {
	database := newStore(t)
	admin := newUser("admin@example.com")
	admin.Role = domain.RoleAdmin

	if err := database.CreateBootstrapUser(admin, "hash"); err != nil {
		t.Fatalf("bootstrap user: %v", err)
	}

	stored, err := database.UserByEmail("admin@example.com")
	if err != nil {
		t.Fatalf("user by email: %v", err)
	}
	if stored.ID != admin.ID || stored.Role != domain.RoleAdmin {
		t.Fatalf("stored user = %+v, want the admin", stored)
	}
	if hash, err := database.PasswordHash(admin.ID); err != nil || hash != "hash" {
		t.Fatalf("password hash = %q, %v", hash, err)
	}

	if err := database.CreateBootstrapUser(newUser("second@example.com"), "hash"); !errors.Is(err, store.ErrAlreadyBootstrapped) {
		t.Fatalf("second bootstrap error = %v, want ErrAlreadyBootstrapped", err)
	}
}

func TestCreateInvitedUserConsumesTheInvite(t *testing.T) {
	database := newStore(t)
	newInvite(t, database, "new@example.com", "hash-1")
	user := newUser("new@example.com")

	used, err := database.CreateInvitedUser(user, "hash", "hash-1", time.Now().UTC())
	if err != nil {
		t.Fatalf("create invited user: %v", err)
	}
	if used.UsedAt == nil || used.UsedBy != user.ID {
		t.Fatalf("used invite = %+v, want usedAt and usedBy set", used)
	}

	stored, err := database.UserByEmail("new@example.com")
	if err != nil {
		t.Fatalf("user by email: %v", err)
	}
	if stored.ID != user.ID || stored.Role != domain.RoleUser {
		t.Fatalf("stored user = %+v, want the invited user", stored)
	}

	second := newUser("other@example.com")
	if _, err := database.CreateInvitedUser(second, "hash", "hash-1", time.Now().UTC()); !errors.Is(err, store.ErrInviteUsed) {
		t.Fatalf("reuse error = %v, want ErrInviteUsed", err)
	}
	if _, err := database.UserByEmail("other@example.com"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("second user error = %v, want ErrNotFound", err)
	}

	if _, err := database.CreateInvitedUser(newUser("third@example.com"), "hash", "unknown", time.Now().UTC()); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("unknown invite error = %v, want ErrNotFound", err)
	}
}

func TestCreateInvitedUserRequiresTheInvitedEmail(t *testing.T) {
	database := newStore(t)
	newInvite(t, database, "new@example.com", "hash-1")

	if _, err := database.CreateInvitedUser(newUser("someone@example.com"), "hash", "hash-1", time.Now().UTC()); !errors.Is(err, store.ErrInviteEmailMismatch) {
		t.Fatalf("email mismatch error = %v, want ErrInviteEmailMismatch", err)
	}

	// The failed registration must not consume the invite.
	invites, err := database.Invites()
	if err != nil {
		t.Fatalf("list invites: %v", err)
	}
	if len(invites) != 1 || invites[0].UsedAt != nil {
		t.Fatalf("invites = %+v, want the invite still unused", invites)
	}
}

func TestCreateInvitedUserRollsBackWhenEmailExists(t *testing.T) {
	database := newStore(t)
	existing := newUser("taken@example.com")
	if err := database.CreateUser(existing); err != nil {
		t.Fatalf("create existing user: %v", err)
	}
	newInvite(t, database, "taken@example.com", "hash-1")

	if _, err := database.CreateInvitedUser(newUser("taken@example.com"), "hash", "hash-1", time.Now().UTC()); !errors.Is(err, store.ErrEmailExists) {
		t.Fatalf("duplicate email error = %v, want ErrEmailExists", err)
	}

	invites, err := database.Invites()
	if err != nil {
		t.Fatalf("list invites: %v", err)
	}
	if len(invites) != 1 || invites[0].UsedAt != nil {
		t.Fatalf("invites = %+v, want the invite still unused after rollback", invites)
	}
}
