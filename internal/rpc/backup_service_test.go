package rpc_test

import (
	"context"
	"errors"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"

	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/store"
)

// registeredUserToken invites and registers a normal account. It is never an
// administrator: only the bootstrap account gets the admin role.
func registeredUserToken(t *testing.T, server *httptest.Server, database *store.Store, email string) string {
	t.Helper()

	code := createInvite(t, database, email)
	response, err := authClient(server).RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:       email,
		Password:    testPassword,
		DisplayName: "Member",
		InviteCode:  code,
	}))
	if err != nil {
		t.Fatalf("register %s: %v", email, err)
	}
	if response.Msg.GetUser().GetRole() != wdidv1.UserRole_USER_ROLE_USER {
		t.Fatalf("invited account role = %v, want user", response.Msg.GetUser().GetRole())
	}
	return response.Msg.GetToken()
}

// backupTestSettings returns a complete, valid settings message. The backup
// block is left empty so tests can vary exactly one backup field.
func backupTestSettings() *wdidv1.Settings {
	return &wdidv1.Settings{
		Timezone:             "UTC",
		WeekStart:            1,
		DailyTarget:          minutes(450),
		ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_OFF,
		LongTimerThreshold:   minutes(240),
		DefaultEntryDuration: minutes(30),
		Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM,
		Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMFORTABLE,
	}
}

func TestBackupRPCsRequireAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)
	client := settingsClient(server)

	if _, err := client.BackupNow(context.Background(), connect.NewRequest(&wdidv1.BackupNowRequest{})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("backup now code = %v, want unauthenticated", connect.CodeOf(err))
	}
	if _, err := client.GetBackupStatus(context.Background(), connect.NewRequest(&wdidv1.GetBackupStatusRequest{})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("backup status code = %v, want unauthenticated", connect.CodeOf(err))
	}
	if _, err := client.ListBackups(context.Background(), connect.NewRequest(&wdidv1.ListBackupsRequest{})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("list backups code = %v, want unauthenticated", connect.CodeOf(err))
	}
	if _, err := client.RestoreBackup(context.Background(), connect.NewRequest(&wdidv1.RestoreBackupRequest{Name: "wdid-20260101T000000Z-manual.db"})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("restore backup code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

func TestBackupStatusReportsConfiguredDirectoryAndOverdue(t *testing.T) {
	cfg := testConfig(t)
	server, _ := newDomainServerWithConfig(t, cfg)
	token := bootstrapToken(t, server)
	client := settingsClient(server)

	response, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, token))
	if err != nil {
		t.Fatalf("get backup status: %v", err)
	}
	status := response.Msg.GetStatus()
	wantDir := filepath.Join(filepath.Dir(cfg.DBPath), "backups")
	if status.GetBackupDirectory() != wantDir {
		t.Fatalf("backup directory = %q, want %q", status.GetBackupDirectory(), wantDir)
	}
	if !status.GetOverdue() {
		t.Fatal("a workspace with no backups must be overdue")
	}
	if status.GetBackupInterval().AsDuration() != 6*time.Hour {
		t.Fatalf("interval = %s, want 6h", status.GetBackupInterval().AsDuration())
	}
	if status.GetBackupRetention() != 30 {
		t.Fatalf("retention = %d, want 30", status.GetBackupRetention())
	}
	if status.GetLastBackupAt() != nil {
		t.Fatalf("last backup = %v, want never", status.GetLastBackupAt())
	}
}

func TestBackupNowCreatesManualSnapshotAndReportsStatus(t *testing.T) {
	cfg := testConfig(t)
	server, _ := newDomainServerWithConfig(t, cfg)
	token := bootstrapToken(t, server)
	client := settingsClient(server)

	created, err := client.BackupNow(context.Background(), withBearer(&wdidv1.BackupNowRequest{}, token))
	if err != nil {
		t.Fatalf("backup now: %v", err)
	}
	backup := created.Msg.GetBackup()
	if !backup.GetManual() {
		t.Fatal("BackupNow must create a manual snapshot")
	}
	if !strings.Contains(backup.GetName(), "-manual") {
		t.Fatalf("name = %q, want the manual suffix", backup.GetName())
	}
	if backup.GetSizeBytes() <= 0 {
		t.Fatalf("size = %d, want the file size", backup.GetSizeBytes())
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(cfg.DBPath), "backups", backup.GetName())); err != nil {
		t.Fatalf("manual snapshot missing on disk: %v", err)
	}

	status := created.Msg.GetStatus()
	if status.GetLastBackupAt() == nil || status.GetLastBackupSizeBytes() != backup.GetSizeBytes() {
		t.Fatalf("status = %+v, want the manual snapshot as the latest backup", status)
	}
	if !status.GetLastBackupManual() {
		t.Fatal("the latest backup is manual")
	}
	if status.GetManualCount() != 1 || status.GetScheduledCount() != 0 {
		t.Fatalf("counts = %d scheduled, %d manual", status.GetScheduledCount(), status.GetManualCount())
	}
	// A manual backup does not satisfy the schedule.
	if !status.GetOverdue() {
		t.Fatal("a manual-only backup directory remains overdue")
	}

	listed, err := client.ListBackups(context.Background(), withBearer(&wdidv1.ListBackupsRequest{}, token))
	if err != nil {
		t.Fatalf("list backups: %v", err)
	}
	if len(listed.Msg.GetBackups()) != 1 || listed.Msg.GetBackups()[0].GetName() != backup.GetName() {
		t.Fatalf("listed backups = %v, want the manual snapshot", listed.Msg.GetBackups())
	}
}

