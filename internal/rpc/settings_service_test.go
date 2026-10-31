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

// --- prompt templates -------------------------------------------------------

func findPromptTemplate(t *testing.T, templates []*wdidv1.PromptTemplate, variant wdidv1.CheckInPromptVariant) *wdidv1.PromptTemplate {
	t.Helper()
	for _, template := range templates {
		if template.GetVariant() == variant {
			return template
		}
	}
	t.Fatalf("no prompt template for variant %v in %+v", variant, templates)
	return nil
}

// TestSettingsPromptTemplatesArePerUserAndResolve proves the three variants are
// editable per account, the built-in body is the fallback, and one account can
// never see another's override.
func TestSettingsPromptTemplatesArePerUserAndResolve(t *testing.T) {
	server, database := newDomainServer(t)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "prompt-member@example.com")
	client := settingsClient(server)

	initial, err := client.ListPromptTemplates(context.Background(), withBearer(&wdidv1.ListPromptTemplatesRequest{}, adminToken))
	if err != nil {
		t.Fatalf("list prompt templates: %v", err)
	}
	if len(initial.Msg.GetTemplates()) != 3 {
		t.Fatalf("templates = %d, want one per variant", len(initial.Msg.GetTemplates()))
	}
	for _, template := range initial.Msg.GetTemplates() {
		if template.GetCustomised() {
			t.Fatalf("new account template %v is customised", template.GetVariant())
		}
		if template.GetBody() == "" {
			t.Fatalf("template %v has no built-in body", template.GetVariant())
		}
		if template.GetRules() != domain.PromptRules {
			t.Fatalf("template %v rules = %q, want the locked rules", template.GetVariant(), template.GetRules())
		}
	}

	oneOnOne := wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE
	updated, err := client.UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: oneOnOne,
		Body:    "  Write a blunt summary for the admin.  ",
	}, adminToken))
	if err != nil {
		t.Fatalf("update prompt template: %v", err)
	}
	if !updated.Msg.GetTemplate().GetCustomised() ||
		updated.Msg.GetTemplate().GetBody() != "Write a blunt summary for the admin." {
		t.Fatalf("updated template = %+v, want the trimmed custom body", updated.Msg.GetTemplate())
	}
	if updated.Msg.GetTemplate().GetRules() != domain.PromptRules {
		t.Fatalf("updated rules = %q, want the locked rules", updated.Msg.GetTemplate().GetRules())
	}

	adminTemplates, err := client.ListPromptTemplates(context.Background(), withBearer(&wdidv1.ListPromptTemplatesRequest{}, adminToken))
	if err != nil {
		t.Fatalf("list admin templates: %v", err)
	}
	if !findPromptTemplate(t, adminTemplates.Msg.GetTemplates(), oneOnOne).GetCustomised() {
		t.Fatal("the administrator's override is not reported")
	}

	// The member shares the variant but not the account's override.
	memberTemplates, err := client.ListPromptTemplates(context.Background(), withBearer(&wdidv1.ListPromptTemplatesRequest{}, memberToken))
	if err != nil {
		t.Fatalf("list member templates: %v", err)
	}
	memberOneOnOne := findPromptTemplate(t, memberTemplates.Msg.GetTemplates(), oneOnOne)
	if memberOneOnOne.GetCustomised() || strings.Contains(memberOneOnOne.GetBody(), "admin") {
		t.Fatalf("member template = %+v, want the built-in body only", memberOneOnOne)
	}

	personal := wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW
	if _, err := client.UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: personal,
		Body:    "Member-only reflection.",
	}, memberToken)); err != nil {
		t.Fatalf("update member template: %v", err)
	}

	adminAgain, err := client.ListPromptTemplates(context.Background(), withBearer(&wdidv1.ListPromptTemplatesRequest{}, adminToken))
	if err != nil {
		t.Fatalf("list admin templates again: %v", err)
	}
	if findPromptTemplate(t, adminAgain.Msg.GetTemplates(), personal).GetCustomised() {
		t.Fatal("the member's override leaked into the administrator's templates")
	}

	// The compatibility SummaryService alias resolves the caller's own body.
	adminResolved, err := summaryClient(server).GetPromptTemplate(context.Background(), withBearer(&wdidv1.GetPromptTemplateRequest{
		Variant: oneOnOne,
	}, adminToken))
	if err != nil {
		t.Fatalf("get prompt template alias: %v", err)
	}
	if !strings.Contains(adminResolved.Msg.GetTemplate(), "Write a blunt summary for the admin.") ||
		!strings.HasSuffix(adminResolved.Msg.GetTemplate(), domain.PromptRules) {
		t.Fatalf("resolved admin template = %q", adminResolved.Msg.GetTemplate())
	}
	if adminResolved.Msg.GetPromptVersion() != domain.PromptVersionCustom {
		t.Fatalf("admin prompt version = %q, want %q", adminResolved.Msg.GetPromptVersion(), domain.PromptVersionCustom)
	}

	memberResolved, err := summaryClient(server).GetPromptTemplate(context.Background(), withBearer(&wdidv1.GetPromptTemplateRequest{
		Variant: personal,
	}, memberToken))
	if err != nil {
		t.Fatalf("get member alias template: %v", err)
	}
	if !strings.Contains(memberResolved.Msg.GetTemplate(), "Member-only reflection.") ||
		memberResolved.Msg.GetPromptVersion() != domain.PromptVersionCustom {
		t.Fatalf("member resolved template = %q/%q", memberResolved.Msg.GetTemplate(), memberResolved.Msg.GetPromptVersion())
	}

	// Reset restores the built-in body and drops the custom label.
	reset, err := client.ResetPromptTemplate(context.Background(), withBearer(&wdidv1.ResetPromptTemplateRequest{
		Variant: oneOnOne,
	}, adminToken))
	if err != nil {
		t.Fatalf("reset prompt template: %v", err)
	}
	if reset.Msg.GetTemplate().GetCustomised() || strings.Contains(reset.Msg.GetTemplate().GetBody(), "blunt summary") {
		t.Fatalf("reset template = %+v, want the built-in body", reset.Msg.GetTemplate())
	}
	adminResolved, err = summaryClient(server).GetPromptTemplate(context.Background(), withBearer(&wdidv1.GetPromptTemplateRequest{
		Variant: oneOnOne,
	}, adminToken))
	if err != nil {
		t.Fatalf("get reset template: %v", err)
	}
	if adminResolved.Msg.GetPromptVersion() != domain.PromptVersion {
		t.Fatalf("prompt version after reset = %q, want %q", adminResolved.Msg.GetPromptVersion(), domain.PromptVersion)
	}
}

