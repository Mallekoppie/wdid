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
	assertSummary(t, summary, 3, 10, 0, 0)
}

func TestSeedDemoAppliesTheFixture(t *testing.T) {
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

	type wantSubcategory struct {
		name     string
		status   domain.SubcategoryStatus
		progress int
		outcome  string
	}
	wantTaxonomy := []struct {
		name          string
		role          domain.CategoryRole
		subcategories []wantSubcategory
	}{
		{
			name: "Client Delivery",
			role: domain.CategoryRoleInitiative,
			subcategories: []wantSubcategory{
				{name: "Acme migration", status: domain.SubcategoryActive, progress: 60, outcome: "Acme's production workloads run entirely on the new platform."},
				{name: "Globex onboarding", status: domain.SubcategoryActive, progress: 35, outcome: "Globex is live and its team can operate without hand-holding."},
				{name: "Initech audit", status: domain.SubcategoryDone, progress: 100, outcome: "Audit findings are delivered and signed off."},
			},
		},
		{
			name: "Platform",
			role: domain.CategoryRoleInitiative,
			subcategories: []wantSubcategory{
				{name: "Auth overhaul", status: domain.SubcategoryActive, progress: 45, outcome: "One auth path serves every client with session rotation."},
				{name: "Search relevance", status: domain.SubcategoryBlocked, progress: 25, outcome: "The benchmark query set returns its expected result in the top three."},
				{name: "Observability", status: domain.SubcategoryPlanned, progress: 0, outcome: "Every request is traceable end to end with actionable alerts."},
			},
		},
		{
			name: "Growth",
			role: domain.CategoryRoleInitiative,
			subcategories: []wantSubcategory{
				{name: "Self-serve trial", status: domain.SubcategoryActive, progress: 70, outcome: "A new account reaches first value without human help."},
				{name: "Pricing experiment", status: domain.SubcategoryPlanned, progress: 10, outcome: "One pricing model is chosen from the experiment results."},
			},
		},
		{
			name: "Support",
			role: domain.CategoryRoleSupport,
			subcategories: []wantSubcategory{
				{name: "Mentoring", status: domain.SubcategoryActive},
				{name: "Pairing", status: domain.SubcategoryActive},
				{name: "Incident support", status: domain.SubcategoryActive},
				{name: "Code review", status: domain.SubcategoryActive},
				{name: "1:1", status: domain.SubcategoryActive},
			},
		},
		{
			name: "Other",
			role: domain.CategoryRoleOther,
			subcategories: []wantSubcategory{
				{name: "Meetings", status: domain.SubcategoryActive},
				{name: "Admin", status: domain.SubcategoryActive},
				{name: "Learning", status: domain.SubcategoryActive},
			},
		},
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
			t.Fatalf("%s subcategories = %+v, want %d", category.Name, subcategories, len(want.subcategories))
		}
		for j, wantSub := range want.subcategories {
			subcategory := subcategories[j]
			if subcategory.Name != wantSub.name || subcategory.CategoryID != category.ID {
				t.Fatalf("%s subcategory %d = %+v, want %s", category.Name, j, subcategory, wantSub.name)
			}
			if subcategory.Status != wantSub.status ||
				subcategory.Progress != wantSub.progress ||
				subcategory.TargetOutcome != wantSub.outcome {
				t.Fatalf("%s subcategory %d = %+v, want status %s progress %d outcome %q",
					category.Name, j, subcategory, wantSub.status, wantSub.progress, wantSub.outcome)
			}
			if subcategory.SortOrder != j {
				t.Fatalf("%s subcategory %d sort order = %d, want %d", category.Name, j, subcategory.SortOrder, j)
			}
			if !subcategory.CreatedAt.Equal(testAnchor) || !subcategory.UpdatedAt.Equal(testAnchor) {
				t.Fatalf("%s subcategory %d timestamps = %s/%s, want anchor %s",
					category.Name, j, subcategory.CreatedAt, subcategory.UpdatedAt, testAnchor)
			}
		}
	}

	settings, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	wantRoster := []string{"Priya", "Sam", "Alex", "Jordan", "Mei", "Diego", "Noor", "Chris"}
	if settings.Timezone != "UTC" ||
		settings.DailyTargetMinutes != 450 ||
		settings.ReviewCadence != domain.ReviewCadenceWeekly {
		t.Fatalf("settings = %+v, want UTC/450/weekly", settings)
	}
	if !reflect.DeepEqual(settings.SupportPeople, wantRoster) || !settings.SupportPeopleSeeded {
		t.Fatalf("support people = %v (seeded %v), want the fixture roster", settings.SupportPeople, settings.SupportPeopleSeeded)
	}
	if !settings.UpdatedAt.Equal(testAnchor) {
		t.Fatalf("settings updated at = %s, want anchor %s", settings.UpdatedAt, testAnchor)
	}

	assertSummary(t, summary, 5, 16, 11, 20)
}

