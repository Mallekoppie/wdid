package auth_test

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/invite"
	"github.com/Mallekoppie/wdid/internal/store"
)

const (
	testBootstrapSecret = "test-bootstrap-secret"
	testPassword        = "longenough1"
)

func newService(t *testing.T) (*auth.Service, *store.Store) {
	t.Helper()

	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid-auth.db"),
		BootstrapSecret:      testBootstrapSecret,
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("test config invalid: %v", err)
	}

	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		_ = database.Close()
	})

	return auth.NewService(database, cfg), database
}

func bootstrap(t *testing.T, service *auth.Service) (domain.User, string) {
	t.Helper()

	user, token, err := service.Register(auth.RegisterRequest{
		Email:           "admin@example.com",
		Password:        testPassword,
		DisplayName:     "Admin",
		BootstrapSecret: testBootstrapSecret,
	}, time.Now().UTC())
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}
	return user, token
}

func createInvite(t *testing.T, database *store.Store, email string) (domain.Invite, string) {
	t.Helper()

	code, err := invite.New()
	if err != nil {
		t.Fatalf("generate invite code: %v", err)
	}
	record := domain.Invite{ID: domain.NewID(), Email: email, CreatedAt: time.Now().UTC()}
	if err := database.CreateInvite(record, invite.Hash(code)); err != nil {
		t.Fatalf("create invite: %v", err)
	}
	return record, code
}

func registerWithInvite(service *auth.Service, email, code string) (domain.User, string, error) {
	return service.Register(auth.RegisterRequest{
		Email:       email,
		Password:    testPassword,
		DisplayName: "Invited User",
		InviteCode:  code,
	}, time.Now().UTC())
}

func TestFirstUserBecomesAdminWithBootstrapSecret(t *testing.T) {
	service, _ := newService(t)

	first, token := bootstrap(t, service)
	if first.Role != domain.RoleAdmin {
		t.Fatalf("first role = %q, want admin", first.Role)
	}

	identity, err := service.VerifyToken(context.Background(), token)
	if err != nil {
		t.Fatalf("verify token: %v", err)
	}
	if identity.UserID != first.ID {
		t.Fatalf("identity user = %q, want %q", identity.UserID, first.ID)
	}
	if !identity.HasRole(string(domain.RoleAdmin)) {
		t.Fatalf("roles = %v, want admin", identity.Roles)
	}
}

func TestBootstrapRejectsBadSecret(t *testing.T) {
	service, _ := newService(t)

	_, _, err := service.Register(auth.RegisterRequest{
		Email:           "admin@example.com",
		Password:        testPassword,
		BootstrapSecret: "wrong-secret-value",
	}, time.Now().UTC())

	if !errors.Is(err, auth.ErrInvalidBootstrapSecret) {
		t.Fatalf("error = %v, want ErrInvalidBootstrapSecret", err)
	}
}

func TestBootstrapSecretIsRejectedAfterFirstUser(t *testing.T) {
	service, _ := newService(t)
	bootstrap(t, service)

	_, _, err := service.Register(auth.RegisterRequest{
		Email:           "second@example.com",
		Password:        testPassword,
		BootstrapSecret: testBootstrapSecret,
	}, time.Now().UTC())

	if !errors.Is(err, auth.ErrInviteRequired) {
		t.Fatalf("error = %v, want ErrInviteRequired", err)
	}
}

func TestRegistrationWithoutInviteFails(t *testing.T) {
	service, _ := newService(t)
	bootstrap(t, service)

	_, _, err := registerWithInvite(service, "new@example.com", "")
	if !errors.Is(err, auth.ErrInviteRequired) {
		t.Fatalf("error = %v, want ErrInviteRequired", err)
	}
}

