package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"

	"github.com/Mallekoppie/goslow/platform"
)

const (
	defaultHTTPAddr            = "127.0.0.1:8080"
	defaultDBPath              = "./data/wdid.db"
	defaultJWTSigningMethod    = "HS256"
	defaultJWTExpirationMinute = 720
	defaultMaxBlockMinutes     = 240
	defaultAllowedOrigins      = "http://127.0.0.1:5173,http://localhost:5173"
	minBootstrapSecretLen      = 16
	minJWTSecretLen            = 32

	// AuthServiceName is the fully qualified Connect service registered by the
	// service process. It is also used for health and reflection reporting.
	AuthServiceName = "wdid.v1.AuthService"

	// AuthRegisterAccountProcedure is public: a new account needs no token.
	AuthRegisterAccountProcedure = "/wdid.v1.AuthService/RegisterAccount"
	// AuthLoginProcedure is public: login exchanges credentials for a token.
	AuthLoginProcedure = "/wdid.v1.AuthService/Login"
	// AuthConfigProcedure is public: the UI needs to know which login modes exist.
	AuthConfigProcedure = "/wdid.v1.AuthService/GetAuthConfig"
	// AuthCurrentUserProcedure is protected and derives identity from the token.
	AuthCurrentUserProcedure = "/wdid.v1.AuthService/GetCurrentUser"
)

// Zitadel holds the OIDC settings for the initial local Zitadel deployment.
// IssuerURL is the issuer base URL (for example http://zitadel.local:8080),
// not the .well-known discovery document.
type Zitadel struct {
	Enabled           bool
	IssuerURL         string
	ClientID          string
	AllowedAlgorithms []string
	AdminRole         string
}

// Config is the service configuration, loaded from the environment.
type Config struct {
	HTTPAddr             string
	DBPath               string
	AllowedOrigins       []string
	DevMode              bool
	BootstrapSecret      string
	JWTSecret            string
	JWTSigningMethod     string
	JWTExpirationMinutes int64
	MaxBlockMinutes      int
	Zitadel              Zitadel
	// StorageOnly marks commands that open the database without serving
	// requests, so no transport or health configuration is required.
	StorageOnly bool
}

// Load reads the service configuration from the environment and validates it.
func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:             envString("WDID_HTTP_ADDR", defaultHTTPAddr),
		DBPath:               envString("WDID_DB_PATH", defaultDBPath),
		AllowedOrigins:       splitList(envString("WDID_ALLOWED_ORIGINS", defaultAllowedOrigins)),
		DevMode:              envBool("WDID_DEV_MODE", false),
		BootstrapSecret:      os.Getenv("WDID_BOOTSTRAP_SECRET"),
		JWTSecret:            os.Getenv("WDID_JWT_SECRET"),
		JWTSigningMethod:     envString("WDID_JWT_SIGNING_METHOD", defaultJWTSigningMethod),
		JWTExpirationMinutes: int64(envInt("WDID_JWT_EXPIRATION_MINUTES", defaultJWTExpirationMinute)),
		MaxBlockMinutes:      envInt("WDID_MAX_BLOCK_MINUTES", defaultMaxBlockMinutes),
		Zitadel: Zitadel{
			Enabled:           envBool("WDID_ZITADEL_ENABLED", false),
			IssuerURL:         strings.TrimRight(envString("WDID_ZITADEL_ISSUER_URL", ""), "/"),
			ClientID:          envString("WDID_ZITADEL_CLIENT_ID", ""),
			AllowedAlgorithms: splitList(envString("WDID_ZITADEL_ALLOWED_ALGORITHMS", "RS256")),
			AdminRole:         envString("WDID_ZITADEL_ADMIN_ROLE", "wdid-admins"),
		},
	}

	if err := cfg.Validate(); err != nil {
		return Config{}, err
	}

	return cfg, nil
}

// LoadStorage reads only the database location. CLI commands that inspect or
// seed the database do not need the serving secrets.
func LoadStorage() Config {
	return Config{DBPath: envString("WDID_DB_PATH", defaultDBPath), StorageOnly: true}
}

// Validate enforces the configuration invariants required to start the service.
func (c Config) Validate() error {
	var problems []string

	if strings.TrimSpace(c.HTTPAddr) == "" {
		problems = append(problems, "WDID_HTTP_ADDR must not be empty")
	}
	if strings.TrimSpace(c.DBPath) == "" {
		problems = append(problems, "WDID_DB_PATH must not be empty")
	}
	for _, origin := range c.AllowedOrigins {
		if err := validateOrigin(origin); err != nil {
			problems = append(problems, fmt.Sprintf("WDID_ALLOWED_ORIGINS entry %q is invalid: %v", origin, err))
		}
	}
	if len(c.BootstrapSecret) < minBootstrapSecretLen {
		problems = append(problems,
			fmt.Sprintf("WDID_BOOTSTRAP_SECRET must be at least %d characters", minBootstrapSecretLen))
	}
	if len(c.JWTSecret) < minJWTSecretLen {
		problems = append(problems,
			fmt.Sprintf("WDID_JWT_SECRET must be at least %d characters", minJWTSecretLen))
	}
	switch c.JWTSigningMethod {
	case "HS256", "HS384", "HS512":
	default:
		problems = append(problems, "WDID_JWT_SIGNING_METHOD must be HS256, HS384 or HS512")
	}
	if c.JWTExpirationMinutes <= 0 {
		problems = append(problems, "WDID_JWT_EXPIRATION_MINUTES must be greater than zero")
	}
	if c.MaxBlockMinutes <= 0 {
		problems = append(problems, "WDID_MAX_BLOCK_MINUTES must be greater than zero")
	}
	if c.Zitadel.Enabled {
		if strings.TrimSpace(c.Zitadel.IssuerURL) == "" {
			problems = append(problems, "WDID_ZITADEL_ISSUER_URL is required when Zitadel is enabled")
		}
		if strings.TrimSpace(c.Zitadel.ClientID) == "" {
			problems = append(problems, "WDID_ZITADEL_CLIENT_ID is required when Zitadel is enabled")
		}
		if len(c.Zitadel.AllowedAlgorithms) == 0 {
			problems = append(problems, "WDID_ZITADEL_ALLOWED_ALGORITHMS must list at least one algorithm")
		}
	}

	if len(problems) > 0 {
		return errors.New(strings.Join(problems, "; "))
	}

	return nil
}

