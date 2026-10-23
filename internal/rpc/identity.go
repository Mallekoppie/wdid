package rpc

import (
	"context"

	"github.com/Mallekoppie/wdid/internal/auth"
)

// userIDFromContext resolves the account from goslow's verified token. Request
// fields never supply identity.
func userIDFromContext(ctx context.Context, authService *auth.Service) (string, error) {
	identity, err := authService.IdentityFromRequestContext(ctx)
	if err != nil {
		return "", err
	}
	return identity.UserID, nil
}
