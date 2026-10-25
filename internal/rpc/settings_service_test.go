package rpc_test

import (
	"context"
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
		Person:      person,
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
