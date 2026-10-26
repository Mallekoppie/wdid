package config_test

import (
	"strings"
	"testing"

	"github.com/Mallekoppie/goslow/platform"

	"github.com/Mallekoppie/wdid/internal/config"
)

func setRequiredEnv(t *testing.T) {
	t.Helper()
	t.Setenv("WDID_BOOTSTRAP_SECRET", "test-registration-secret")
	t.Setenv("WDID_JWT_SECRET", strings.Repeat("k", 32))
}

func TestValidateRejectsMissingSecrets(t *testing.T) {
	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:8080",
		DBPath:               "./data/wdid.db",
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected validation error for missing secrets")
	}
}

func TestValidateAcceptsCompleteConfig(t *testing.T) {
	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:8080",
		DBPath:               "./data/wdid.db",
		BootstrapSecret:      "test-registration-secret",
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}

	if err := cfg.Validate(); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoadFromEnvironment(t *testing.T) {
	setRequiredEnv(t)
	t.Setenv("WDID_HTTP_ADDR", "127.0.0.1:9999")
	t.Setenv("WDID_DB_PATH", "/tmp/wdid-config-test.db")
	t.Setenv("WDID_ZITADEL_ENABLED", "true")
	t.Setenv("WDID_ZITADEL_ISSUER_URL", "http://zitadel.local:8080/")
	t.Setenv("WDID_ZITADEL_CLIENT_ID", "wdid-client")
	t.Setenv("WDID_ZITADEL_ALLOWED_ALGORITHMS", "RS256, ES256")
	t.Setenv("WDID_ALLOWED_ORIGINS", "http://127.0.0.1:5173,https://wdid.example")

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	if cfg.HTTPAddr != "127.0.0.1:9999" {
		t.Fatalf("http addr = %q", cfg.HTTPAddr)
	}
	if cfg.Zitadel.IssuerURL != "http://zitadel.local:8080" {
		t.Fatalf("issuer url = %q, want trailing slash trimmed", cfg.Zitadel.IssuerURL)
	}
	if len(cfg.Zitadel.AllowedAlgorithms) != 2 || cfg.Zitadel.AllowedAlgorithms[1] != "ES256" {
		t.Fatalf("algorithms = %v", cfg.Zitadel.AllowedAlgorithms)
	}

	platformConfig := cfg.PlatformConfig()
	if !platformConfig.Database.BoltDB.Enabled {
		t.Fatal("boltdb should be enabled")
	}
	if platformConfig.Database.BoltDB.FileName != cfg.DBPath {
		t.Fatalf("db file = %q, want %q", platformConfig.Database.BoltDB.FileName, cfg.DBPath)
	}
	if !platformConfig.Auth.Server.LocalJwt.Enabled {
		t.Fatal("local JWT should be enabled")
	}
	if platformConfig.Auth.Server.LocalJwt.JwtSigningKey != cfg.JWTSecret {
		t.Fatal("local JWT signing key not mapped")
	}
	if platformConfig.Grpc.Server.Auth != platform.AuthLocalOrOIDC {
		t.Fatalf("grpc auth = %q, want local-or-oidc", platformConfig.Grpc.Server.Auth)
	}
	if !platformConfig.Auth.Server.OAuth.Enabled {
		t.Fatal("goslow OAuth must be enabled when Zitadel is enabled")
	}
	if platformConfig.Auth.Server.OAuth.IdpWellKnownURL != "http://zitadel.local:8080/.well-known/openid-configuration" {
		t.Fatalf("well-known url = %q", platformConfig.Auth.Server.OAuth.IdpWellKnownURL)
	}
	if len(platformConfig.HTTP.Server.AllowedOrigins) != 2 {
		t.Fatalf("allowed origins = %v", platformConfig.HTTP.Server.AllowedOrigins)
	}
	public := make(map[string]struct{}, len(platformConfig.Auth.Server.UnauthenticatedPaths))
	for _, path := range platformConfig.Auth.Server.UnauthenticatedPaths {
		public[path] = struct{}{}
	}
	if _, ok := public[config.AuthRegisterAccountProcedure]; !ok {
		t.Fatalf("register procedure missing from public paths: %v", platformConfig.Auth.Server.UnauthenticatedPaths)
	}
}

func TestLoadIgnoresTheRetiredEnvironmentAIKey(t *testing.T) {
	setRequiredEnv(t)
	// The AI key is per user and stored in Settings. A leftover deployment
	// variable must neither configure generation nor fail startup.
	t.Setenv("WDID_OPENAI_API_KEY", "sk-test-key")

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	// The platform configuration has no field for the key, so it cannot leak
	// into the service's transport or logging configuration.
	platformConfig := cfg.PlatformConfig()
	if platformConfig.HTTP.Server.ListeningAddress != cfg.HTTPAddr {
		t.Fatalf("http address = %q", platformConfig.HTTP.Server.ListeningAddress)
	}
}

func TestPlatformConfigLocalOnlyUsesLocalJWT(t *testing.T) {
	setRequiredEnv(t)
	// make exports WDID_DEV_MODE=true for local runs; this case asserts the
	// non-development configuration, so opt out explicitly.
	t.Setenv("WDID_DEV_MODE", "false")

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	platformConfig := cfg.PlatformConfig()
	if platformConfig.Grpc.Server.Auth != platform.AuthLocalJWT {
		t.Fatalf("grpc auth = %q, want local-jwt", platformConfig.Grpc.Server.Auth)
	}
	if platformConfig.Auth.Server.OAuth.Enabled {
		t.Fatal("oauth must stay disabled without Zitadel")
	}
	if !platformConfig.Grpc.Server.HealthEnabled {
		t.Fatal("connect health should be enabled")
	}
	if platformConfig.Grpc.Server.ReflectionEnabled {
		t.Fatal("reflection must be opt-in")
	}
}

func TestValidateRejectsWildcardOrigin(t *testing.T) {
	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:8080",
		DBPath:               "./data/wdid.db",
		AllowedOrigins:       []string{"*"},
		BootstrapSecret:      "test-registration-secret",
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected wildcard origin to be rejected")
	}
}