// TestSettingsUpdatePromptTemplateRejectsBlankAndOversizeBodies proves a blank
// save is a mistake rather than "use the built-in" (that is Reset), and an
// over-long body is refused.
func TestSettingsUpdatePromptTemplateRejectsBlankAndOversizeBodies(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := settingsClient(server)
	variant := wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE

	for name, body := range map[string]string{"empty": "", "spaces": "   ", "tabs": "\t\r\n "} {
		t.Run(name, func(t *testing.T) {
			_, err := client.UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
				Variant: variant,
				Body:    body,
			}, token))
			if connect.CodeOf(err) != connect.CodeInvalidArgument {
				t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
			}
			if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "body" {
				t.Fatalf("field violations = %v, want body", fields)
			}
			if !strings.Contains(err.Error(), "Reset") {
				t.Fatalf("error = %q, want it to point at Reset", err)
			}
		})
	}

	_, err := client.UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: variant,
		Body:    strings.Repeat("x", 20001),
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("oversize code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "body" {
		t.Fatalf("oversize field violations = %v, want body", fields)
	}

	// A body at the cap is accepted.
	if _, err := client.UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: variant,
		Body:    strings.Repeat("x", 20000),
	}, token)); err != nil {
		t.Fatalf("body at the cap: %v", err)
	}

	_, err = client.UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: wdidv1.CheckInPromptVariant(99),
		Body:    "anything",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("unknown variant code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "variant" {
		t.Fatalf("unknown variant fields = %v, want variant", fields)
	}

	if _, err := client.ListPromptTemplates(context.Background(), connect.NewRequest(&wdidv1.ListPromptTemplatesRequest{})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("list code = %v, want unauthenticated", connect.CodeOf(err))
	}
	if _, err := client.UpdatePromptTemplate(context.Background(), connect.NewRequest(&wdidv1.UpdatePromptTemplateRequest{
		Variant: variant,
		Body:    "anything",
	})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("update code = %v, want unauthenticated", connect.CodeOf(err))
	}
	if _, err := client.ResetPromptTemplate(context.Background(), connect.NewRequest(&wdidv1.ResetPromptTemplateRequest{
		Variant: variant,
	})); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("reset code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

// TestSettingsPromptTemplatesSurviveUnrelatedUpdates proves an ordinary
// settings save (which cannot carry prompt templates) never wipes the stored
// overrides.
func TestSettingsPromptTemplatesSurviveUnrelatedUpdates(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := settingsClient(server)
	variant := wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW

	if _, err := client.UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: variant,
		Body:    "Keep the evidence tight.",
	}, token)); err != nil {
		t.Fatalf("update prompt template: %v", err)
	}

	update := backupTestSettings()
	update.BackupInterval = minutes(360)
	update.BackupRetention = 30
	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: update,
	}, token)); err != nil {
		t.Fatalf("update settings: %v", err)
	}

	templates, err := client.ListPromptTemplates(context.Background(), withBearer(&wdidv1.ListPromptTemplatesRequest{}, token))
	if err != nil {
		t.Fatalf("list templates after settings save: %v", err)
	}
	template := findPromptTemplate(t, templates.Msg.GetTemplates(), variant)
	if !template.GetCustomised() || template.GetBody() != "Keep the evidence tight." {
		t.Fatalf("template after an unrelated save = %+v, want the override preserved", template)
	}
}
