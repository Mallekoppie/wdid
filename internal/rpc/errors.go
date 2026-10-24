package rpc

import (
	"errors"

	"connectrpc.com/connect"
	"github.com/Mallekoppie/goslow/platform"
	"go.uber.org/zap"
	"google.golang.org/genproto/googleapis/rpc/errdetails"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/backup"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// ErrBackupsAdminOnly is returned when a signed-in account without the admin
// role reads or changes instance-wide backup state. Snapshots cover every
// account, so backups are admin-only.
var ErrBackupsAdminOnly = errors.New("backups are managed by an administrator; only an administrator can view or change them")

// toConnectError maps wdid's service errors onto stable Connect codes and
// attaches field-level validation details where available.
func toConnectError(err error) error {
	var validation domain.ValidationError
	switch {
	case errors.As(err, &validation):
		connectErr := connect.NewError(connect.CodeInvalidArgument, err)
		detail, detailErr := connect.NewErrorDetail(&errdetails.BadRequest{
			FieldViolations: []*errdetails.BadRequest_FieldViolation{{
				Field:       validation.Field,
				Description: validation.Message,
			}},
		})
		if detailErr == nil {
			connectErr.AddDetail(detail)
		}
		return connectErr
	case errors.Is(err, store.ErrNotFound),
		errors.Is(err, store.ErrCategoryNotFound),
		errors.Is(err, store.ErrSubcategoryNotFound):
		return connect.NewError(connect.CodeNotFound, err)
	case errors.Is(err, store.ErrCategoryRoleImmutable),
		errors.Is(err, store.ErrCategoryInUse),
		errors.Is(err, store.ErrSubcategoryInUse),
		errors.Is(err, store.ErrSubcategoryReparent),
		errors.Is(err, store.ErrFinalCheckInReadOnly):
		return connect.NewError(connect.CodeFailedPrecondition, err)
	case errors.Is(err, store.ErrEmailExists):
		return connect.NewError(connect.CodeAlreadyExists, err)
	case errors.Is(err, ErrBackupsAdminOnly):
		return connect.NewError(connect.CodePermissionDenied, err)
	case errors.Is(err, store.ErrInvalidSnapshot):
		return connect.NewError(connect.CodeFailedPrecondition, err)
	case errors.Is(err, backup.ErrSnapshotNotFound):
		return connect.NewError(connect.CodeNotFound, err)
	case errors.Is(err, backup.ErrRestoreUnsupported):
		return connect.NewError(connect.CodeFailedPrecondition, err)
	case errors.Is(err, auth.ErrInvalidBootstrapSecret),
		errors.Is(err, auth.ErrInvalidInvite),
		errors.Is(err, auth.ErrInviteUsed),
		errors.Is(err, auth.ErrInviteEmailMismatch):
		return connect.NewError(connect.CodePermissionDenied, err)
	case errors.Is(err, auth.ErrBootstrapComplete):
		return connect.NewError(connect.CodeFailedPrecondition, err)
	case errors.Is(err, auth.ErrInviteRequired):
		return connect.NewError(connect.CodeInvalidArgument, err)
	case errors.Is(err, auth.ErrInvalidCredentials), errors.Is(err, auth.ErrUnauthenticated):
		return connect.NewError(connect.CodeUnauthenticated, err)
	default:
		platform.Log.Error("RPC request failed", zap.Error(err))
		return connect.NewError(connect.CodeInternal, errors.New("the request could not be completed"))
	}
}
