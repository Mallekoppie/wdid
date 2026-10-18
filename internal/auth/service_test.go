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
	"github.com/Mallekoppie/wdid/internal/store"
)

const testSecret = "test-registration-secret"

func newService(t *testing.T) *auth.Service {
	t.Helper()

	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid-auth.db"),
		RegistrationSecret:   testSecret,
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

	return auth.NewService(database, cfg)
}

func register(t *testing.T, service *auth.Service, email, password, secret string) (domain.User, string) {
	t.Helper()

	user, token, err := service.Register(auth.RegisterRequest{
		Email:              email,
		Password:           password,
		DisplayName:        "Test User",
		RegistrationSecret: secret,
	}, time.Now().UTC())
	if err != nil {
		t.Fatalf("register %s: %v", email, err)
	}
	return user, token
}

func TestRegisterRejectsBadSecret(t *testing.T) {
	service := newService(t)

	_, _, err := service.Register(auth.RegisterRequest{
		Email:              "dev@example.com",
		Password:           "longenough1",
		RegistrationSecret: "wrong-secret-value",
	}, time.Now().UTC())

	if !errors.Is(err, auth.ErrInvalidRegistrationSecret) {
		t.Fatalf("error = %v, want ErrInvalidRegistrationSecret", err)
	}
}

func TestFirstUserBecomesAdmin(t *testing.T) {
	service := newService(t)

	first, token := register(t, service, "first@example.com", "longenough1", testSecret)
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

	second, _ := register(t, service, "second@example.com", "longenough1", testSecret)
	if second.Role != domain.RoleUser {
		t.Fatalf("second role = %q, want user", second.Role)
	}
}

func TestRegisterRejectsDuplicateEmail(t *testing.T) {
	service := newService(t)
	register(t, service, "dev@example.com", "longenough1", testSecret)

	_, _, err := service.Register(auth.RegisterRequest{
		Email:              "DEV@example.com",
		Password:           "longenough1",
		RegistrationSecret: testSecret,
	}, time.Now().UTC())

	if !errors.Is(err, store.ErrEmailExists) {
		t.Fatalf("error = %v, want ErrEmailExists", err)
	}
}

func TestLogin(t *testing.T) {
	service := newService(t)
	user, _ := register(t, service, "dev@example.com", "longenough1", testSecret)

	loggedIn, token, err := service.Login("DEV@example.com", "longenough1")
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if loggedIn.ID != user.ID {
		t.Fatalf("login user = %q, want %q", loggedIn.ID, user.ID)
	}
	if token == "" {
		t.Fatal("login returned an empty token")
	}

	if _, _, err := service.Login("dev@example.com", "wrong-password"); !errors.Is(err, auth.ErrInvalidCredentials) {
		t.Fatalf("wrong password error = %v, want ErrInvalidCredentials", err)
	}

	if _, _, err := service.Login("missing@example.com", "longenough1"); !errors.Is(err, auth.ErrInvalidCredentials) {
		t.Fatalf("unknown email error = %v, want ErrInvalidCredentials", err)
	}
}

func TestVerifyTokenRejectsGarbage(t *testing.T) {
	service := newService(t)

	if _, err := service.VerifyToken(context.Background(), "not-a-token"); !errors.Is(err, auth.ErrUnauthenticated) {
		t.Fatalf("error = %v, want ErrUnauthenticated", err)
	}
}
