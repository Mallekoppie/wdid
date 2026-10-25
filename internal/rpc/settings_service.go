package rpc

import (
	"context"
	"net/http"
	"strings"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/backup"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
)

// SettingsService implements the generated SettingsService handler. Settings
// are stored per account, so a second user never sees the first user's
// preferences. Backups are instance-wide and use the configured backup
// directory, interval and retention.
type SettingsService struct {
	store *store.Store
	auth  *auth.Service
	// backup is the instance-wide snapshot manager shared with the scheduler.
	backup *backup.Manager
	// backupDefaults are the service-level backup settings. They are the
	// fallback when an account has not configured backups.
	backupDefaults backup.Config
}

// SettingsServiceOption customises a SettingsService.
type SettingsServiceOption func(*SettingsService)

// WithBackupManager shares the service's snapshot manager with Settings. The
// RPC surface can then report status and take a manual backup.
func WithBackupManager(manager *backup.Manager) SettingsServiceOption {
	return func(service *SettingsService) {
		if manager != nil {
			service.backup = manager
		}
	}
}

// NewSettingsService builds the SettingsService implementation.
func NewSettingsService(database *store.Store, authService *auth.Service, options ...SettingsServiceOption) *SettingsService {
	service := &SettingsService{store: database, auth: authService}
	for _, option := range options {
		option(service)
	}
	if service.backup == nil {
		// Tests and embedders that do not care about backups still get a
		// usable manual/status surface scoped to the default directory.
		service.backup = backup.New(database, backup.Config{})
	}
	service.backupDefaults = service.backup.Config()
	return service
}

// Register implements platform.ConnectService.
func (s *SettingsService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewSettingsServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// settingsForUser returns the account's saved settings, materialising the
// default record and seeding the support-person roster on the first load.
func (s *SettingsService) settingsForUser(userID string) (domain.Settings, error) {
	return s.store.EnsureSupportPeople(userID)
}

// backupSettingsChanged reports whether a request tries to change an
// instance-wide backup preference. An empty directory or a zero interval or
// retention means the caller did not send the backup block, so it is not a
// change; clients that omit backups can still save their own preferences.
func backupSettingsChanged(requested, current domain.Settings) bool {
	requested.Normalize()
	if requested.BackupDirectory != "" && requested.BackupDirectory != current.BackupDirectory {
		return true
	}
	if requested.BackupIntervalHours != 0 && requested.BackupIntervalHours != current.BackupIntervalHours {
		return true
	}
	return requested.BackupRetention != 0 && requested.BackupRetention != current.BackupRetention
}

// GetSettings returns the caller's preferences and build information. It works
// for every account: backups are admin-only, but ordinary settings are not.
func (s *SettingsService) GetSettings(ctx context.Context, _ *connect.Request[wdidv1.GetSettingsRequest]) (*connect.Response[wdidv1.GetSettingsResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	settings, err := s.settingsForUser(userID)
	if err != nil {
		return nil, toConnectError(err)
	}

	schemaVersion, err := s.store.SchemaVersion()
	if err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.GetSettingsResponse{
		Settings: toProtoSettings(settings),
		About: &wdidv1.About{
			Version:       config.ServiceVersion,
			SchemaVersion: int32(schemaVersion),
			License:       config.ServiceLicense,
		},
	}), nil
}

// UpdateSettings replaces the caller's preferences after validating every
// field. Enum and range failures carry a field violation. Backups are
// instance-wide, so their fields are admin-only: a non-admin request that tries
// to change the backup directory, interval or retention is denied.
func (s *SettingsService) UpdateSettings(ctx context.Context, request *connect.Request[wdidv1.UpdateSettingsRequest]) (*connect.Response[wdidv1.UpdateSettingsResponse], error) {
	identity, err := s.auth.IdentityFromRequestContext(ctx)
	if err != nil {
		return nil, toConnectError(err)
	}
	userID := identity.UserID
	isAdmin := identity.HasRole(string(domain.RoleAdmin))

	if request.Msg.GetSettings() == nil {
		return nil, toConnectError(domain.ValidationError{Field: "settings", Message: "is required"})
	}

	settings := fromProtoSettings(request.Msg.GetSettings())
	settings.UserID = userID
	settings.UpdatedAt = time.Now().UTC()
	// Seed before replacing the roster, so an administrator whose first settings
	// call is an update still records the seeded marker exactly once.
	if _, err := s.store.EnsureSupportPeople(userID); err != nil {
		return nil, toConnectError(err)
	}
	// An explicit save replaces the roster and marks it as seeded; otherwise the
	// next load would resurrect names the client deliberately removed.
	settings.SupportPeopleSeeded = true

	if !isAdmin {
		current, err := s.settingsForUser(userID)
		if err != nil {
			return nil, toConnectError(err)
		}
		if backupSettingsChanged(settings, current) {
			return nil, toConnectError(ErrBackupsAdminOnly)
		}
		// Preserve the account's own backup preferences without applying them
		// to the live manager. The instance-wide schedule is admin-only.
		settings.BackupDirectory = current.BackupDirectory
		settings.BackupIntervalHours = current.BackupIntervalHours
		settings.BackupRetention = current.BackupRetention
	}

	// Canonicalise before saving so the response carries exactly what is stored.
	settings.Normalize()
	if err := s.store.SaveSettings(settings); err != nil {
		return nil, toConnectError(err)
	}

	if isAdmin {
		// Backups are instance-wide, so the saved preferences become the live
		// configuration for the scheduler and the backup RPCs.
		s.backup.Configure(backup.FromSettings(settings, s.backupDefaults))
	}

	return connect.NewResponse(&wdidv1.UpdateSettingsResponse{Settings: toProtoSettings(settings)}), nil
}

// BackupNow takes a manual snapshot. Manual snapshots are never removed by
// retention. Backups cover every account, so only an administrator may ask.
func (s *SettingsService) BackupNow(ctx context.Context, _ *connect.Request[wdidv1.BackupNowRequest]) (*connect.Response[wdidv1.BackupNowResponse], error) {
	if _, err := backupAdminFromContext(ctx, s.auth); err != nil {
		return nil, toConnectError(err)
	}

	snapshot, err := s.backup.Create(backup.KindManual)
	if err != nil {
		return nil, toConnectError(err)
	}
	status, err := s.backup.Status()
	if err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.BackupNowResponse{
		Backup: toProtoBackup(snapshot),
		Status: toProtoBackupStatus(status),
	}), nil
}

