package rpc

import (
	"context"
	"net/http"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
)

// AuthService implements the generated AuthService handler and registers it on
// goslow's Connect mux.
type AuthService struct {
	store *store.Store
	auth  *auth.Service
	cfg   config.Config
}

// NewAuthService builds the AuthService implementation.
func NewAuthService(database *store.Store, authService *auth.Service, cfg config.Config) *AuthService {
	return &AuthService{store: database, auth: authService, cfg: cfg}
}

// Register implements platform.ConnectService.
func (s *AuthService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewAuthServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// RegisterAccount creates an account after validating the registration secret.
func (s *AuthService) RegisterAccount(ctx context.Context, request *connect.Request[wdidv1.RegisterAccountRequest]) (*connect.Response[wdidv1.RegisterAccountResponse], error) {
	user, token, err := s.auth.Register(auth.RegisterRequest{
		Email:           request.Msg.GetEmail(),
		Password:        request.Msg.GetPassword(),
		DisplayName:     request.Msg.GetDisplayName(),
		InviteCode:      request.Msg.GetInviteCode(),
		BootstrapSecret: request.Msg.GetBootstrapSecret(),
	}, time.Now().UTC())
	if err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.RegisterAccountResponse{
		User:  toProtoUser(user),
		Token: token,
	}), nil
}

// Login verifies local credentials and issues a token.
func (s *AuthService) Login(_ context.Context, request *connect.Request[wdidv1.LoginRequest]) (*connect.Response[wdidv1.LoginResponse], error) {
	user, token, err := s.auth.Login(request.Msg.GetEmail(), request.Msg.GetPassword())
	if err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.LoginResponse{
		User:  toProtoUser(user),
		Token: token,
	}), nil
}

// GetAuthConfig reports the enabled login modes without requiring a token.
func (s *AuthService) GetAuthConfig(_ context.Context, _ *connect.Request[wdidv1.GetAuthConfigRequest]) (*connect.Response[wdidv1.GetAuthConfigResponse], error) {
	count, err := s.store.CountUsers()
	if err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.GetAuthConfigResponse{
		LocalLogin:          true,
		RegistrationEnabled: count > 0,
		BootstrapRequired:   count == 0,
		Oidc: &wdidv1.OIDCConfig{
			Enabled:   s.cfg.Zitadel.Enabled,
			IssuerUrl: s.cfg.Zitadel.IssuerURL,
			ClientId:  s.cfg.Zitadel.ClientID,
		},
	}), nil
}

// GetCurrentUser resolves the authenticated caller after goslow has validated
// the bearer token.
func (s *AuthService) GetCurrentUser(ctx context.Context, _ *connect.Request[wdidv1.GetCurrentUserRequest]) (*connect.Response[wdidv1.GetCurrentUserResponse], error) {
	identity, err := s.auth.IdentityFromRequestContext(ctx)
	if err != nil {
		return nil, toConnectError(err)
	}

	user, err := s.store.UserByID(identity.UserID)
	if err != nil {
		return nil, toConnectError(err)
	}

	// The caller's role comes from the verified token, not the stored profile,
	// so the response must report the role that actually authorized the request.
	if len(identity.Roles) > 0 {
		user.Role = domain.Role(identity.Roles[0])
	}

	return connect.NewResponse(&wdidv1.GetCurrentUserResponse{User: toProtoUser(user)}), nil
}

func toProtoUser(user domain.User) *wdidv1.User {
	return &wdidv1.User{
		Id:          user.ID,
		Email:       user.Email,
		DisplayName: user.DisplayName,
		Role:        toProtoRole(user.Role),
		CreatedAt:   timestamppb.New(user.CreatedAt),
	}
}

func toProtoRole(role domain.Role) wdidv1.UserRole {
	switch role {
	case domain.RoleAdmin:
		return wdidv1.UserRole_USER_ROLE_ADMIN
	case domain.RoleUser:
		return wdidv1.UserRole_USER_ROLE_USER
	default:
		return wdidv1.UserRole_USER_ROLE_UNSPECIFIED
	}
}