// Backups snapshot every account's data, so the whole surface is admin-only.
// Each RPC denies a normal account with an explanation and keeps working for
// the administrator.
func TestBackupRPCsRequireAdmin(t *testing.T) {
	server, database := newDomainServer(t)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "member@example.com")
	client := settingsClient(server)

	calls := []struct {
		name string
		call func(token string) error
	}{
		{
			name: "BackupNow",
			call: func(token string) error {
				_, err := client.BackupNow(context.Background(), withBearer(&wdidv1.BackupNowRequest{}, token))
				return err
			},
		},
		{
			name: "GetBackupStatus",
			call: func(token string) error {
				_, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, token))
				return err
			},
		},
		{
			name: "ListBackups",
			call: func(token string) error {
				_, err := client.ListBackups(context.Background(), withBearer(&wdidv1.ListBackupsRequest{}, token))
				return err
			},
		},
		{
			name: "RestoreBackup",
			call: func(token string) error {
				_, err := client.RestoreBackup(context.Background(), withBearer(&wdidv1.RestoreBackupRequest{Name: "wdid-20260101T000000Z-manual.db"}, token))
				return err
			},
		},
	}

	for _, testCase := range calls {
		t.Run(testCase.name, func(t *testing.T) {
			err := testCase.call(memberToken)
			if connect.CodeOf(err) != connect.CodePermissionDenied {
				t.Fatalf("%s code = %v, want permission denied", testCase.name, connect.CodeOf(err))
			}
			if !strings.Contains(err.Error(), "administrator") {
				t.Fatalf("%s error = %q, want an explanation naming the administrator", testCase.name, err)
			}
		})
	}

	// The denied BackupNow must not have written a snapshot.
	listed, err := client.ListBackups(context.Background(), withBearer(&wdidv1.ListBackupsRequest{}, adminToken))
	if err != nil {
		t.Fatalf("admin list backups: %v", err)
	}
	if len(listed.Msg.GetBackups()) != 0 {
		t.Fatalf("backups after denied call = %d, want none", len(listed.Msg.GetBackups()))
	}

	// The administrator keeps the full surface.
	created, err := client.BackupNow(context.Background(), withBearer(&wdidv1.BackupNowRequest{}, adminToken))
	if err != nil {
		t.Fatalf("admin backup now: %v", err)
	}
	if !created.Msg.GetBackup().GetManual() {
		t.Fatal("admin BackupNow must create a manual snapshot")
	}
	if _, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, adminToken)); err != nil {
		t.Fatalf("admin get backup status: %v", err)
	}
	listed, err = client.ListBackups(context.Background(), withBearer(&wdidv1.ListBackupsRequest{}, adminToken))
	if err != nil {
		t.Fatalf("admin list backups: %v", err)
	}
	if len(listed.Msg.GetBackups()) != 1 {
		t.Fatalf("admin backups = %d, want the manual snapshot", len(listed.Msg.GetBackups()))
	}
}