// GetBackupStatus reports the last backup, its size and whether the schedule
// is overdue. Only an administrator may inspect instance-wide backup state.
func (s *SettingsService) GetBackupStatus(ctx context.Context, _ *connect.Request[wdidv1.GetBackupStatusRequest]) (*connect.Response[wdidv1.GetBackupStatusResponse], error) {
	if _, err := backupAdminFromContext(ctx, s.auth); err != nil {
		return nil, toConnectError(err)
	}

	status, err := s.backup.Status()
	if err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.GetBackupStatusResponse{
		Status: toProtoBackupStatus(status),
	}), nil
}

// ListBackups returns every snapshot, newest first. Only an administrator may
// inspect instance-wide backup state.
func (s *SettingsService) ListBackups(ctx context.Context, _ *connect.Request[wdidv1.ListBackupsRequest]) (*connect.Response[wdidv1.ListBackupsResponse], error) {
	if _, err := backupAdminFromContext(ctx, s.auth); err != nil {
		return nil, toConnectError(err)
	}

	snapshots, err := s.backup.List()
	if err != nil {
		return nil, toConnectError(err)
	}

	backups := make([]*wdidv1.Backup, 0, len(snapshots))
	for _, snapshot := range snapshots {
		backups = append(backups, toProtoBackup(snapshot))
	}

	return connect.NewResponse(&wdidv1.ListBackupsResponse{Backups: backups}), nil
}