func TestSeedDemoAppliesFixtureDirectoryOverrides(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "settings.json", `{
		"timezone": "Europe/Amsterdam",
		"dailyTargetMinutes": 300,
		"reviewCadence": "monthly"
	}`)
	writeFixtureFile(t, dir, "people.json", `{"roster": ["Ada", "Grace"]}`)

	database := openStore(t, filepath.Join(t.TempDir(), "override.db"))
	t.Cleanup(func() { _ = database.Close() })

	if _, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: testAnchor, Fixture: dir}); err != nil {
		t.Fatalf("seed with fixture override: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	settings, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	if settings.Timezone != "Europe/Amsterdam" ||
		settings.DailyTargetMinutes != 300 ||
		settings.ReviewCadence != domain.ReviewCadenceMonthly ||
		!reflect.DeepEqual(settings.SupportPeople, []string{"Ada", "Grace"}) {
		t.Fatalf("settings = %+v, want the fixture directory overrides", settings)
	}

	// taxonomy.json is absent from the override directory, so it falls back to
	// the embedded domain.
	categories, err := database.Categories(user.ID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	if len(categories) != 5 {
		t.Fatalf("categories = %d, want the embedded 5", len(categories))
	}
}

func TestSeedTimezoneOverrideBeatsTheFixture(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "timezone.db"))
	t.Cleanup(func() { _ = database.Close() })

	if _, err := demo.Seed(database, demo.Options{
		Scenario: "demo",
		Anchor:   testAnchor,
		Timezone: "Asia/Tokyo",
	}); err != nil {
		t.Fatalf("seed with timezone override: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	settings, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	if settings.Timezone != "Asia/Tokyo" {
		t.Fatalf("timezone = %q, want the --timezone override", settings.Timezone)
	}
	if settings.DailyTargetMinutes != 450 || settings.ReviewCadence != domain.ReviewCadenceWeekly {
		t.Fatalf("settings = %+v, want the rest of the fixture unchanged", settings)
	}
}

func TestSeedRejectsAnInvalidTimezone(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "bad-timezone.db"))
	t.Cleanup(func() { _ = database.Close() })

	_, err := demo.Seed(database, demo.Options{
		Scenario: "demo",
		Anchor:   testAnchor,
		Timezone: "Mars/Olympus",
	})
	if err == nil || !strings.Contains(err.Error(), "timezone") {
		t.Fatalf("error = %v, want an invalid timezone error", err)
	}
}

func TestSeedRejectsAMissingFixtureDirectory(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "bad-fixture.db"))
	t.Cleanup(func() { _ = database.Close() })

	_, err := demo.Seed(database, demo.Options{
		Scenario: "demo",
		Anchor:   testAnchor,
		Fixture:  filepath.Join(t.TempDir(), "absent"),
	})
	if err == nil || !strings.Contains(err.Error(), "fixture") {
		t.Fatalf("error = %v, want a fixture path error", err)
	}
}

func TestSeedIsDeterministicForTheSameAnchor(t *testing.T) {
	for _, scenario := range []string{"empty", "demo"} {
		t.Run(scenario, func(t *testing.T) {
			first := seedSnapshot(t, filepath.Join(t.TempDir(), "first.db"), scenario)
			second := seedSnapshot(t, filepath.Join(t.TempDir(), "second.db"), scenario)

			if !reflect.DeepEqual(first, second) {
				t.Fatalf("same anchor produced different %s data:\nfirst:  %+v\nsecond: %+v", scenario, first, second)
			}
		})
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
	ID            string
	CategoryID    string
	Name          string
	Status        domain.SubcategoryStatus
	Progress      int
	TargetOutcome string
	SortOrder     int
	CreatedAt     string
	UpdatedAt     string
}

type settingsSnapshot struct {
	Timezone            string
	WeekStart           int
	DailyTargetMinutes  int
	ReviewCadence       domain.ReviewCadence
	SupportPeople       []string
	SupportPeopleSeeded bool
	UpdatedAt           string
}

func seedSnapshot(t *testing.T, path, scenario string) snapshot {
	t.Helper()

	database := openStore(t, path)
	defer func() {
		if err := database.Close(); err != nil {
			t.Fatalf("close store: %v", err)
		}
	}()

	if _, err := demo.Seed(database, demo.Options{Scenario: scenario, Anchor: testAnchor}); err != nil {
		t.Fatalf("seed %s scenario: %v", scenario, err)
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
			Timezone:            settings.Timezone,
			WeekStart:           settings.WeekStart,
			DailyTargetMinutes:  settings.DailyTargetMinutes,
			ReviewCadence:       settings.ReviewCadence,
			SupportPeople:       settings.SupportPeople,
			SupportPeopleSeeded: settings.SupportPeopleSeeded,
			UpdatedAt:           settings.UpdatedAt.Format(time.RFC3339Nano),
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
			ID:            subcategory.ID,
			CategoryID:    subcategory.CategoryID,
			Name:          subcategory.Name,
			Status:        subcategory.Status,
			Progress:      subcategory.Progress,
			TargetOutcome: subcategory.TargetOutcome,
			SortOrder:     subcategory.SortOrder,
			CreatedAt:     subcategory.CreatedAt.Format(time.RFC3339Nano),
			UpdatedAt:     subcategory.UpdatedAt.Format(time.RFC3339Nano),
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

func assertSummary(t *testing.T, summary demo.Summary, categories, subcategories, notes, milestones int) {
	t.Helper()

	if summary.Users != 1 ||
		summary.Categories != categories ||
		summary.Subcategories != subcategories ||
		summary.Entries != 0 ||
		summary.Notes != notes ||
		summary.Milestones != milestones ||
		summary.CheckIns != 0 ||
		summary.ActiveTimer {
		t.Fatalf("summary = %+v, want 1 user, %d categories, %d subcategories, %d notes, %d milestones and no entries/check-ins",
			summary, categories, subcategories, notes, milestones)
	}
}
