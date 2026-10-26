package auth

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"golang.org/x/crypto/bcrypt"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/invite"
	"github.com/Mallekoppie/wdid/internal/store"
)

var (
	// ErrInvalidBootstrapSecret is returned when the bootstrap secret is wrong.
	ErrInvalidBootstrapSecret = errors.New("invalid bootstrap secret")
	// ErrBootstrapComplete is returned when the first account already exists.
	ErrBootstrapComplete = errors.New("workspace is already bootstrapped")
	// ErrInviteRequired is returned when registration has no invite code.
	ErrInviteRequired = errors.New("an invite code is required")
	// ErrInvalidInvite is returned when an invite code does not exist.
	ErrInvalidInvite = errors.New("invalid invite code")
	// ErrInviteUsed is returned when an invite code has already been redeemed.
	ErrInviteUsed = errors.New("invite code has already been used")
	// ErrInviteEmailMismatch is returned when a code is used for another email.
	ErrInviteEmailMismatch = errors.New("invite code is for a different email")
	// ErrInvalidCredentials is returned for an unknown account or wrong password.
	ErrInvalidCredentials = errors.New("invalid credentials")
	// ErrLocalAccountExists is returned when local mode already has its single
	// account. Local mode can never create a second one.
	ErrLocalAccountExists = errors.New("local mode has exactly one account")
	// ErrLegacyServerDatabase is returned when a local-mode service opens a
	// database that still holds server-mode accounts. The operator must choose
	// server mode explicitly; the service never switches modes by itself.
	ErrLegacyServerDatabase = errors.New("database contains accounts from a server-mode deployment")
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

// RegisterRequest is the payload for creating the first or a later account. The
// first account uses the deployment bootstrap secret; every later account needs
// a single-use invite code.
type RegisterRequest struct {
	// Username creates a local-mode account. Server-mode accounts use Email.
	Username        string
	Email           string
	Password        string
	DisplayName     string
	InviteCode      string
	BootstrapSecret string
}

// Identity is the authenticated caller attached to a request context.
type Identity struct {
	UserID      string
	Username    string
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

// Service handles registration, login and resolving goslow's verified identity
// onto a local account.
type Service struct {
	store *store.Store
	cfg   config.Config
}

// NewService builds the auth service.
func NewService(database *store.Store, cfg config.Config) *Service {
	return &Service{store: database, cfg: cfg}
}

// Register creates an account in the mode the service runs in. Local mode
// creates the single username account; server mode uses the bootstrap secret
// for the first account and an invite for every later one.
func (s *Service) Register(request RegisterRequest, now time.Time) (domain.User, string, error) {
	if s.cfg.LocalMode() {
		return s.registerLocal(request, now)
	}
	return s.registerServer(request, now)
}

// registerLocal creates the one local account. It requires a username and
// accepts an optional password; there is no email, bootstrap secret or invite.
// The account becomes the administrator so instance-wide backups stay usable.
func (s *Service) registerLocal(request RegisterRequest, now time.Time) (domain.User, string, error) {
	request.Username = strings.TrimSpace(request.Username)
	request.DisplayName = strings.TrimSpace(request.DisplayName)

	if err := domain.ValidateLocalRegistration(request.Username, request.Password); err != nil {
		return domain.User{}, "", err
	}

	var hash string
	if request.Password != "" {
		hashed, err := bcrypt.GenerateFromPassword([]byte(request.Password), bcrypt.DefaultCost)
		if err != nil {
			return domain.User{}, "", fmt.Errorf("hash password: %w", err)
		}
		hash = string(hashed)
	}

	displayName := request.DisplayName
	if displayName == "" {
		displayName = request.Username
	}

	user := domain.User{
		ID:          domain.NewID(),
		Username:    request.Username,
		DisplayName: displayName,
		Role:        domain.RoleAdmin,
		CreatedAt:   now.UTC(),
	}

	if err := s.store.CreateLocalUser(user, hash); err != nil {
		if errors.Is(err, store.ErrAlreadyBootstrapped) {
			return domain.User{}, "", ErrLocalAccountExists
		}
		return domain.User{}, "", err
	}

	token, err := s.issueToken(user)
	if err != nil {
		return domain.User{}, "", err
	}

	return user, token, nil
}

// registerServer creates an account in the multi-user deployment: the first
// account needs the deployment bootstrap secret and becomes the administrator,
// and every later account needs a single-use invite code.
func (s *Service) registerServer(request RegisterRequest, now time.Time) (domain.User, string, error) {
	request.Email = strings.ToLower(strings.TrimSpace(request.Email))
	request.DisplayName = strings.TrimSpace(request.DisplayName)

	if err := domain.ValidateRegistration(request.Email, request.Password, request.DisplayName); err != nil {
		return domain.User{}, "", err
	}

	count, err := s.store.CountUsers()
	if err != nil {
		return domain.User{}, "", err
	}

	// Validate the credential before hashing the password, so an unauthorised
	// caller cannot force bcrypt work with garbage input.
	var codeHash string
	if count == 0 {
		if subtle.ConstantTimeCompare(
			[]byte(request.BootstrapSecret), []byte(s.cfg.BootstrapSecret),
		) != 1 {
			return domain.User{}, "", ErrInvalidBootstrapSecret
		}
	} else {
		code := strings.TrimSpace(request.InviteCode)
		if code == "" {
			return domain.User{}, "", ErrInviteRequired
		}
		codeHash = invite.Hash(code)
		if err := s.store.CheckInvite(codeHash, request.Email); err != nil {
			return domain.User{}, "", inviteRegistrationError(err)
		}
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
		CreatedAt:   now.UTC(),
	}

	if count == 0 {
		user.Role = domain.RoleAdmin
		if err := s.store.CreateBootstrapUser(user, string(hash)); err != nil {
			if errors.Is(err, store.ErrAlreadyBootstrapped) {
				return domain.User{}, "", ErrBootstrapComplete
			}
			return domain.User{}, "", err
		}
	} else {
		user.Role = domain.RoleUser
		if _, err := s.store.CreateInvitedUser(user, string(hash), codeHash, now); err != nil {
			return domain.User{}, "", inviteRegistrationError(err)
		}
	}

	token, err := s.issueToken(user)
	if err != nil {
		return domain.User{}, "", err
	}

	return user, token, nil
}

// inviteRegistrationError maps store invite failures onto auth errors.
func inviteRegistrationError(err error) error {
	switch {
	case errors.Is(err, store.ErrNotFound):
		return ErrInvalidInvite
	case errors.Is(err, store.ErrInviteUsed):
		return ErrInviteUsed
	case errors.Is(err, store.ErrInviteEmailMismatch):
		return ErrInviteEmailMismatch
	default:
		return err
	}
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

// LoginLocal signs in the single local account by username. An account without
// a stored password signs in without one; an account with a password verifies
// it exactly like a server login.
func (s *Service) LoginLocal(username, password string) (domain.User, string, error) {
	username = strings.TrimSpace(username)
	if username == "" {
		return domain.User{}, "", ErrInvalidCredentials
	}

	user, err := s.store.UserByUsername(username)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return domain.User{}, "", ErrInvalidCredentials
		}
		return domain.User{}, "", err
	}

	hash, err := s.store.PasswordHash(user.ID)
	switch {
	case errors.Is(err, store.ErrNotFound):
		// Passwordless local account: any supplied password is ignored.
	case err != nil:
		return domain.User{}, "", err
	default:
		if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
			return domain.User{}, "", ErrInvalidCredentials
		}
	}

	token, err := s.issueToken(user)
	if err != nil {
		return domain.User{}, "", err
	}

	return user, token, nil
}

