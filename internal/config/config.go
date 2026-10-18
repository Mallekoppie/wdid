package config

import (
	"errors"
	"fmt"
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
	minRegistrationSecretLen   = 16
	minJWTSecretLen            = 32
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
	AllowLocalDevCORS    bool
	RegistrationSecret   string
	JWTSecret            string
	JWTSigningMethod     string
	JWTExpirationMinutes int64
	MaxBlockMinutes      int
	Zitadel              Zitadel
}

// Load reads the service configuration from the environment and validates it.
func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:             envString("WDID_HTTP_ADDR", defaultHTTPAddr),
		DBPath:               envString("WDID_DB_PATH", defaultDBPath),
		AllowLocalDevCORS:    envBool("WDID_ALLOW_LOCAL_DEV_CORS", true),
		RegistrationSecret:   os.Getenv("WDID_REGISTRATION_SECRET"),
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

// Validate enforces the configuration invariants required to start the service.
func (c Config) Validate() error {
	var problems []string

	if strings.TrimSpace(c.HTTPAddr) == "" {
		problems = append(problems, "WDID_HTTP_ADDR must not be empty")
	}
	if strings.TrimSpace(c.DBPath) == "" {
		problems = append(problems, "WDID_DB_PATH must not be empty")
	}
	if len(c.RegistrationSecret) < minRegistrationSecretLen {
		problems = append(problems,
			fmt.Sprintf("WDID_REGISTRATION_SECRET must be at least %d characters", minRegistrationSecretLen))
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
// Local JWT issuance stays enabled so the initial local-user login works.
// Zitadel tokens are verified by internal/auth instead of goslow's OAuth
// middleware: goslow applies both middlewares to any AuthRequired route when
// both are enabled, which would reject local-issued tokens. Keeping one
// verifier that understands both token sources avoids that conflict.
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
	pc.HTTP.Server.AllowCorsForLocalDevelopment = c.AllowLocalDevCORS

	pc.Database.BoltDB.Enabled = true
	pc.Database.BoltDB.FileName = c.DBPath

	pc.Auth.Server.LocalJwt.Enabled = true
	pc.Auth.Server.LocalJwt.JwtSigningKey = c.JWTSecret
	pc.Auth.Server.LocalJwt.JwtSigningMethod = c.JWTSigningMethod
	pc.Auth.Server.LocalJwt.JwtExpiration = c.JWTExpirationMinutes

	return pc
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