// RestoreBackup replaces the live database with one named snapshot. The
// snapshot is verified before the database changes and the current database is
// preserved as a pre-restore file. Restoring covers every account, so only an
// administrator may ask.
func (s *SettingsService) RestoreBackup(ctx context.Context, request *connect.Request[wdidv1.RestoreBackupRequest]) (*connect.Response[wdidv1.RestoreBackupResponse], error) {
	if _, err := backupAdminFromContext(ctx, s.auth); err != nil {
		return nil, toConnectError(err)
	}

	name := strings.TrimSpace(request.Msg.GetName())
	if name == "" {
		return nil, toConnectError(domain.ValidationError{Field: "name", Message: "is required"})
	}

	snapshot, result, err := s.backup.Restore(name)
	if err != nil {
		return nil, toConnectError(err)
	}

	status, err := s.backup.Status()
	if err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.RestoreBackupResponse{
		Backup:         toProtoBackup(snapshot),
		Status:         toProtoBackupStatus(status),
		PreRestorePath: result.PreRestorePath,
	}), nil
}

func toProtoBackup(snapshot backup.Snapshot) *wdidv1.Backup {
	return &wdidv1.Backup{
		Name:      snapshot.Name,
		CreatedAt: timestamppb.New(snapshot.CreatedAt.UTC()),
		SizeBytes: snapshot.Size,
		Manual:    snapshot.Manual(),
	}
}

func toProtoBackupStatus(status backup.Status) *wdidv1.BackupStatus {
	var lastBackupAt *timestamppb.Timestamp
	if !status.LastBackupAt.IsZero() {
		lastBackupAt = timestamppb.New(status.LastBackupAt.UTC())
	}
	var nextBackupAt *timestamppb.Timestamp
	if !status.NextDueAt.IsZero() {
		nextBackupAt = timestamppb.New(status.NextDueAt.UTC())
	}
	return &wdidv1.BackupStatus{
		LastBackupAt:        lastBackupAt,
		LastBackupSizeBytes: status.LastBackupSize,
		Overdue:             status.Overdue,
		BackupDirectory:     status.Directory,
		BackupInterval:      durationpb.New(status.Interval),
		BackupRetention:     int32(status.Retention),
		ScheduledCount:      int32(status.ScheduledCount),
		ManualCount:         int32(status.ManualCount),
		NextBackupAt:        nextBackupAt,
		LastBackupManual:    status.LastBackupManual,
	}
}

func toProtoSettings(settings domain.Settings) *wdidv1.Settings {
	var updatedAt *timestamppb.Timestamp
	if !settings.UpdatedAt.IsZero() {
		updatedAt = timestamppb.New(settings.UpdatedAt)
	}
	return &wdidv1.Settings{
		Timezone:             settings.Timezone,
		WeekStart:            int32(settings.WeekStart),
		DailyTarget:          minutesDuration(settings.DailyTargetMinutes),
		ReviewCadence:        toProtoReviewCadence(settings.ReviewCadence),
		LongTimerThreshold:   minutesDuration(settings.LongTimerMinutes),
		DefaultEntryDuration: minutesDuration(settings.DefaultDurationMinutes),
		BackupDirectory:      settings.BackupDirectory,
		BackupInterval:       minutesDuration(settings.BackupIntervalHours * 60),
		BackupRetention:      int32(settings.BackupRetention),
		AiBaseUrl:            settings.AIBaseURL,
		AiModel:              settings.AIModel,
		AiRedact:             settings.AIRedact,
		Theme:                toProtoTheme(settings.Theme),
		Density:              toProtoDensity(settings.Density),
		JournalStartDate:     settings.JournalStartDate,
		UpdatedAt:            updatedAt,
		SupportPeople:        settings.SupportPeople,
	}
}

func fromProtoSettings(settings *wdidv1.Settings) domain.Settings {
	return domain.Settings{
		Timezone:               settings.GetTimezone(),
		WeekStart:              int(settings.GetWeekStart()),
		DailyTargetMinutes:     durationMinutes(settings.GetDailyTarget()),
		ReviewCadence:          fromProtoReviewCadence(settings.GetReviewCadence()),
		LongTimerMinutes:       durationMinutes(settings.GetLongTimerThreshold()),
		DefaultDurationMinutes: durationMinutes(settings.GetDefaultEntryDuration()),
		BackupDirectory:        settings.GetBackupDirectory(),
		BackupIntervalHours:    durationMinutes(settings.GetBackupInterval()) / 60,
		BackupRetention:        int(settings.GetBackupRetention()),
		AIBaseURL:              settings.GetAiBaseUrl(),
		AIModel:                settings.GetAiModel(),
		AIRedact:               settings.GetAiRedact(),
		Theme:                  fromProtoTheme(settings.GetTheme()),
		Density:                fromProtoDensity(settings.GetDensity()),
		JournalStartDate:       settings.GetJournalStartDate(),
		SupportPeople:          settings.GetSupportPeople(),
	}
}

