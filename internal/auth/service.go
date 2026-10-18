package auth

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"github.com/coreos/go-oidc"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

var (
	// ErrInvalidRegistrationSecret is returned when the sign-up secret is wrong.
	ErrInvalidRegistrationSecret = errors.New("invalid registration secret")
	// ErrInvalidCredentials is returned for an unknown email or wrong password.
	ErrInvalidCredentials = errors.New("invalid email or password")
	// ErrUnauthenticated is returned when a token cannot be verified.
	ErrUnauthenticated = errors.New("unauthenticated")
)

const (
	localIssuer = "wdid-local"
	// OIDCSource marks identities resolved from a Zitadel ID token.
	OIDCSource = "oidc"
	// LocalSource marks identities resolved from a locally issued token.
	LocalSource = "local"
)

// RegisterRequest is the payload for creating the first or a later account.
type RegisterRequest struct {
	Email              string `json:"email"`
	Password           string `json:"password"`
	DisplayName        string `json:"displayName"`
	RegistrationSecret string `json:"registrationSecret"`
}

// Identity is the authenticated caller attached to a request context.
type Identity struct {
	UserID      string
	Email       string
	DisplayName string
	Roles       []string
	Source      string
}

// HasRole reports whether the identity carries the given role.
func (i Identity) HasRole(role string) bool {
	for _, candidate := range i.Roles {
		if candidate == role {
			return true
		}
	}
	return false
}

type identityKey struct{}

// WithIdentity stores the identity on the context.
func WithIdentity(ctx context.Context, identity Identity) context.Context {
	return context.WithValue(ctx, identityKey{}, identity)
}

// IdentityFromContext returns the identity stored by the middleware.
func IdentityFromContext(ctx context.Context) (Identity, bool) {
	identity, ok := ctx.Value(identityKey{}).(Identity)
	return identity, ok
}

// Service handles registration, login and token verification.
type Service struct {
	store *store.Store
	cfg   config.Config

	verifierMu sync.Mutex
	verifier   *oidc.IDTokenVerifier
}

// NewService builds the auth service.
func NewService(database *store.Store, cfg config.Config) *Service {
	return &Service{store: database, cfg: cfg}
}

// Register creates an account after checking the shared registration secret.
// The first account becomes the administrator so a fresh deployment is usable.
func (s *Service) Register(request RegisterRequest, now time.Time) (domain.User, string, error) {
	request.Email = strings.ToLower(strings.TrimSpace(request.Email))
	request.DisplayName = strings.TrimSpace(request.DisplayName)

	if err := domain.ValidateRegistration(request.Email, request.Password, request.DisplayName); err != nil {
		return domain.User{}, "", err
	}

	if subtle.ConstantTimeCompare(
		[]byte(request.RegistrationSecret), []byte(s.cfg.RegistrationSecret),
	) != 1 {
		return domain.User{}, "", ErrInvalidRegistrationSecret
	}

	count, err := s.store.CountUsers()
	if err != nil {
		return domain.User{}, "", err
	}

	role := domain.RoleUser
	if count == 0 {
		role = domain.RoleAdmin
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(request.Password), bcrypt.DefaultCost)
	if err != nil {
		return domain.User{}, "", fmt.Errorf("hash password: %w", err)
	}

	displayName := request.DisplayName
	if displayName == "" {
		displayName = request.Email
	}

	user := domain.User{
		ID:          domain.NewID(),
		Email:       request.Email,
		DisplayName: displayName,
		Role:        role,
		CreatedAt:   now.UTC(),
	}

	// Store the credential before the profile so a created account is always
	// usable for login.
	if err := s.store.SetPasswordHash(user.ID, string(hash)); err != nil {
		return domain.User{}, "", err
	}

	if err := s.store.CreateUser(user); err != nil {
		return domain.User{}, "", err
	}

	token, err := s.issueToken(user)
	if err != nil {
		return domain.User{}, "", err
	}

	return user, token, nil
}

// Login verifies a local password and issues a token.
func (s *Service) Login(email, password string) (domain.User, string, error) {
	user, err := s.store.UserByEmail(email)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return domain.User{}, "", ErrInvalidCredentials
		}
		return domain.User{}, "", err
	}

	hash, err := s.store.PasswordHash(user.ID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return domain.User{}, "", ErrInvalidCredentials
		}
		return domain.User{}, "", err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)); err != nil {
		return domain.User{}, "", ErrInvalidCredentials
	}

	token, err := s.issueToken(user)
	if err != nil {
		return domain.User{}, "", err
	}

	return user, token, nil
}

func (s *Service) issueToken(user domain.User) (string, error) {
	return platform.LocalJwt.NewLocalJwtToken(map[string]interface{}{
		"sub":                user.ID,
		"email":              user.Email,
		"preferred_username": user.DisplayName,
		"roles":              []string{string(user.Role)},
		"iss":                localIssuer,
	})
}