// PlatformConfig translates the service configuration into goslow's platform
// configuration.
//
// Local JWT issuance is always enabled so the initial local-user login works.
// Zitadel adds goslow's OAuth verifier, which lets Connect and HTTP routes use
// AuthLocalOrOIDC. A local-only deployment uses AuthLocalJWT so goslow does not
// require an OAuth provider that is not configured.
func (c Config) PlatformConfig() platform.Config {
	var pc platform.Config

	pc.Log.Level = "info"
	pc.Log.FileLoggingEnabled = false
	pc.Log.FilePath = "./wdid.log"
	pc.Log.MaxSize = 1024
	pc.Log.MaxBackups = 3
	pc.Log.MaxAge = 14
	pc.Component.ComponentName = "wdid"

	pc.HTTP.Server.ListeningAddress = c.HTTPAddr
	pc.HTTP.Server.AllowedOrigins = append([]string(nil), c.AllowedOrigins...)

	pc.Grpc.Server.ListeningAddress = c.HTTPAddr
	pc.Grpc.Server.AllowedOrigins = append([]string(nil), c.AllowedOrigins...)
	pc.Grpc.Server.Auth = platform.AuthLocalJWT
	pc.Grpc.Server.HealthEnabled = !c.StorageOnly
	pc.Grpc.Server.ReflectionEnabled = c.DevMode && !c.StorageOnly
	pc.Grpc.Server.StreamTimeoutSeconds = 0
	pc.Grpc.Server.MaxReceiveMessageBytes = 4 << 20

	pc.Auth.Server.UnauthenticatedPaths = []string{
		"GET /healthz",
		"/grpc.health.v1.Health/Check",
		"/grpc.health.v1.Health/Watch",
		AuthRegisterAccountProcedure,
		AuthLoginProcedure,
		AuthConfigProcedure,
	}

	pc.Database.BoltDB.Enabled = true
	pc.Database.BoltDB.FileName = c.DBPath

	pc.Auth.Server.LocalJwt.Enabled = true
	pc.Auth.Server.LocalJwt.JwtSigningKey = c.JWTSecret
	pc.Auth.Server.LocalJwt.JwtSigningMethod = c.JWTSigningMethod
	pc.Auth.Server.LocalJwt.JwtExpiration = c.JWTExpirationMinutes

	if c.Zitadel.Enabled {
		pc.Grpc.Server.Auth = platform.AuthLocalOrOIDC
		pc.Auth.Server.OAuth.Enabled = true
		pc.Auth.Server.OAuth.IdpWellKnownURL = c.Zitadel.IssuerURL + "/.well-known/openid-configuration"
		pc.Auth.Server.OAuth.ClientID = c.Zitadel.ClientID
		pc.Auth.Server.OAuth.AllowedAlgorithms = append([]string(nil), c.Zitadel.AllowedAlgorithms...)
		pc.Auth.Server.OAuth.RolesClaim = "roles"
	}

	return pc
}

// validateOrigin accepts an exact http(s) origin. Wildcards, paths, queries and
// fragments are rejected so CORS cannot be opened accidentally.
func validateOrigin(origin string) error {
	trimmed := strings.TrimSpace(origin)
	if trimmed == "" {
		return errors.New("must not be empty")
	}
	if strings.Contains(trimmed, "*") {
		return errors.New("wildcards are not allowed")
	}
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return err
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return errors.New("scheme must be http or https")
	}
	if parsed.Host == "" {
		return errors.New("host is required")
	}
	if parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || parsed.Path != "" {
		return errors.New("must be an origin without credentials, trailing slash, path, query or fragment")
	}
	return nil
}

func envString(key string, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && strings.TrimSpace(value) != "" {
		return strings.TrimSpace(value)
	}
	return fallback
}

func envBool(key string, fallback bool) bool {
	value, ok := os.LookupEnv(key)
	if !ok || strings.TrimSpace(value) == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envInt(key string, fallback int) int {
	value, ok := os.LookupEnv(key)
	if !ok || strings.TrimSpace(value) == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil {
		return fallback
	}
	return parsed
}

func splitList(value string) []string {
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}
