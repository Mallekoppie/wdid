package rpc_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"

	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/store"
)

// seedSupportEntryForRoster writes a support-role entry for the user, using a
// fixed id so the roster's first-seen spelling is deterministic.
func seedSupportEntryForRoster(t *testing.T, database *store.Store, userID, id, person string) {
	t.Helper()

	categories, err := database.Categories(userID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	var support domain.Category
	for _, category := range categories {
		if category.Role == domain.CategoryRoleSupport {
			support = category
			break
		}
	}
	if support.ID == "" {
		t.Fatal("seeded taxonomy has no support category")
	}

	started := time.Date(2026, 10, 23, 9, 0, 0, 0, time.UTC)
	entry := domain.WorkEntry{
		ID:          id,
		UserID:      userID,
		CategoryID:  support.ID,
		Description: "Support for " + person,
		StartedAt:   started,
		EndedAt:     started.Add(30 * time.Minute),
		Minutes:     30,
		Source:      domain.EntrySourceManual,
		People:      []string{person},
		CreatedAt:   started,
		UpdatedAt:   started,
	}
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save support entry for %q: %v", person, err)
	}
}

func assertRoster(t *testing.T, settings *wdidv1.Settings, want []string) {
	t.Helper()

	got := settings.GetSupportPeople()
	if len(got) != len(want) {
		t.Fatalf("support people = %#v, want %#v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("support people = %#v, want %#v", got, want)
		}
	}
}

func TestSettingsRosterSeedsOnFirstLoadAndUpdateReplacesIt(t *testing.T) {
	server, database := newDomainServer(t)
	bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "roster-member@example.com")
	client := settingsClient(server)

	member, err := database.UserByEmail("roster-member@example.com")
	if err != nil {
		t.Fatalf("find member: %v", err)
	}
	seedSupportEntryForRoster(t, database, member.ID, "00000000-0000-7000-8000-000000000001", " Priya ")
	seedSupportEntryForRoster(t, database, member.ID, "00000000-0000-7000-8000-000000000002", "priya")
	seedSupportEntryForRoster(t, database, member.ID, "00000000-0000-7000-8000-000000000003", "Sam")

	// The first settings load seeds from the account's existing support entries.
	loaded, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken))
	if err != nil {
		t.Fatalf("get settings: %v", err)
	}
	assertRoster(t, loaded.Msg.GetSettings(), []string{"Priya", "Sam"})

	// UpdateSettings replaces the list and returns the canonical form.
	update := backupTestSettings()
	update.SupportPeople = []string{" Priya ", "priya", "Sam"}
	updated, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: update}, memberToken))
	if err != nil {
		t.Fatalf("update settings: %v", err)
	}
	assertRoster(t, updated.Msg.GetSettings(), []string{"Priya", "Sam"})

	reread, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken))
	if err != nil {
		t.Fatalf("get settings after update: %v", err)
	}
	assertRoster(t, reread.Msg.GetSettings(), []string{"Priya", "Sam"})

	// An empty roster replaces the list and is not re-seeded on the next load,
	// even after a new support entry appears.
	emptied := backupTestSettings()
	emptied.SupportPeople = nil
	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: emptied}, memberToken)); err != nil {
		t.Fatalf("update with empty roster: %v", err)
	}
	seedSupportEntryForRoster(t, database, member.ID, "00000000-0000-7000-8000-000000000004", "Alex")

	after, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken))
	if err != nil {
		t.Fatalf("get settings after emptying: %v", err)
	}
	assertRoster(t, after.Msg.GetSettings(), nil)
}

func TestSettingsRosterSeedsBeforeAdminUpdate(t *testing.T) {
	server, database := newDomainServer(t)
	adminToken := bootstrapToken(t, server)
	client := settingsClient(server)

	admin, err := database.UserByEmail("admin@example.com")
	if err != nil {
		t.Fatalf("find bootstrap account: %v", err)
	}
	seedSupportEntryForRoster(t, database, admin.ID, "00000000-0000-7000-8000-000000000011", "Priya")

	// The administrator's very first settings call is an update, which must
	// still persist the seeded marker before replacing the roster.
	update := backupTestSettings()
	update.BackupInterval = minutes(60)
	update.BackupRetention = 2
	update.SupportPeople = []string{"Priya"}
	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: update}, adminToken)); err != nil {
		t.Fatalf("admin update settings: %v", err)
	}
	loaded, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, adminToken))
	if err != nil {
		t.Fatalf("admin get settings: %v", err)
	}
	assertRoster(t, loaded.Msg.GetSettings(), []string{"Priya"})
}