// LocalAccount describes the single local-mode account's login hints.
type LocalAccount struct {
	Username         string
	PasswordRequired bool
}

// LocalAccount returns the local account's username and whether it has a
// password. found is false for a fresh installation that still needs its
// first-run setup. It is the only place the login screen's local hints are
// resolved, so the RPC layer never reaches into the store itself.
func (s *Service) LocalAccount() (LocalAccount, bool, error) {
	user, err := s.store.LocalUser()
	if errors.Is(err, store.ErrNotFound) {
		return LocalAccount{}, false, nil
	}
	if err != nil {
		return LocalAccount{}, false, err
	}

	account := LocalAccount{Username: user.Username}
	_, err = s.store.PasswordHash(user.ID)
	switch {
	case err == nil:
		account.PasswordRequired = true
	case errors.Is(err, store.ErrNotFound):
		// Passwordless local account.
	default:
		return LocalAccount{}, false, err
	}

	return account, true, nil
}

// EnsureLocalModeCompatible fails fast when a local-mode service would attach
// to accounts created by a server-mode deployment. Local mode has exactly one
// username account, so silently choosing an arbitrary legacy email account
// would lose the operator's data. It never switches modes itself; the error
// tells the operator how to opt into server mode. Development mode resolves to
// server mode, so make run, seeding and tests are not blocked.
func EnsureLocalModeCompatible(database *store.Store, cfg config.Config) error {
	if !cfg.LocalMode() {
		return nil
	}

	count, err := database.LegacyServerAccountCount()
	if err != nil {
		return fmt.Errorf("inspect existing accounts: %w", err)
	}
	if count == 0 {
		return nil
	}

	return fmt.Errorf(
		"%w: %d account(s) have no username identity; set WDID_AUTH_MODE=server to keep using this database",
		ErrLegacyServerDatabase,
		count,
	)
}

