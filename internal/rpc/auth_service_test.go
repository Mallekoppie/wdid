package rpc_test

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"
	"github.com/Mallekoppie/goslow/platform"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/invite"
	"github.com/Mallekoppie/wdid/internal/rpc"
	"github.com/Mallekoppie/wdid/internal/store"
)

const (
	testBootstrapSecret = "test-bootstrap-secret"
	testPassword        = "longenough1"
)

func testConfig(t *testing.T) config.Config {
	t.Helper()

	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid-rpc.db"),
		AllowedOrigins:       []string{"http://127.0.0.1:5173"},
		BootstrapSecret:      testBootstrapSecret,
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

func newAuthHandlerWithConfig(t *testing.T, cfg config.Config) (http.Handler, *store.Store) {
	t.Helper()

	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		_ = database.Close()
	})

	authService := auth.NewService(database, cfg)
	application, err := platform.NewApplicationHandler(platform.ApplicationServerOptions{
		Services: []platform.ConnectService{
			rpc.NewAuthService(database, authService, cfg),
		},
		ServiceNames: []string{config.AuthServiceName},
	})
	if err != nil {
		t.Fatalf("build application handler: %v", err)
	}

	return application, database
}

func newAuthHandler(t *testing.T) (http.Handler, *store.Store) {
	t.Helper()
	return newAuthHandlerWithConfig(t, testConfig(t))
}

func newAuthServer(t *testing.T) (*httptest.Server, *store.Store) {
	t.Helper()

	handler, database := newAuthHandler(t)
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)

	return server, database
}

func authClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.AuthServiceClient {
	return wdidv1connect.NewAuthServiceClient(server.Client(), server.URL, options...)
}

func registerBootstrap(t *testing.T, client wdidv1connect.AuthServiceClient) *wdidv1.RegisterAccountResponse {
	t.Helper()

	response, err := client.RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:           "admin@example.com",
		Password:        testPassword,
		DisplayName:     "Admin",
		BootstrapSecret: testBootstrapSecret,
	}))
	if err != nil {
		t.Fatalf("bootstrap account: %v", err)
	}
	return response.Msg
}

func createInvite(t *testing.T, database *store.Store, email string) string {
	t.Helper()

	code, err := invite.New()
	if err != nil {
		t.Fatalf("generate invite code: %v", err)
	}
	record := domain.Invite{ID: domain.NewID(), Email: email, CreatedAt: time.Now().UTC()}
	if err := database.CreateInvite(record, invite.Hash(code)); err != nil {
		t.Fatalf("create invite: %v", err)
	}
	return code
}