// Restoring a chosen snapshot replaces the database, preserves the previous
// database as a pre-restore file, and leaves the admin surface working.
func TestRestoreBackupRoundTrip(t *testing.T) {
	cfg := testConfig(t)
	server, database := newDomainServerWithConfig(t, cfg)
	adminToken := bootstrapToken(t, server)
	client := settingsClient(server)

	created, err := client.BackupNow(context.Background(), withBearer(&wdidv1.BackupNowRequest{}, adminToken))
	if err != nil {
		t.Fatalf("backup now: %v", err)
	}
	name := created.Msg.GetBackup().GetName()

	// This account is created after the snapshot, so a successful restore must
	// remove it.
	_ = registeredUserToken(t, server, database, "after-snapshot@example.com")
	if _, err := database.UserByEmail("after-snapshot@example.com"); err != nil {
		t.Fatalf("post-snapshot account was not created: %v", err)
	}

	restored, err := client.RestoreBackup(context.Background(), withBearer(&wdidv1.RestoreBackupRequest{Name: name}, adminToken))
	if err != nil {
		t.Fatalf("restore backup: %v", err)
	}
	if restored.Msg.GetBackup().GetName() != name {
		t.Fatalf("restored backup = %q, want %q", restored.Msg.GetBackup().GetName(), name)
	}
	preRestorePath := restored.Msg.GetPreRestorePath()
	if preRestorePath == "" {
		t.Fatal("restore response has no pre-restore path")
	}
	if filepath.Dir(preRestorePath) != filepath.Dir(cfg.DBPath) {
		t.Fatalf("pre-restore path = %q, want it next to the database", preRestorePath)
	}
	if _, err := os.Stat(preRestorePath); err != nil {
		t.Fatalf("pre-restore copy missing: %v", err)
	}
	if restored.Msg.GetStatus().GetLastBackupAt() == nil {
		t.Fatal("restore response has no backup status")
	}

	// The restored database matches the snapshot.
	if _, err := database.UserByEmail("after-snapshot@example.com"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("post-snapshot account after restore error = %v, want ErrNotFound", err)
	}
	if _, err := database.UserByEmail("admin@example.com"); err != nil {
		t.Fatalf("admin account missing after restore: %v", err)
	}

	// The restored handle keeps serving the backup RPCs.
	if _, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, adminToken)); err != nil {
		t.Fatalf("get backup status after restore: %v", err)
	}
}

// A restore refuses an empty name, a missing snapshot and a file that is not a
// usable database, and none of those attempts changes the live database.
func TestRestoreBackupRejectsInvalidSelection(t *testing.T) {
	cfg := testConfig(t)
	server, _ := newDomainServerWithConfig(t, cfg)
	adminToken := bootstrapToken(t, server)
	client := settingsClient(server)

	_, err := client.RestoreBackup(context.Background(), withBearer(&wdidv1.RestoreBackupRequest{}, adminToken))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("empty name code = %v, want invalid argument", connect.CodeOf(err))
	}
	if !strings.Contains(err.Error(), "name:") {
		t.Fatalf("empty name error = %q, want a name field violation", err)
	}

	_, err = client.RestoreBackup(context.Background(),
		withBearer(&wdidv1.RestoreBackupRequest{Name: "wdid-29990101T000000Z-manual.db"}, adminToken))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("missing snapshot code = %v, want not found", connect.CodeOf(err))
	}

	// A file that looks like a snapshot but is not a BoltDB database.
	backupDir := filepath.Join(filepath.Dir(cfg.DBPath), "backups")
	if err := os.MkdirAll(backupDir, 0o750); err != nil {
		t.Fatalf("create backup directory: %v", err)
	}
	corruptName := "wdid-20260101T000000Z-manual.db"
	if err := os.WriteFile(filepath.Join(backupDir, corruptName), []byte("not bolt"), 0o600); err != nil {
		t.Fatalf("write corrupt snapshot: %v", err)
	}
	_, err = client.RestoreBackup(context.Background(),
		withBearer(&wdidv1.RestoreBackupRequest{Name: corruptName}, adminToken))
	if connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("corrupt snapshot code = %v, want failed precondition", connect.CodeOf(err))
	}

	// The live database still serves and no refused attempt left a pre-restore
	// copy behind.
	if _, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, adminToken)); err != nil {
		t.Fatalf("get backup status after refused restores: %v", err)
	}
	entries, err := os.ReadDir(filepath.Dir(cfg.DBPath))
	if err != nil {
		t.Fatalf("read data directory: %v", err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "wdid-before-restore-") {
			t.Fatalf("a refused restore wrote a pre-restore copy: %s", entry.Name())
		}
	}
}

