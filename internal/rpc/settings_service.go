package rpc

import (
	"context"
	"errors"
	"net/http"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
)

// SettingsService implements the generated SettingsService handler. Settings
// are stored per account, so a second user never sees the first user's
// preferences.
type SettingsService struct {
	store *store.Store
	auth  *auth.Service
}

// NewSettingsService builds the SettingsService implementation.
func NewSettingsService(database *store.Store, authService *auth.Service) *SettingsService {
	return &SettingsService{store: database, auth: authService}
}

// Register implements platform.ConnectService.
func (s *SettingsService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewSettingsServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// GetSettings returns the caller's preferences and build information.
func (s *SettingsService) GetSettings(ctx context.Context, _ *connect.Request[wdidv1.GetSettingsRequest]) (*connect.Response[wdidv1.GetSettingsResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	settings, err := s.store.Settings(userID)
	if errors.Is(err, store.ErrNotFound) {
		settings = domain.DefaultSettings(userID)
	} else if err != nil {
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
// field. Enum and range failures carry a field violation.
func (s *SettingsService) UpdateSettings(ctx context.Context, request *connect.Request[wdidv1.UpdateSettingsRequest]) (*connect.Response[wdidv1.UpdateSettingsResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	if request.Msg.GetSettings() == nil {
		return nil, toConnectError(domain.ValidationError{Field: "settings", Message: "is required"})
	}

	settings := fromProtoSettings(request.Msg.GetSettings())
	settings.UserID = userID
	settings.UpdatedAt = time.Now().UTC()
	if err := s.store.SaveSettings(settings); err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.UpdateSettingsResponse{Settings: toProtoSettings(settings)}), nil
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