func TestAuthServiceConnectFlow(t *testing.T) {
	server, _ := newAuthServer(t)
	client := authClient(server)

	configResponse, err := client.GetAuthConfig(context.Background(), connect.NewRequest(&wdidv1.GetAuthConfigRequest{}))
	if err != nil {
		t.Fatalf("get auth config: %v", err)
	}
	if !configResponse.Msg.GetLocalLogin() || !configResponse.Msg.GetBootstrapRequired() {
		t.Fatalf("initial auth config = %v, want local login and bootstrap required", configResponse.Msg)
	}
	if configResponse.Msg.GetRegistrationEnabled() {
		t.Fatal("invite registration must wait for the first account")
	}

	_, err = client.GetCurrentUser(context.Background(), connect.NewRequest(&wdidv1.GetCurrentUserRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("unauthenticated GetCurrentUser code = %v, want unauthenticated", connect.CodeOf(err))
	}

	registration := registerBootstrap(t, client)
	if registration.GetUser().GetRole() != wdidv1.UserRole_USER_ROLE_ADMIN {
		t.Fatalf("first user role = %v, want admin", registration.GetUser().GetRole())
	}
	if registration.GetToken() == "" {
		t.Fatal("registration returned an empty token")
	}

	current, err := client.GetCurrentUser(context.Background(), withBearer(&wdidv1.GetCurrentUserRequest{}, registration.GetToken()))
	if err != nil {
		t.Fatalf("get current user: %v", err)
	}
	if current.Msg.GetUser().GetEmail() != "admin@example.com" {
		t.Fatalf("current user email = %q", current.Msg.GetUser().GetEmail())
	}

	// The token's roles claim, not the stored profile, decides the reported
	// role: the same account presents a user-role token and must read as user.
	userToken, err := platform.LocalJwt.NewLocalJwtToken(map[string]interface{}{
		"sub":                registration.GetUser().GetId(),
		"email":              "admin@example.com",
		"preferred_username": "Admin",
		"roles":              []string{string(domain.RoleUser)},
		"iss":                "wdid-local",
	})
	if err != nil {
		t.Fatalf("issue user-role token: %v", err)
	}
	demoted, err := client.GetCurrentUser(context.Background(), withBearer(&wdidv1.GetCurrentUserRequest{}, userToken))
	if err != nil {
		t.Fatalf("get current user with user-role token: %v", err)
	}
	if demoted.Msg.GetUser().GetRole() != wdidv1.UserRole_USER_ROLE_USER {
		t.Fatalf("reported role = %v, want user", demoted.Msg.GetUser().GetRole())
	}

	login, err := client.Login(context.Background(), connect.NewRequest(&wdidv1.LoginRequest{
		Email:    "ADMIN@example.com",
		Password: testPassword,
	}))
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if login.Msg.GetUser().GetId() != registration.GetUser().GetId() {
		t.Fatalf("login user = %q, want %q", login.Msg.GetUser().GetId(), registration.GetUser().GetId())
	}

	configResponse, err = client.GetAuthConfig(context.Background(), connect.NewRequest(&wdidv1.GetAuthConfigRequest{}))
	if err != nil {
		t.Fatalf("get auth config after bootstrap: %v", err)
	}
	if configResponse.Msg.GetBootstrapRequired() || !configResponse.Msg.GetRegistrationEnabled() {
		t.Fatalf("post-bootstrap auth config = %v, want invite registration enabled", configResponse.Msg)
	}
}

func TestAuthServiceRejectsBadBootstrapSecret(t *testing.T) {
	server, _ := newAuthServer(t)
	client := authClient(server)

	_, err := client.RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:           "admin@example.com",
		Password:        testPassword,
		BootstrapSecret: "wrong-secret-value",
	}))
	if connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("code = %v, want permission denied", connect.CodeOf(err))
	}
}

func TestAuthServiceRequiresInviteAfterBootstrap(t *testing.T) {
	server, _ := newAuthServer(t)
	client := authClient(server)
	registerBootstrap(t, client)

	_, err := client.RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:           "second@example.com",
		Password:        testPassword,
		BootstrapSecret: testBootstrapSecret,
	}))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
	}
}

func TestAuthServiceInviteRegistration(t *testing.T) {
	server, database := newAuthServer(t)
	client := authClient(server)
	registerBootstrap(t, client)

	code := createInvite(t, database, "new@example.com")

	registration, err := client.RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:       "NEW@example.com",
		Password:    testPassword,
		DisplayName: "New User",
		InviteCode:  strings.ToLower(code),
	}))
	if err != nil {
		t.Fatalf("invite registration: %v", err)
	}
	if registration.Msg.GetUser().GetRole() != wdidv1.UserRole_USER_ROLE_USER {
		t.Fatalf("invited role = %v, want user", registration.Msg.GetUser().GetRole())
	}

	login, err := client.Login(context.Background(), connect.NewRequest(&wdidv1.LoginRequest{
		Email:    "new@example.com",
		Password: testPassword,
	}))
	if err != nil {
		t.Fatalf("login invited user: %v", err)
	}
	if login.Msg.GetUser().GetId() != registration.Msg.GetUser().GetId() {
		t.Fatalf("login user = %q, want %q", login.Msg.GetUser().GetId(), registration.Msg.GetUser().GetId())
	}

	_, err = client.RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:      "another@example.com",
		Password:   testPassword,
		InviteCode: code,
	}))
	if connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("reused invite code = %v, want permission denied", connect.CodeOf(err))
	}
}

