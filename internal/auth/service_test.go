package auth_test

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/goslow/platform"

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

	service, database, _ := newServiceConfig(t, nil)
	return service, database
}

// newServiceConfig lets a test customize the configuration before the store
// configures the platform. Tests that exercise OIDC enable Zitadel here.
func newServiceConfig(t *testing.T, mutate func(*config.Config)) (*auth.Service, *store.Store, config.Config) {
	t.Helper()

	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid-auth.db"),
		AuthMode:             config.AuthModeServer,
		BootstrapSecret:      testBootstrapSecret,
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}
	if mutate != nil {
		mutate(&cfg)
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

	return auth.NewService(database, cfg), database, cfg
}

// newLocalService builds the single-user local-mode service. It has no
// bootstrap secret: the first local run creates its one account from a username.
func newLocalService(t *testing.T) (*auth.Service, *store.Store, config.Config) {
	t.Helper()

	return newServiceConfig(t, func(cfg *config.Config) {
		cfg.AuthMode = config.AuthModeLocal
		cfg.BootstrapSecret = ""
	})
}

func registerLocal(t *testing.T, service *auth.Service, username, password string) (domain.User, string) {
	t.Helper()

	user, token, err := service.Register(auth.RegisterRequest{
		Username: username,
		Password: password,
	}, time.Now().UTC())
	if err != nil {
		t.Fatalf("register local account: %v", err)
	}
	return user, token
}

func withZitadel(cfg *config.Config) {
	cfg.Zitadel = config.Zitadel{
		Enabled:           true,
		IssuerURL:         "http://zitadel.local:8080",
		ClientID:          "wdid-client",
		AllowedAlgorithms: []string{"RS256"},
	}
}

// localToken signs a wdid local token carrying the given roles. Tests use it
// to prove that the token, not the stored profile, decides the role.
func localToken(t *testing.T, user domain.User, roles []string) string {
	t.Helper()

	token, err := platform.LocalJwt.NewLocalJwtToken(map[string]interface{}{
		"sub":                user.ID,
		"email":              user.Email,
		"preferred_username": user.DisplayName,
		"roles":              roles,
		"iss":                "wdid-local",
	})
	if err != nil {
		t.Fatalf("issue local token: %v", err)
	}
	return token
}

// authorizeLocal drives the real goslow authorizer, so the identity reaches the
// service through the same context path as a served request.
func authorizeLocal(t *testing.T, cfg config.Config, token string) (context.Context, error) {
	t.Helper()

	platformConfig := cfg.PlatformConfig()
	authorizer, err := platform.NewAuthorizer(platform.AuthSettingsFromConfig(&platformConfig))
	if err != nil {
		t.Fatalf("build authorizer: %v", err)
	}
	rule, err := authorizer.ResolveAccessRule(platform.AuthLocalJWT, nil)
	if err != nil {
		t.Fatalf("resolve access rule: %v", err)
	}
	return authorizer.Authorize(context.Background(), rule, platform.BearerCredential(token))
}

func localIdentity(t *testing.T, service *auth.Service, cfg config.Config, token string) auth.Identity {
	t.Helper()

	ctx, err := authorizeLocal(t, cfg, token)
	if err != nil {
		t.Fatalf("authorize local token: %v", err)
	}
	identity, err := service.IdentityFromRequestContext(ctx)
	if err != nil {
		t.Fatalf("resolve identity: %v", err)
	}
	return identity
}

// fakeIDTokenVerifier stands in for the IdP: goslow's authorizer calls it and
// trusts the claims it returns.
type fakeIDTokenVerifier struct {
	claims map[string]interface{}
}

func (f fakeIDTokenVerifier) Verify(context.Context, string) (map[string]interface{}, error) {
	return f.claims, nil
}

