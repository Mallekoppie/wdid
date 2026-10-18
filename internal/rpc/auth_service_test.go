package rpc_test

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"connectrpc.com/connect"
	"github.com/Mallekoppie/goslow/platform"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/rpc"
	"github.com/Mallekoppie/wdid/internal/store"
)

const (
	testRegistrationSecret = "test-registration-secret"
	testPassword           = "longenough1"
)

func newAuthHandler(t *testing.T) http.Handler {
	t.Helper()

	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid-rpc.db"),
		AllowedOrigins:       []string{"http://127.0.0.1:5173"},
		RegistrationSecret:   testRegistrationSecret,
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

	return application
}

func newAuthServer(t *testing.T) *httptest.Server {
	t.Helper()

	server := httptest.NewServer(newAuthHandler(t))
	t.Cleanup(server.Close)

	return server
}

func authClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.AuthServiceClient {
	return wdidv1connect.NewAuthServiceClient(server.Client(), server.URL, options...)
}

func TestAuthServiceConnectFlow(t *testing.T) {
	server := newAuthServer(t)
	client := authClient(server)

	configResponse, err := client.GetAuthConfig(context.Background(), connect.NewRequest(&wdidv1.GetAuthConfigRequest{}))
	if err != nil {
		t.Fatalf("get auth config: %v", err)
	}
	if !configResponse.Msg.GetLocalLogin() || !configResponse.Msg.GetRegistrationEnabled() {
		t.Fatalf("unexpected auth config: %v", configResponse.Msg)
	}

	_, err = client.GetCurrentUser(context.Background(), connect.NewRequest(&wdidv1.GetCurrentUserRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("unauthenticated GetCurrentUser code = %v, want unauthenticated", connect.CodeOf(err))
	}

	registration, err := client.RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:              "dev@example.com",
		Password:           testPassword,
		DisplayName:        "Dev",
		RegistrationSecret: testRegistrationSecret,
	}))
	if err != nil {
		t.Fatalf("register account: %v", err)
	}
	if registration.Msg.GetUser().GetRole() != wdidv1.UserRole_USER_ROLE_ADMIN {
		t.Fatalf("first user role = %v, want admin", registration.Msg.GetUser().GetRole())
	}
	if registration.Msg.GetToken() == "" {
		t.Fatal("registration returned an empty token")
	}

	current, err := client.GetCurrentUser(context.Background(), withBearer(&wdidv1.GetCurrentUserRequest{}, registration.Msg.GetToken()))
	if err != nil {
		t.Fatalf("get current user: %v", err)
	}
	if current.Msg.GetUser().GetEmail() != "dev@example.com" {
		t.Fatalf("current user email = %q", current.Msg.GetUser().GetEmail())
	}

	login, err := client.Login(context.Background(), connect.NewRequest(&wdidv1.LoginRequest{
		Email:    "DEV@example.com",
		Password: testPassword,
	}))
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if login.Msg.GetUser().GetId() != registration.Msg.GetUser().GetId() {
		t.Fatalf("login user = %q, want %q", login.Msg.GetUser().GetId(), registration.Msg.GetUser().GetId())
	}
}

func TestAuthServiceRejectsBadRegistrationSecret(t *testing.T) {
	server := newAuthServer(t)
	client := authClient(server)

	_, err := client.RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:              "dev@example.com",
		Password:           testPassword,
		RegistrationSecret: "wrong-secret-value",
	}))
	if connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("code = %v, want permission denied", connect.CodeOf(err))
	}
}

func TestAuthServiceHealthIsPublic(t *testing.T) {
	server := newAuthServer(t)
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
	server := newAuthServer(t)
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
	server := httptest.NewUnstartedServer(newAuthHandler(t))
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

func withBearer[T any](message *T, token string) *connect.Request[T] {
	request := connect.NewRequest(message)
	request.Header().Set("Authorization", "Bearer "+token)
	return request
}