// A normal account cannot change the instance-wide backup preferences through
// UpdateSettings, while the administrator can.
func TestNonAdminCannotChangeBackupSettings(t *testing.T) {
	cfg := testConfig(t)
	server, database := newDomainServerWithConfig(t, cfg)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "member@example.com")
	client := settingsClient(server)

	customDir := filepath.Join(t.TempDir(), "admin-backups")
	adminSettings := backupTestSettings()
	adminSettings.BackupDirectory = customDir
	adminSettings.BackupInterval = minutes(60)
	adminSettings.BackupRetention = 2
	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: adminSettings}, adminToken)); err != nil {
		t.Fatalf("admin update backup settings: %v", err)
	}

	status, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, adminToken))
	if err != nil {
		t.Fatalf("admin get backup status: %v", err)
	}
	if status.Msg.GetStatus().GetBackupDirectory() != customDir ||
		status.Msg.GetStatus().GetBackupInterval().AsDuration() != time.Hour ||
		status.Msg.GetStatus().GetBackupRetention() != 2 {
		t.Fatalf("admin backup status = %+v, want the configured values", status.Msg.GetStatus())
	}

	attempts := []struct {
		name   string
		mutate func(*wdidv1.Settings)
	}{
		{"directory", func(s *wdidv1.Settings) { s.BackupDirectory = filepath.Join(t.TempDir(), "member-backups") }},
		{"interval", func(s *wdidv1.Settings) { s.BackupInterval = minutes(120) }},
		{"retention", func(s *wdidv1.Settings) { s.BackupRetention = 5 }},
	}

	for _, attempt := range attempts {
		t.Run(attempt.name, func(t *testing.T) {
			settings := backupTestSettings()
			attempt.mutate(settings)
			_, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: settings}, memberToken))
			if connect.CodeOf(err) != connect.CodePermissionDenied {
				t.Fatalf("code = %v, want permission denied", connect.CodeOf(err))
			}
			if !strings.Contains(err.Error(), "administrator") {
				t.Fatalf("error = %q, want an explanation naming the administrator", err)
			}
		})
	}

	// The administrator's instance-wide configuration is untouched.
	status, err = client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, adminToken))
	if err != nil {
		t.Fatalf("admin get backup status after attempts: %v", err)
	}
	if status.Msg.GetStatus().GetBackupDirectory() != customDir ||
		status.Msg.GetStatus().GetBackupInterval().AsDuration() != time.Hour ||
		status.Msg.GetStatus().GetBackupRetention() != 2 {
		t.Fatalf("backup status after non-admin attempts = %+v, want the admin values", status.Msg.GetStatus())
	}

	// A normal account can still read its own settings.
	member, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken))
	if err != nil {
		t.Fatalf("member get settings: %v", err)
	}
	if member.Msg.GetSettings().GetTimezone() != "UTC" {
		t.Fatalf("member timezone = %q, want its own default", member.Msg.GetSettings().GetTimezone())
	}
}

// Non-admins can still save their own preferences. Backup fields they do not
// change are preserved, and they are never applied to the live manager.
func TestNonAdminCanUpdateNormalSettings(t *testing.T) {
	server, database := newDomainServer(t)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "member@example.com")
	client := settingsClient(server)

	// Shape one: round-trip exactly what GetSettings returned.
	member, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken))
	if err != nil {
		t.Fatalf("member get settings: %v", err)
	}
	updated := member.Msg.GetSettings()
	updated.Timezone = "Europe/Amsterdam"
	updated.Theme = wdidv1.ThemePreference_THEME_PREFERENCE_DARK
	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: updated}, memberToken)); err != nil {
		t.Fatalf("non-admin update with round-tripped settings: %v", err)
	}

	// Shape two: a client that omits the backup block entirely.
	omitted := backupTestSettings()
	omitted.Timezone = "Europe/Amsterdam"
	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: omitted}, memberToken)); err != nil {
		t.Fatalf("non-admin update without backup fields: %v", err)
	}

	response, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken))
	if err != nil {
		t.Fatalf("member get settings after update: %v", err)
	}
	settings := response.Msg.GetSettings()
	if settings.GetTimezone() != "Europe/Amsterdam" {
		t.Fatalf("timezone = %q, want the updated value", settings.GetTimezone())
	}
	if settings.GetBackupInterval().AsDuration() != 6*time.Hour || settings.GetBackupRetention() != 30 {
		t.Fatalf("backup preferences = %s/%d, want the preserved defaults", settings.GetBackupInterval().AsDuration(), settings.GetBackupRetention())
	}

	// The live instance-wide configuration still comes from the administrator.
	status, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, adminToken))
	if err != nil {
		t.Fatalf("admin get backup status: %v", err)
	}
	if status.Msg.GetStatus().GetBackupInterval().AsDuration() != 6*time.Hour ||
		status.Msg.GetStatus().GetBackupRetention() != 30 {
		t.Fatalf("live backup config = %+v, want the service defaults", status.Msg.GetStatus())
	}
}