func authorizeOIDC(t *testing.T, claims map[string]interface{}) context.Context {
	t.Helper()

	authorizer, err := platform.NewAuthorizer(
		platform.AuthSettings{
			OAuth: platform.OAuthSettings{
				Enabled:           true,
				ClientID:          "wdid-client",
				AllowedAlgorithms: []string{"RS256"},
				RolesClaim:        "roles",
			},
		},
		platform.WithIDTokenVerifierFactory(
			func(context.Context) (platform.IDTokenVerifier, error) {
				return fakeIDTokenVerifier{claims: claims}, nil
			},
		),
	)
	if err != nil {
		t.Fatalf("build OIDC authorizer: %v", err)
	}
	rule, err := authorizer.ResolveAccessRule(platform.AuthOAuth, nil)
	if err != nil {
		t.Fatalf("resolve OIDC access rule: %v", err)
	}
	ctx, err := authorizer.Authorize(context.Background(), rule, platform.BearerCredential("fake-id-token"))
	if err != nil {
		t.Fatalf("authorize OIDC token: %v", err)
	}
	return ctx
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
	service, _, cfg := newServiceConfig(t, nil)

	first, token := bootstrap(t, service)
	if first.Role != domain.RoleAdmin {
		t.Fatalf("first role = %q, want admin", first.Role)
	}

	identity := localIdentity(t, service, cfg, token)
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

func TestIdentityFromRequestContextRejectsMissingIdentity(t *testing.T) {
	service, _ := newService(t)

	if _, err := service.IdentityFromRequestContext(context.Background()); !errors.Is(err, auth.ErrUnauthenticated) {
		t.Fatalf("error = %v, want ErrUnauthenticated", err)
	}
}

func TestLocalAuthorizerRejectsGarbageToken(t *testing.T) {
	_, _, cfg := newServiceConfig(t, nil)

	if _, err := authorizeLocal(t, cfg, "not-a-token"); err == nil {
		t.Fatal("authorize garbage token succeeded, want an error")
	}
}

// TestLocalRoleComesFromTokenNotTheStoredProfile pins the rule that the token's
// roles claim decides the caller's role.
func TestLocalRoleComesFromTokenNotTheStoredProfile(t *testing.T) {
	service, database, cfg := newServiceConfig(t, nil)
	admin, _ := bootstrap(t, service)

	_, code := createInvite(t, database, "member@example.com")
	member, _, err := registerWithInvite(service, "member@example.com", code)
	if err != nil {
		t.Fatalf("register member: %v", err)
	}

	demoted := localIdentity(t, service, cfg, localToken(t, admin, []string{string(domain.RoleUser)}))
	if demoted.HasRole(string(domain.RoleAdmin)) {
		t.Fatalf("roles = %v, want the token's user role", demoted.Roles)
	}

	promoted := localIdentity(t, service, cfg, localToken(t, member, []string{string(domain.RoleAdmin)}))
	if !promoted.HasRole(string(domain.RoleAdmin)) {
		t.Fatalf("roles = %v, want the token's admin role", promoted.Roles)
	}
}

func TestLocalTokenForUnknownAccountIsRejected(t *testing.T) {
	service, _, cfg := newServiceConfig(t, nil)

	ghost := domain.User{ID: domain.NewID(), Email: "ghost@example.com", DisplayName: "Ghost"}
	ctx, err := authorizeLocal(t, cfg, localToken(t, ghost, []string{string(domain.RoleAdmin)}))
	if err != nil {
		t.Fatalf("authorize token: %v", err)
	}

	if _, err := service.IdentityFromRequestContext(ctx); !errors.Is(err, auth.ErrUnauthenticated) {
		t.Fatalf("error = %v, want ErrUnauthenticated", err)
	}
}

// TestLocalTokenWithoutIssuerIsRejected covers the issuer split: goslow accepts
// the signature, but wdid cannot tell local from OIDC and refuses it.
func TestLocalTokenWithoutIssuerIsRejected(t *testing.T) {
	service, _, cfg := newServiceConfig(t, nil)
	user, _ := bootstrap(t, service)

	token, err := platform.LocalJwt.NewLocalJwtToken(map[string]interface{}{
		"sub":   user.ID,
		"roles": []string{string(domain.RoleAdmin)},
	})
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	ctx, err := authorizeLocal(t, cfg, token)
	if err != nil {
		t.Fatalf("authorize token: %v", err)
	}

	if _, err := service.IdentityFromRequestContext(ctx); !errors.Is(err, auth.ErrUnauthenticated) {
		t.Fatalf("error = %v, want ErrUnauthenticated", err)
	}
}

func TestOIDCFirstLoginProvisionsAccountWithTokenRole(t *testing.T) {
	service, database, _ := newServiceConfig(t, withZitadel)

	identity, err := service.IdentityFromRequestContext(authorizeOIDC(t, map[string]interface{}{
		"iss":   "http://zitadel.local:8080",
		"email": "oidc@example.com",
		"name":  "OIDC User",
		"roles": []interface{}{"admin"},
	}))
	if err != nil {
		t.Fatalf("resolve identity: %v", err)
	}
	if identity.Source != auth.OIDCSource {
		t.Fatalf("source = %q, want %q", identity.Source, auth.OIDCSource)
	}
	if !identity.HasRole(string(domain.RoleAdmin)) {
		t.Fatalf("roles = %v, want admin", identity.Roles)
	}

	stored, err := database.UserByID(identity.UserID)
	if err != nil {
		t.Fatalf("read provisioned user: %v", err)
	}
	if stored.Role != domain.RoleAdmin {
		t.Fatalf("stored role = %q, want admin", stored.Role)
	}
	if stored.Email != "oidc@example.com" || stored.DisplayName != "OIDC User" {
		t.Fatalf("stored user = %+v, want email and name from claims", stored)
	}
}

// TestOIDCFirstLoginWithoutAdminClaimIsNotAdmin covers the strict rule: even the
// first account is not an admin unless its token says so.
func TestOIDCFirstLoginWithoutAdminClaimIsNotAdmin(t *testing.T) {
	service, database, _ := newServiceConfig(t, withZitadel)

	identity, err := service.IdentityFromRequestContext(authorizeOIDC(t, map[string]interface{}{
		"iss":   "http://zitadel.local:8080",
		"email": "first@example.com",
		"roles": []interface{}{"user"},
	}))
	if err != nil {
		t.Fatalf("resolve identity: %v", err)
	}
	if identity.HasRole(string(domain.RoleAdmin)) {
		t.Fatalf("roles = %v, want user", identity.Roles)
	}

	stored, err := database.UserByID(identity.UserID)
	if err != nil {
		t.Fatalf("read provisioned user: %v", err)
	}
	if stored.Role != domain.RoleUser {
		t.Fatalf("stored role = %q, want user", stored.Role)
	}
}

func TestOIDCMissingEmailIsRejected(t *testing.T) {
	service, _, _ := newServiceConfig(t, withZitadel)

	_, err := service.IdentityFromRequestContext(authorizeOIDC(t, map[string]interface{}{
		"iss":   "http://zitadel.local:8080",
		"roles": []interface{}{"admin"},
	}))
	if !errors.Is(err, auth.ErrUnauthenticated) {
		t.Fatalf("error = %v, want ErrUnauthenticated", err)
	}
}

func TestLocalSetupCreatesTheOnlyAccountWithoutEmail(t *testing.T) {
	service, database, cfg := newLocalService(t)

	user, token := registerLocal(t, service, "malle", "")
	if user.Username != "malle" {
		t.Fatalf("username = %q, want malle", user.Username)
	}
	if user.Email != "" {
		t.Fatalf("email = %q, want empty for a local account", user.Email)
	}
	if user.Role != domain.RoleAdmin {
		t.Fatalf("role = %q, want admin for the single local account", user.Role)
	}

	count, err := database.CountUsers()
	if err != nil {
		t.Fatalf("count users: %v", err)
	}
	if count != 1 {
		t.Fatalf("users = %d, want 1", count)
	}

	identity := localIdentity(t, service, cfg, token)
	if identity.UserID != user.ID || identity.Username != "malle" {
		t.Fatalf("identity = %+v, want the local account with its username", identity)
	}
}

func TestLocalPasswordlessAccountSignsInWithoutAPassword(t *testing.T) {
	service, _, _ := newLocalService(t)
	registered, _ := registerLocal(t, service, "malle", "")

	loggedIn, token, err := service.LoginLocal("  MALLE ", "")
	if err != nil {
		t.Fatalf("passwordless login: %v", err)
	}
	if loggedIn.ID != registered.ID {
		t.Fatalf("login user = %q, want %q", loggedIn.ID, registered.ID)
	}
	if token == "" {
		t.Fatal("passwordless login returned an empty token")
	}
}

func TestLocalPasswordAccountRequiresThePassword(t *testing.T) {
	service, _, _ := newLocalService(t)
	registered, _ := registerLocal(t, service, "malle", testPassword)

	if _, _, err := service.LoginLocal("malle", ""); !errors.Is(err, auth.ErrInvalidCredentials) {
		t.Fatalf("empty password error = %v, want ErrInvalidCredentials", err)
	}
	if _, _, err := service.LoginLocal("malle", "wrong-password"); !errors.Is(err, auth.ErrInvalidCredentials) {
		t.Fatalf("wrong password error = %v, want ErrInvalidCredentials", err)
	}

	loggedIn, token, err := service.LoginLocal("malle", testPassword)
	if err != nil {
		t.Fatalf("password login: %v", err)
	}
	if loggedIn.ID != registered.ID || token == "" {
		t.Fatalf("login = (%q, %q), want the registered account and a token", loggedIn.ID, token)
	}
}

func TestLocalModeCannotCreateASecondAccount(t *testing.T) {
	service, _, _ := newLocalService(t)
	registerLocal(t, service, "malle", "")

	_, _, err := service.Register(auth.RegisterRequest{
		Username: "someone-else",
		Password: testPassword,
	}, time.Now().UTC())
	if !errors.Is(err, auth.ErrLocalAccountExists) {
		t.Fatalf("second account error = %v, want ErrLocalAccountExists", err)
	}
}

func TestLocalUsernameIsRequired(t *testing.T) {
	service, _, _ := newLocalService(t)

	_, _, err := service.Register(auth.RegisterRequest{Password: testPassword}, time.Now().UTC())
	var validation domain.ValidationError
	if !errors.As(err, &validation) || validation.Field != "username" {
		t.Fatalf("error = %v, want a username validation error", err)
	}
}

func TestOIDCRoleComesFromTokenNotTheStoredProfile(t *testing.T) {
	service, _, _ := newServiceConfig(t, withZitadel)
	admin, _ := bootstrap(t, service)

	identity, err := service.IdentityFromRequestContext(authorizeOIDC(t, map[string]interface{}{
		"iss":   "http://zitadel.local:8080",
		"email": admin.Email,
		"roles": []interface{}{"user"},
	}))
	if err != nil {
		t.Fatalf("resolve identity: %v", err)
	}
	if identity.UserID != admin.ID {
		t.Fatalf("identity user = %q, want %q", identity.UserID, admin.ID)
	}
	if identity.HasRole(string(domain.RoleAdmin)) {
		t.Fatalf("roles = %v, want the token's user role", identity.Roles)
	}
}