// VerifyToken accepts either a locally issued token or, when Zitadel is
// enabled, an ID token from the configured provider.
func (s *Service) VerifyToken(ctx context.Context, raw string) (Identity, error) {
	if claims, err := platform.LocalJwt.ValidateLocalJwtToken(raw); err == nil {
		return s.identityFromLocalClaims(claims)
	}

	if !s.cfg.Zitadel.Enabled {
		return Identity{}, ErrUnauthenticated
	}

	return s.verifyOIDCToken(ctx, raw)
}

// IdentityFromRequestContext resolves the wdid identity after goslow's auth
// interceptor has accepted the request. Local JWTs expose their claims through
// the platform context; OIDC tokens carry the raw token, which wdid resolves to
// a local account (provisioning it on first login).
func (s *Service) IdentityFromRequestContext(ctx context.Context) (Identity, error) {
	if claims := platform.ClaimsFromContext(ctx); len(claims) > 0 {
		return s.identityFromLocalClaims(claims)
	}

	raw := platform.ClientTokenFromContext(ctx)
	if raw == "" {
		return Identity{}, ErrUnauthenticated
	}

	return s.VerifyToken(ctx, raw)
}

func (s *Service) identityFromLocalClaims(claims map[string]interface{}) (Identity, error) {
	userID, _ := claims["sub"].(string)
	if strings.TrimSpace(userID) == "" {
		return Identity{}, ErrUnauthenticated
	}

	user, err := s.store.UserByID(userID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return Identity{}, ErrUnauthenticated
		}
		return Identity{}, err
	}

	return Identity{
		UserID:      user.ID,
		Email:       user.Email,
		DisplayName: user.DisplayName,
		Roles:       []string{string(user.Role)},
		Source:      LocalSource,
	}, nil
}

func (s *Service) verifyOIDCToken(ctx context.Context, raw string) (Identity, error) {
	verifier, err := s.oidcVerifier(ctx)
	if err != nil {
		return Identity{}, err
	}

	idToken, err := verifier.Verify(ctx, raw)
	if err != nil {
		platform.Log.Warn("OIDC token rejected", zap.Error(err))
		return Identity{}, ErrUnauthenticated
	}

	var claims struct {
		Email             string   `json:"email"`
		Name              string   `json:"name"`
		PreferredUsername string   `json:"preferred_username"`
		Roles             []string `json:"roles"`
	}

	if err := idToken.Claims(&claims); err != nil {
		return Identity{}, ErrUnauthenticated
	}

	email := strings.ToLower(strings.TrimSpace(claims.Email))
	if email == "" {
		return Identity{}, fmt.Errorf("%w: OIDC token has no email claim", ErrUnauthenticated)
	}

	user, err := s.store.UserByEmail(email)
	if errors.Is(err, store.ErrNotFound) {
		displayName := claims.Name
		if strings.TrimSpace(displayName) == "" {
			displayName = claims.PreferredUsername
		}
		user, err = s.provisionOIDCUser(email, displayName, claims.Roles)
	}
	if err != nil {
		return Identity{}, err
	}

	return Identity{
		UserID:      user.ID,
		Email:       user.Email,
		DisplayName: user.DisplayName,
		Roles:       []string{string(user.Role)},
		Source:      OIDCSource,
	}, nil
}

// provisionOIDCUser creates the local account backing a first-time OIDC login.
func (s *Service) provisionOIDCUser(email, displayName string, roles []string) (domain.User, error) {
	role := domain.RoleUser
	if s.cfg.Zitadel.AdminRole != "" {
		for _, candidate := range roles {
			if candidate == s.cfg.Zitadel.AdminRole {
				role = domain.RoleAdmin
				break
			}
		}
	}

	count, err := s.store.CountUsers()
	if err != nil {
		return domain.User{}, err
	}
	if count == 0 {
		role = domain.RoleAdmin
	}

	if strings.TrimSpace(displayName) == "" {
		displayName = email
	}

	user := domain.User{
		ID:          domain.NewID(),
		Email:       email,
		DisplayName: displayName,
		Role:        role,
		CreatedAt:   time.Now().UTC(),
	}

	if err := s.store.CreateUser(user); err != nil {
		if errors.Is(err, store.ErrEmailExists) {
			return s.store.UserByEmail(email)
		}
		return domain.User{}, err
	}

	return user, nil
}

// oidcVerifier discovers the provider lazily so a local-only deployment does
// not depend on Zitadel being reachable at startup.
func (s *Service) oidcVerifier(ctx context.Context) (*oidc.IDTokenVerifier, error) {
	s.verifierMu.Lock()
	defer s.verifierMu.Unlock()

	if s.verifier != nil {
		return s.verifier, nil
	}

	provider, err := oidc.NewProvider(ctx, s.cfg.Zitadel.IssuerURL)
	if err != nil {
		return nil, fmt.Errorf("discover OIDC provider: %w", err)
	}

	oidcConfig := &oidc.Config{ClientID: s.cfg.Zitadel.ClientID}
	if len(s.cfg.Zitadel.AllowedAlgorithms) > 0 {
		oidcConfig.SupportedSigningAlgs = s.cfg.Zitadel.AllowedAlgorithms
	}

	s.verifier = provider.Verifier(oidcConfig)

	return s.verifier, nil
}