func (s *Service) issueToken(user domain.User) (string, error) {
	claims := map[string]interface{}{
		"sub":                user.ID,
		"preferred_username": user.DisplayName,
		"roles":              []string{string(user.Role)},
		"iss":                localIssuer,
	}
	if user.Email != "" {
		claims["email"] = user.Email
	}
	if user.Username != "" {
		claims["username"] = user.Username
	}
	return platform.LocalJwt.NewLocalJwtToken(claims)
}

// IdentityFromRequestContext resolves the wdid identity after goslow has
// authorized the request. goslow stores exactly one Identity in the context;
// its issuer records which strategy verified the token. wdid resolves that
// identity onto a local account and always takes the role from the token.
func (s *Service) IdentityFromRequestContext(ctx context.Context) (Identity, error) {
	platformIdentity, ok := platform.IdentityFromContext(ctx)
	if !ok {
		return Identity{}, ErrUnauthenticated
	}

	return s.identityFromPlatform(platformIdentity)
}

func (s *Service) identityFromPlatform(platformIdentity platform.Identity) (Identity, error) {
	if platformIdentity.Issuer == localIssuer {
		return s.identityFromLocalClaims(platformIdentity)
	}

	// Local installs have no OIDC configuration and never accept an external
	// identity provider's token.
	if s.cfg.LocalMode() {
		return Identity{}, ErrUnauthenticated
	}

	if !s.cfg.Zitadel.Enabled {
		return Identity{}, ErrUnauthenticated
	}

	return s.identityFromOIDCClaims(platformIdentity)
}

// identityFromLocalClaims resolves a locally issued token. The account must
// still exist; the role comes from the token's roles claim, not the stored
// profile.
func (s *Service) identityFromLocalClaims(platformIdentity platform.Identity) (Identity, error) {
	userID, _ := platformIdentity.Claims["sub"].(string)
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
		Username:    user.Username,
		Email:       user.Email,
		DisplayName: user.DisplayName,
		Roles:       rolesFor(platformIdentity.Roles),
		Source:      LocalSource,
	}, nil
}

// identityFromOIDCClaims resolves an ID token verified by goslow. The first
// login provisions a local account by email; the role still comes from the
// token, and provisioning only records it.
func (s *Service) identityFromOIDCClaims(platformIdentity platform.Identity) (Identity, error) {
	email, displayName, err := oidcProfile(platformIdentity.Claims)
	if err != nil {
		return Identity{}, err
	}

	role := roleFromRoles(platformIdentity.Roles)

	user, err := s.store.UserByEmail(email)
	if errors.Is(err, store.ErrNotFound) {
		user, err = s.provisionOIDCUser(email, displayName, role)
	}
	if err != nil {
		return Identity{}, err
	}

	return Identity{
		UserID:      user.ID,
		Email:       user.Email,
		DisplayName: user.DisplayName,
		Roles:       []string{string(role)},
		Source:      OIDCSource,
	}, nil
}

// oidcProfile extracts the account keys from verified ID token claims.
func oidcProfile(claims map[string]interface{}) (string, string, error) {
	email := strings.ToLower(strings.TrimSpace(stringClaim(claims, "email")))
	if email == "" {
		return "", "", fmt.Errorf("%w: OIDC token has no email claim", ErrUnauthenticated)
	}

	displayName := strings.TrimSpace(stringClaim(claims, "name"))
	if displayName == "" {
		displayName = strings.TrimSpace(stringClaim(claims, "preferred_username"))
	}

	return email, displayName, nil
}

// roleFromRoles maps goslow's verified roles claim onto a wdid role. Local and
// OIDC tokens both use wdid's role vocabulary, so one rule covers both: an
// admin claim wins, and everything else is a plain user.
func roleFromRoles(roles []string) domain.Role {
	for _, role := range roles {
		if role == string(domain.RoleAdmin) {
			return domain.RoleAdmin
		}
	}

	return domain.RoleUser
}

func rolesFor(roles []string) []string {
	return []string{string(roleFromRoles(roles))}
}

func stringClaim(claims map[string]interface{}, key string) string {
	value, _ := claims[key].(string)
	return value
}

// provisionOIDCUser creates the local account backing a first-time OIDC login.
func (s *Service) provisionOIDCUser(email, displayName string, role domain.Role) (domain.User, error) {
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