// The gate behaves the same over gRPC-Web, which is what the browser uses.
func TestBackupAdminGatingServesGRPCWeb(t *testing.T) {
	server, database := newDomainServer(t)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "member@example.com")
	client := settingsClient(server, connect.WithGRPCWeb())

	if _, err := client.BackupNow(context.Background(), withBearer(&wdidv1.BackupNowRequest{}, memberToken)); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("gRPC-Web BackupNow code = %v, want permission denied", connect.CodeOf(err))
	}
	if _, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, memberToken)); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("gRPC-Web GetBackupStatus code = %v, want permission denied", connect.CodeOf(err))
	}
	if _, err := client.ListBackups(context.Background(), withBearer(&wdidv1.ListBackupsRequest{}, memberToken)); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("gRPC-Web ListBackups code = %v, want permission denied", connect.CodeOf(err))
	}
	if _, err := client.RestoreBackup(context.Background(), withBearer(&wdidv1.RestoreBackupRequest{Name: "wdid-20260101T000000Z-manual.db"}, memberToken)); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("gRPC-Web RestoreBackup code = %v, want permission denied", connect.CodeOf(err))
	}

	changed := backupTestSettings()
	changed.BackupRetention = 3
	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: changed}, memberToken)); connect.CodeOf(err) != connect.CodePermissionDenied {
		t.Fatalf("gRPC-Web backup settings update code = %v, want permission denied", connect.CodeOf(err))
	}

	// Normal settings still load for the normal account.
	if _, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken)); err != nil {
		t.Fatalf("gRPC-Web member GetSettings: %v", err)
	}

	// The administrator keeps the surface.
	created, err := client.BackupNow(context.Background(), withBearer(&wdidv1.BackupNowRequest{}, adminToken))
	if err != nil {
		t.Fatalf("gRPC-Web admin BackupNow: %v", err)
	}
	if _, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, adminToken)); err != nil {
		t.Fatalf("gRPC-Web admin GetBackupStatus: %v", err)
	}
	if _, err := client.ListBackups(context.Background(), withBearer(&wdidv1.ListBackupsRequest{}, adminToken)); err != nil {
		t.Fatalf("gRPC-Web admin ListBackups: %v", err)
	}
	if _, err := client.RestoreBackup(context.Background(),
		withBearer(&wdidv1.RestoreBackupRequest{Name: created.Msg.GetBackup().GetName()}, adminToken)); err != nil {
		t.Fatalf("gRPC-Web admin RestoreBackup: %v", err)
	}
}

func TestUpdateSettingsReconfiguresBackups(t *testing.T) {
	cfg := testConfig(t)
	server, _ := newDomainServerWithConfig(t, cfg)
	token := bootstrapToken(t, server)
	client := settingsClient(server)

	customDir := filepath.Join(t.TempDir(), "custom-backups")
	_, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: &wdidv1.Settings{
			Timezone:             "UTC",
			WeekStart:            1,
			DailyTarget:          minutes(450),
			ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_OFF,
			LongTimerThreshold:   minutes(240),
			DefaultEntryDuration: minutes(30),
			BackupDirectory:      customDir,
			BackupInterval:       minutes(60),
			BackupRetention:      2,
			Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM,
			Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMFORTABLE,
		},
	}, token))
	if err != nil {
		t.Fatalf("update settings: %v", err)
	}

	status, err := client.GetBackupStatus(context.Background(), withBearer(&wdidv1.GetBackupStatusRequest{}, token))
	if err != nil {
		t.Fatalf("get backup status: %v", err)
	}
	if status.Msg.GetStatus().GetBackupDirectory() != customDir {
		t.Fatalf("directory = %q, want %q", status.Msg.GetStatus().GetBackupDirectory(), customDir)
	}
	if status.Msg.GetStatus().GetBackupInterval().AsDuration() != time.Hour {
		t.Fatalf("interval = %s, want 1h", status.Msg.GetStatus().GetBackupInterval().AsDuration())
	}
	if status.Msg.GetStatus().GetBackupRetention() != 2 {
		t.Fatalf("retention = %d, want 2", status.Msg.GetStatus().GetBackupRetention())
	}

	created, err := client.BackupNow(context.Background(), withBearer(&wdidv1.BackupNowRequest{}, token))
	if err != nil {
		t.Fatalf("backup now: %v", err)
	}
	if _, err := os.Stat(filepath.Join(customDir, created.Msg.GetBackup().GetName())); err != nil {
		t.Fatalf("manual snapshot was not written to the configured directory: %v", err)
	}
}