func TestAuthServiceInviteRejectsAnotherEmail(t *testing.T) {
	server, database := newAuthServer(t)
	client := authClient(server)
	registerBootstrap(t, client)

	code := createInvite(t, database, "new@example.com")

	_, err := client.RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:      "someone@example.com",
		Password:   testPassword,
		InviteCode: code,
	}))
	if connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("code = %v, want permission denied", connect.CodeOf(err))
	}
}

func TestAuthServiceHealthIsPublic(t *testing.T) {
	server, _ := newAuthServer(t)
	request, err := http.NewRequest(http.MethodPost, server.URL+"/grpc.health.v1.Health/Check", strings.NewReader(`{"service":"wdid.v1.AuthService"}`))
	if err != nil {
		t.Fatalf("build health request: %v", err)
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Connect-Protocol-Version", "1")

	response, err := server.Client().Do(request)
	if err != nil {
		t.Fatalf("health request: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		t.Fatalf("health status = %d, want 200", response.StatusCode)
	}
	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatalf("read health response: %v", err)
	}
	if !strings.Contains(string(body), "SERVING") {
		t.Fatalf("health body = %q, want SERVING", body)
	}
}

func TestAuthServiceServesGRPCWeb(t *testing.T) {
	server, _ := newAuthServer(t)
	client := authClient(server, connect.WithGRPCWeb())

	response, err := client.GetAuthConfig(context.Background(), connect.NewRequest(&wdidv1.GetAuthConfigRequest{}))
	if err != nil {
		t.Fatalf("gRPC-Web GetAuthConfig: %v", err)
	}
	if !response.Msg.GetLocalLogin() {
		t.Fatal("gRPC-Web response did not include local login")
	}
}

func TestAuthServiceServesNativeGRPC(t *testing.T) {
	handler, _ := newAuthHandler(t)
	server := httptest.NewUnstartedServer(handler)
	server.EnableHTTP2 = true
	server.StartTLS()
	t.Cleanup(server.Close)

	client := authClient(server, connect.WithGRPC())
	response, err := client.GetAuthConfig(context.Background(), connect.NewRequest(&wdidv1.GetAuthConfigRequest{}))
	if err != nil {
		t.Fatalf("native gRPC GetAuthConfig: %v", err)
	}
	if !response.Msg.GetLocalLogin() {
		t.Fatal("native gRPC response did not include local login")
	}
}

func TestAuthServiceReportsOIDCConfig(t *testing.T) {
	cfg := testConfig(t)
	cfg.Zitadel = config.Zitadel{
		Enabled:           true,
		IssuerURL:         "http://zitadel.local:8080",
		ClientID:          "wdid-client",
		AllowedAlgorithms: []string{"RS256"},
	}

	handler, _ := newAuthHandlerWithConfig(t, cfg)
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)

	response, err := authClient(server).GetAuthConfig(context.Background(), connect.NewRequest(&wdidv1.GetAuthConfigRequest{}))
	if err != nil {
		t.Fatalf("get auth config: %v", err)
	}
	if !response.Msg.GetOidc().GetEnabled() {
		t.Fatal("OIDC must be reported as enabled")
	}
	if response.Msg.GetOidc().GetIssuerUrl() != cfg.Zitadel.IssuerURL || response.Msg.GetOidc().GetClientId() != cfg.Zitadel.ClientID {
		t.Fatalf("OIDC config = %v, want issuer and client id", response.Msg.GetOidc())
	}
	if !response.Msg.GetLocalLogin() {
		t.Fatal("local login must stay available with OIDC")
	}
}

func withBearer[T any](message *T, token string) *connect.Request[T] {
	request := connect.NewRequest(message)
	request.Header().Set("Authorization", "Bearer "+token)
	return request
}