func TestInviteRegistration(t *testing.T) {
	service, database := newService(t)
	bootstrap(t, service)
	_, code := createInvite(t, database, "new@example.com")

	user, token, err := registerWithInvite(service, "NEW@example.com", code)
	if err != nil {
		t.Fatalf("register with invite: %v", err)
	}
	if user.Role != domain.RoleUser {
		t.Fatalf("invited role = %q, want user", user.Role)
	}
	if token == "" {
		t.Fatal("invite registration returned an empty token")
	}

	loggedIn, _, err := service.Login("new@example.com", testPassword)
	if err != nil {
		t.Fatalf("login invited user: %v", err)
	}
	if loggedIn.ID != user.ID {
		t.Fatalf("login user = %q, want %q", loggedIn.ID, user.ID)
	}
}

func TestInviteCannotBeReused(t *testing.T) {
	service, database := newService(t)
	bootstrap(t, service)
	_, code := createInvite(t, database, "new@example.com")

	if _, _, err := registerWithInvite(service, "new@example.com", code); err != nil {
		t.Fatalf("first registration: %v", err)
	}

	_, _, err := registerWithInvite(service, "another@example.com", code)
	if !errors.Is(err, auth.ErrInviteUsed) {
		t.Fatalf("reuse error = %v, want ErrInviteUsed", err)
	}
}

func TestRevokedInviteCannotBeRedeemed(t *testing.T) {
	service, database := newService(t)
	bootstrap(t, service)
	record, code := createInvite(t, database, "new@example.com")

	if err := database.RevokeInvite(record.ID); err != nil {
		t.Fatalf("revoke invite: %v", err)
	}

	_, _, err := registerWithInvite(service, "new@example.com", code)
	if !errors.Is(err, auth.ErrInvalidInvite) {
		t.Fatalf("revoked invite error = %v, want ErrInvalidInvite", err)
	}
}

func TestInviteRejectsUnknownCode(t *testing.T) {
	service, _ := newService(t)
	bootstrap(t, service)

	_, _, err := registerWithInvite(service, "new@example.com", "wdid-AAAA-AAAA-AAAA-AAAA")
	if !errors.Is(err, auth.ErrInvalidInvite) {
		t.Fatalf("unknown invite error = %v, want ErrInvalidInvite", err)
	}
}

func TestInviteRejectsAnotherEmail(t *testing.T) {
	service, database := newService(t)
	bootstrap(t, service)
	_, code := createInvite(t, database, "new@example.com")

	_, _, err := registerWithInvite(service, "someone@example.com", code)
	if !errors.Is(err, auth.ErrInviteEmailMismatch) {
		t.Fatalf("email mismatch error = %v, want ErrInviteEmailMismatch", err)
	}
}

func TestInviteRegistrationRejectsDuplicateEmail(t *testing.T) {
	service, database := newService(t)
	admin, _ := bootstrap(t, service)
	_, code := createInvite(t, database, admin.Email)

	_, _, err := registerWithInvite(service, admin.Email, code)
	if !errors.Is(err, store.ErrEmailExists) {
		t.Fatalf("error = %v, want ErrEmailExists", err)
	}
}

func TestLogin(t *testing.T) {
	service, _ := newService(t)
	user, _ := bootstrap(t, service)

	loggedIn, token, err := service.Login("ADMIN@example.com", testPassword)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if loggedIn.ID != user.ID {
		t.Fatalf("login user = %q, want %q", loggedIn.ID, user.ID)
	}
	if token == "" {
		t.Fatal("login returned an empty token")
	}

	if _, _, err := service.Login("admin@example.com", "wrong-password"); !errors.Is(err, auth.ErrInvalidCredentials) {
		t.Fatalf("wrong password error = %v, want ErrInvalidCredentials", err)
	}

	if _, _, err := service.Login("missing@example.com", testPassword); !errors.Is(err, auth.ErrInvalidCredentials) {
		t.Fatalf("unknown email error = %v, want ErrInvalidCredentials", err)
	}
}

func TestVerifyTokenRejectsGarbage(t *testing.T) {
	service, _ := newService(t)

	if _, err := service.VerifyToken(context.Background(), "not-a-token"); !errors.Is(err, auth.ErrUnauthenticated) {
		t.Fatalf("error = %v, want ErrUnauthenticated", err)
	}
}