func TestSettingsRosterRejectsUnauthenticatedAccess(t *testing.T) {
	server, _ := newDomainServer(t)
	client := settingsClient(server)

	_, err := client.GetSettings(context.Background(), connect.NewRequest(&wdidv1.GetSettingsRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

func TestSettingsAIKeyIsWriteOnlyAndSurvivesUnrelatedUpdates(t *testing.T) {
	const apiKey = "sk-ant-very-secret-key"
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := settingsClient(server)

	initial, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, token))
	if err != nil {
		t.Fatalf("get initial settings: %v", err)
	}
	if initial.Msg.GetSettings().GetHasAiApiKey() {
		t.Fatal("a new account must not report a stored AI key")
	}

	set, err := client.SetAIApiKey(context.Background(), withBearer(&wdidv1.SetAIApiKeyRequest{
		ApiKey: "  " + apiKey + "  ",
	}, token))
	if err != nil {
		t.Fatalf("set AI key: %v", err)
	}
	if !set.Msg.GetSettings().GetHasAiApiKey() {
		t.Fatal("the set response must report that a key is stored")
	}
	if strings.Contains(set.Msg.String(), apiKey) {
		t.Fatal("the set response must not echo the key")
	}

	loaded, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, token))
	if err != nil {
		t.Fatalf("get settings after set: %v", err)
	}
	if !loaded.Msg.GetSettings().GetHasAiApiKey() {
		t.Fatal("GetSettings must report the stored key")
	}
	if strings.Contains(loaded.Msg.String(), apiKey) {
		t.Fatal("GetSettings must never return the key")
	}

	// An ordinary settings save must neither return nor erase the key. The
	// client cannot resend it because it never received it.
	update := backupTestSettings()
	update.BackupInterval = minutes(360)
	update.BackupRetention = 30
	update.AiBaseUrl = "https://api.deepseek.com/anthropic"
	update.AiModel = "deepseek-flash"
	updated, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: update,
	}, token))
	if err != nil {
		t.Fatalf("update settings with a stored key: %v", err)
	}
	if !updated.Msg.GetSettings().GetHasAiApiKey() {
		t.Fatal("UpdateSettings must preserve the stored key")
	}
	if strings.Contains(updated.Msg.String(), apiKey) {
		t.Fatal("UpdateSettings must never return the key")
	}

	cleared, err := client.ClearAIApiKey(context.Background(), withBearer(&wdidv1.ClearAIApiKeyRequest{}, token))
	if err != nil {
		t.Fatalf("clear AI key: %v", err)
	}
	if cleared.Msg.GetSettings().GetHasAiApiKey() {
		t.Fatal("the clear response must report that no key is stored")
	}
	after, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, token))
	if err != nil {
		t.Fatalf("get settings after clear: %v", err)
	}
	if after.Msg.GetSettings().GetHasAiApiKey() {
		t.Fatal("a cleared key must stay cleared")
	}
	if strings.Contains(after.Msg.String(), apiKey) {
		t.Fatal("GetSettings must never return a cleared key")
	}
}

func TestSettingsAIKeysArePerUser(t *testing.T) {
	server, database := newDomainServer(t)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "ai-member@example.com")
	client := settingsClient(server)

	if _, err := client.SetAIApiKey(context.Background(), withBearer(&wdidv1.SetAIApiKeyRequest{
		ApiKey: "sk-ant-admin",
	}, adminToken)); err != nil {
		t.Fatalf("set admin key: %v", err)
	}

	member, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken))
	if err != nil {
		t.Fatalf("get member settings: %v", err)
	}
	if member.Msg.GetSettings().GetHasAiApiKey() {
		t.Fatal("the member must not see the administrator's key")
	}

	if _, err := client.SetAIApiKey(context.Background(), withBearer(&wdidv1.SetAIApiKeyRequest{
		ApiKey: "sk-ant-member",
	}, memberToken)); err != nil {
		t.Fatalf("set member key: %v", err)
	}
	if _, err := client.ClearAIApiKey(context.Background(), withBearer(&wdidv1.ClearAIApiKeyRequest{}, adminToken)); err != nil {
		t.Fatalf("clear admin key: %v", err)
	}

	member, err = client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, memberToken))
	if err != nil {
		t.Fatalf("get member settings after admin clear: %v", err)
	}
	if !member.Msg.GetSettings().GetHasAiApiKey() {
		t.Fatal("clearing one account's key must not clear another's")
	}
}

