package demo_test

import (
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/demo"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

var testAnchor = time.Date(2026, time.March, 9, 0, 0, 0, 0, time.UTC)

// openStore opens a store for a test. The platform database handle is global,
// so callers must close the store before opening another one.
func openStore(t *testing.T, path string) *store.Store {
	t.Helper()

	database, err := store.Open(config.Config{DBPath: path, StorageOnly: true})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	return database
}

func TestSeedEmptyCreatesAccountSettingsAndTaxonomy(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "empty.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{Scenario: "empty", Anchor: testAnchor})
	if err != nil {
		t.Fatalf("seed empty scenario: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	if user.DisplayName != demo.DemoDisplayName {
		t.Fatalf("display name = %q, want %q", user.DisplayName, demo.DemoDisplayName)
	}
	if user.Role != domain.RoleAdmin {
		t.Fatalf("role = %q, want admin", user.Role)
	}
	if !user.CreatedAt.Equal(testAnchor) {
		t.Fatalf("created at = %s, want anchor %s", user.CreatedAt, testAnchor)
	}

	hash, err := database.PasswordHash(user.ID)
	if err != nil {
		t.Fatalf("read password hash: %v", err)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(demo.DemoPassword)); err != nil {
		t.Fatalf("documented demo password does not verify: %v", err)
	}

	// Literal expectations: the empty scenario must match the default taxonomy
	// the production account path seeds, not just itself.
	wantTaxonomy := []struct {
		name          string
		role          domain.CategoryRole
		subcategories []string
	}{
		{name: "Initiatives", role: domain.CategoryRoleInitiative},
		{name: "Support", role: domain.CategoryRoleSupport, subcategories: []string{"Review", "Pair", "Unblock", "Mentor", "Incident", "Other"}},
		{name: "Other", role: domain.CategoryRoleOther, subcategories: []string{"Meetings", "Admin", "Learning", "Unplanned"}},
	}

	categories, err := database.Categories(user.ID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	if len(categories) != len(wantTaxonomy) {
		t.Fatalf("categories = %+v, want %d", categories, len(wantTaxonomy))
	}

	for i, want := range wantTaxonomy {
		category := categories[i]
		if category.Name != want.name || category.Role != want.role {
			t.Fatalf("category %d = %s/%s, want %s/%s", i, category.Name, category.Role, want.name, want.role)
		}
		if category.SortOrder != i {
			t.Fatalf("%s sort order = %d, want %d", category.Name, category.SortOrder, i)
		}
		if !category.CreatedAt.Equal(testAnchor) || !category.UpdatedAt.Equal(testAnchor) {
			t.Fatalf("%s timestamps = %s/%s, want anchor %s", category.Name, category.CreatedAt, category.UpdatedAt, testAnchor)
		}

		subcategories, err := database.Subcategories(user.ID, category.ID)
		if err != nil {
			t.Fatalf("list %s subcategories: %v", category.Name, err)
		}
		if len(subcategories) != len(want.subcategories) {
			t.Fatalf("%s subcategories = %+v, want %v", category.Name, subcategories, want.subcategories)
		}
		for j, name := range want.subcategories {
			subcategory := subcategories[j]
			if subcategory.Name != name || subcategory.CategoryID != category.ID {
				t.Fatalf("%s subcategory %d = %+v, want %s", category.Name, j, subcategory, name)
			}
			if subcategory.Status != domain.SubcategoryActive || subcategory.SortOrder != j {
				t.Fatalf("%s subcategory %d = %+v, want an active default", category.Name, j, subcategory)
			}
		}
	}

	settings, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	if settings.Timezone != "UTC" ||
		settings.WeekStart != int(time.Monday) ||
		settings.DailyTargetMinutes != 450 ||
		settings.ReviewCadence != domain.ReviewCadenceOff ||
		settings.LongTimerMinutes != 240 ||
		settings.DefaultDurationMinutes != 30 ||
		settings.BackupIntervalHours != 6 ||
		settings.BackupRetention != 30 ||
		settings.Theme != domain.ThemeSystem ||
		settings.Density != domain.DensityComfortable {
		t.Fatalf("settings = %+v, want the default settings", settings)
	}
	if !settings.UpdatedAt.Equal(testAnchor) {
		t.Fatalf("settings updated at = %s, want anchor %s", settings.UpdatedAt, testAnchor)
	}

	assertNoRows(t, database, user.ID)
	assertSummary(t, summary, 0)
}

func TestSeedDemoIsRegisteredAsAnEmptyBaseUntilFixtureLands(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "demo.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: testAnchor})
	if err != nil {
		t.Fatalf("seed demo scenario: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	categories, err := database.Categories(user.ID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	if len(categories) != 3 {
		t.Fatalf("demo categories = %d, want the empty base's 3", len(categories))
	}
	assertNoRows(t, database, user.ID)
	assertSummary(t, summary, 0)
}

func TestSeedIsDeterministicForTheSameAnchor(t *testing.T) {
	first := seedSnapshot(t, filepath.Join(t.TempDir(), "first.db"))
	second := seedSnapshot(t, filepath.Join(t.TempDir(), "second.db"))

	if !reflect.DeepEqual(first, second) {
		t.Fatalf("same anchor produced different data:\nfirst:  %+v\nsecond: %+v", first, second)
	}
}

func TestSeedRejectsAnUnknownScenario(t *testing.T) {
	if err := demo.ValidateScenario("empty"); err != nil {
		t.Fatalf("empty should be a known scenario: %v", err)
	}
	if err := demo.ValidateScenario("demo"); err != nil {
		t.Fatalf("demo should be a known scenario: %v", err)
	}

	err := demo.ValidateScenario("nope")
	if err == nil || !strings.Contains(err.Error(), "unknown scenario") {
		t.Fatalf("ValidateScenario(nope) = %v, want an unknown scenario error", err)
	}
	if !strings.Contains(err.Error(), "empty") || !strings.Contains(err.Error(), "demo") {
		t.Fatalf("ValidateScenario(nope) = %v, want the valid scenario names", err)
	}
}

type snapshot struct {
	UserID         string
	UserCreatedAt  string
	Categories     []categorySnapshot
	Subcategories  []subcategorySnapshot
	Settings       settingsSnapshot
	EntryCount     int
	NoteCount      int
	MilestoneCount int
	CheckInCount   int
	HasActiveTimer bool
}

type categorySnapshot struct {
	ID        string
	Name      string
	Role      domain.CategoryRole
	SortOrder int
	CreatedAt string
	UpdatedAt string
}

type subcategorySnapshot struct {
	ID         string
	CategoryID string
	Name       string
	Status     domain.SubcategoryStatus
	SortOrder  int
	CreatedAt  string
	UpdatedAt  string
}

type settingsSnapshot struct {
	Timezone           string
	WeekStart          int
	DailyTargetMinutes int
	ReviewCadence      domain.ReviewCadence
	UpdatedAt          string
}

func seedSnapshot(t *testing.T, path string) snapshot {
	t.Helper()

	database := openStore(t, path)
	defer func() {
		if err := database.Close(); err != nil {
			t.Fatalf("close store: %v", err)
		}
	}()

	if _, err := demo.Seed(database, demo.Options{Scenario: "empty", Anchor: testAnchor}); err != nil {
		t.Fatalf("seed empty scenario: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	categories, err := database.Categories(user.ID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	subcategories, err := database.Subcategories(user.ID, "")
	if err != nil {
		t.Fatalf("list subcategories: %v", err)
	}
	settings, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	entries, err := database.WorkEntries(user.ID, store.WorkEntryFilter{})
	if err != nil {
		t.Fatalf("list entries: %v", err)
	}
	notes, err := database.Notes(user.ID, store.NoteFilter{})
	if err != nil {
		t.Fatalf("list notes: %v", err)
	}
	milestones, err := database.Milestones(user.ID, "")
	if err != nil {
		t.Fatalf("list milestones: %v", err)
	}
	checkIns, err := database.CheckIns(user.ID, "")
	if err != nil {
		t.Fatalf("list check-ins: %v", err)
	}
	_, hasTimer, err := database.ActiveTimer(user.ID)
	if err != nil {
		t.Fatalf("read active timer: %v", err)
	}

	result := snapshot{
		UserID:         user.ID,
		UserCreatedAt:  user.CreatedAt.Format(time.RFC3339Nano),
		EntryCount:     len(entries),
		NoteCount:      len(notes),
		MilestoneCount: len(milestones),
		CheckInCount:   len(checkIns),
		HasActiveTimer: hasTimer,
		Settings: settingsSnapshot{
			Timezone:           settings.Timezone,
			WeekStart:          settings.WeekStart,
			DailyTargetMinutes: settings.DailyTargetMinutes,
			ReviewCadence:      settings.ReviewCadence,
			UpdatedAt:          settings.UpdatedAt.Format(time.RFC3339Nano),
		},
	}
	for _, category := range categories {
		result.Categories = append(result.Categories, categorySnapshot{
			ID:        category.ID,
			Name:      category.Name,
			Role:      category.Role,
			SortOrder: category.SortOrder,
			CreatedAt: category.CreatedAt.Format(time.RFC3339Nano),
			UpdatedAt: category.UpdatedAt.Format(time.RFC3339Nano),
		})
	}
	for _, subcategory := range subcategories {
		result.Subcategories = append(result.Subcategories, subcategorySnapshot{
			ID:         subcategory.ID,
			CategoryID: subcategory.CategoryID,
			Name:       subcategory.Name,
			Status:     subcategory.Status,
			SortOrder:  subcategory.SortOrder,
			CreatedAt:  subcategory.CreatedAt.Format(time.RFC3339Nano),
			UpdatedAt:  subcategory.UpdatedAt.Format(time.RFC3339Nano),
		})
	}
	return result
}

func assertNoRows(t *testing.T, database *store.Store, userID string) {
	t.Helper()

	entries, err := database.WorkEntries(userID, store.WorkEntryFilter{})
	if err != nil {
		t.Fatalf("list entries: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("entries = %+v, want none", entries)
	}

	notes, err := database.Notes(userID, store.NoteFilter{})
	if err != nil {
		t.Fatalf("list notes: %v", err)
	}
	if len(notes) != 0 {
		t.Fatalf("notes = %+v, want none", notes)
	}

	milestones, err := database.Milestones(userID, "")
	if err != nil {
		t.Fatalf("list milestones: %v", err)
	}
	if len(milestones) != 0 {
		t.Fatalf("milestones = %+v, want none", milestones)
	}

	checkIns, err := database.CheckIns(userID, "")
	if err != nil {
		t.Fatalf("list check-ins: %v", err)
	}
	if len(checkIns) != 0 {
		t.Fatalf("check-ins = %+v, want none", checkIns)
	}

	if _, active, err := database.ActiveTimer(userID); err != nil {
		t.Fatalf("read active timer: %v", err)
	} else if active {
		t.Fatal("active timer = running, want none")
	}
}

func assertSummary(t *testing.T, summary demo.Summary, extraRows int) {
	t.Helper()

	if summary.Users != 1 ||
		summary.Categories != 3 ||
		summary.Subcategories != 10 ||
		summary.Entries != extraRows ||
		summary.Notes != 0 ||
		summary.Milestones != 0 ||
		summary.CheckIns != 0 ||
		summary.ActiveTimer {
		t.Fatalf("summary = %+v, want 1 user, 3 categories, 10 subcategories and no rows", summary)
	}
}