func minutesDuration(minutes int) *durationpb.Duration {
	return durationpb.New(time.Duration(minutes) * time.Minute)
}

func durationMinutes(duration *durationpb.Duration) int {
	if duration == nil {
		return 0
	}
	return int(duration.AsDuration().Minutes())
}

func toProtoReviewCadence(cadence domain.ReviewCadence) wdidv1.ReviewCadence {
	switch cadence {
	case domain.ReviewCadenceWeekly:
		return wdidv1.ReviewCadence_REVIEW_CADENCE_WEEKLY
	case domain.ReviewCadenceMonthly:
		return wdidv1.ReviewCadence_REVIEW_CADENCE_MONTHLY
	case domain.ReviewCadenceOff:
		return wdidv1.ReviewCadence_REVIEW_CADENCE_OFF
	default:
		return wdidv1.ReviewCadence_REVIEW_CADENCE_UNSPECIFIED
	}
}

func fromProtoReviewCadence(cadence wdidv1.ReviewCadence) domain.ReviewCadence {
	switch cadence {
	case wdidv1.ReviewCadence_REVIEW_CADENCE_WEEKLY:
		return domain.ReviewCadenceWeekly
	case wdidv1.ReviewCadence_REVIEW_CADENCE_MONTHLY:
		return domain.ReviewCadenceMonthly
	case wdidv1.ReviewCadence_REVIEW_CADENCE_OFF:
		return domain.ReviewCadenceOff
	default:
		return ""
	}
}

func toProtoTheme(theme domain.Theme) wdidv1.ThemePreference {
	switch theme {
	case domain.ThemeSystem:
		return wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM
	case domain.ThemeLight:
		return wdidv1.ThemePreference_THEME_PREFERENCE_LIGHT
	case domain.ThemeDark:
		return wdidv1.ThemePreference_THEME_PREFERENCE_DARK
	case domain.ThemeHighContrast:
		return wdidv1.ThemePreference_THEME_PREFERENCE_HIGH_CONTRAST
	default:
		return wdidv1.ThemePreference_THEME_PREFERENCE_UNSPECIFIED
	}
}

func fromProtoTheme(theme wdidv1.ThemePreference) domain.Theme {
	switch theme {
	case wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM:
		return domain.ThemeSystem
	case wdidv1.ThemePreference_THEME_PREFERENCE_LIGHT:
		return domain.ThemeLight
	case wdidv1.ThemePreference_THEME_PREFERENCE_DARK:
		return domain.ThemeDark
	case wdidv1.ThemePreference_THEME_PREFERENCE_HIGH_CONTRAST:
		return domain.ThemeHighContrast
	default:
		return ""
	}
}

func toProtoDensity(density domain.Density) wdidv1.DensityPreference {
	switch density {
	case domain.DensityComfortable:
		return wdidv1.DensityPreference_DENSITY_PREFERENCE_COMFORTABLE
	case domain.DensityCompact:
		return wdidv1.DensityPreference_DENSITY_PREFERENCE_COMPACT
	default:
		return wdidv1.DensityPreference_DENSITY_PREFERENCE_UNSPECIFIED
	}
}

func fromProtoDensity(density wdidv1.DensityPreference) domain.Density {
	switch density {
	case wdidv1.DensityPreference_DENSITY_PREFERENCE_COMFORTABLE:
		return domain.DensityComfortable
	case wdidv1.DensityPreference_DENSITY_PREFERENCE_COMPACT:
		return domain.DensityCompact
	default:
		return ""
	}
}