func TestSettingsAIKeyRejectsAnEmptyKey(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)

	_, err := settingsClient(server).SetAIApiKey(context.Background(), withBearer(&wdidv1.SetAIApiKeyRequest{
		ApiKey: "   ",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
	}
}

func TestSettingsAIKeyRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)
	client := settingsClient(server)

	if _, err := client.SetAIApiKey(context.Background(), connect.NewRequest(&wdidv1.SetAIApiKeyRequest{
		ApiKey: "sk-ant-test",
	})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("set code = %v, want unauthenticated", connect.CodeOf(err))
	}
	if _, err := client.ClearAIApiKey(context.Background(), connect.NewRequest(&wdidv1.ClearAIApiKeyRequest{})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("clear code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

// Saving a preference unrelated to backups must not touch or revalidate the
// stored backup directory. The directory may have become unusable since it was
// configured; only a change to the backup settings checks it again.
func TestUpdateSettingsDoesNotRevalidateUnchangedBackupDirectory(t *testing.T) {
	cfg := testConfig(t)
	server, _ := newDomainServerWithConfig(t, cfg)
	token := bootstrapToken(t, server)
	client := settingsClient(server)

	dir := filepath.Join(t.TempDir(), "backups")
	configured := backupTestSettings()
	configured.BackupDirectory = dir
	configured.BackupInterval = minutes(60)
	configured.BackupRetention = 2
	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: configured}, token)); err != nil {
		t.Fatalf("configure backups: %v", err)
	}

	// Break the configured path: replace the directory with a regular file, so
	// any EnsureDirectory probe would fail.
	if err := os.RemoveAll(dir); err != nil {
		t.Fatalf("remove backup directory: %v", err)
	}
	if err := os.WriteFile(dir, []byte("not a directory"), 0o600); err != nil {
		t.Fatalf("replace backup directory with a file: %v", err)
	}

	unrelated := backupTestSettings()
	unrelated.BackupDirectory = dir
	unrelated.BackupInterval = minutes(60)
	unrelated.BackupRetention = 2
	unrelated.DefaultEntryDuration = minutes(45)
	updated, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: unrelated}, token))
	if err != nil {
		t.Fatalf("saving an unrelated preference must not revalidate backups: %v", err)
	}
	if got := updated.Msg.GetSettings().GetDefaultEntryDuration().AsDuration(); got != 45*time.Minute {
		t.Fatalf("default entry duration = %s, want 45m", got)
	}
	if got := updated.Msg.GetSettings().GetBackupDirectory(); got != dir {
		t.Fatalf("backup directory = %q, want the unchanged %q", got, dir)
	}

	// A genuine backup-directory change still validates and reports the bad path.
	blocked := filepath.Join(t.TempDir(), "blocking-file")
	if err := os.WriteFile(blocked, []byte("x"), 0o600); err != nil {
		t.Fatalf("write blocking file: %v", err)
	}
	changed := backupTestSettings()
	changed.BackupDirectory = blocked
	changed.BackupInterval = minutes(60)
	changed.BackupRetention = 2
	_, err = client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: changed}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
	}
	if !strings.Contains(err.Error(), "backupDirectory") {
		t.Fatalf("error = %q, want a backupDirectory field violation", err)
	}

	// The rejected change did not replace the stored directory.
	reread, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, token))
	if err != nil {
		t.Fatalf("get settings after rejected change: %v", err)
	}
	if got := reread.Msg.GetSettings().GetBackupDirectory(); got != dir {
		t.Fatalf("backup directory = %q, want the unchanged %q", got, dir)
	}
}
