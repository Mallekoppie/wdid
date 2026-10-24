package rpc

import (
	"context"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/domain"
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

// backupAdminFromContext resolves the caller and requires the admin role.
// Backups snapshot the whole database, so they are instance-wide and only an
// administrator may read or change them.
func backupAdminFromContext(ctx context.Context, authService *auth.Service) (auth.Identity, error) {
	identity, err := authService.IdentityFromRequestContext(ctx)
	if err != nil {
		return auth.Identity{}, err
	}
	if !identity.HasRole(string(domain.RoleAdmin)) {
		return auth.Identity{}, ErrBackupsAdminOnly
	}
	return identity, nil
}
