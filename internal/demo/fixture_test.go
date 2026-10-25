package demo_test

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/Mallekoppie/wdid/internal/demo"
	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestLoadFixtureReadsTheEmbeddedDomains(t *testing.T) {
	fixture, err := demo.LoadFixture("")
	if err != nil {
		t.Fatalf("load embedded fixture: %v", err)
	}

	wantCategories := []struct {
		name          string
		role          domain.CategoryRole
		subcategories []string
	}{
		{name: "Client Delivery", role: domain.CategoryRoleInitiative, subcategories: []string{"Acme migration", "Globex onboarding", "Initech audit"}},
		{name: "Platform", role: domain.CategoryRoleInitiative, subcategories: []string{"Auth overhaul", "Search relevance", "Observability"}},
		{name: "Growth", role: domain.CategoryRoleInitiative, subcategories: []string{"Self-serve trial", "Pricing experiment"}},
		{name: "Support", role: domain.CategoryRoleSupport, subcategories: []string{"Mentoring", "Pairing", "Incident support", "Code review", "1:1"}},
		{name: "Other", role: domain.CategoryRoleOther, subcategories: []string{"Meetings", "Admin", "Learning"}},
	}

	if len(fixture.Taxonomy.Categories) != len(wantCategories) {
		t.Fatalf("categories = %+v, want %d", fixture.Taxonomy.Categories, len(wantCategories))
	}
	for i, want := range wantCategories {
		category := fixture.Taxonomy.Categories[i]
		if category.Name != want.name || category.Role != want.role {
			t.Fatalf("category %d = %s/%s, want %s/%s", i, category.Name, category.Role, want.name, want.role)
		}
		names := make([]string, 0, len(category.Subcategories))
		for _, subcategory := range category.Subcategories {
			names = append(names, subcategory.Name)
		}
		if !reflect.DeepEqual(names, want.subcategories) {
			t.Fatalf("%s subcategories = %v, want %v", category.Name, names, want.subcategories)
		}
	}

	wantRoster := []string{"Priya", "Sam", "Alex", "Jordan", "Mei", "Diego", "Noor", "Chris"}
	if !reflect.DeepEqual(fixture.People.Roster, wantRoster) {
		t.Fatalf("roster = %v, want %v", fixture.People.Roster, wantRoster)
	}

	if fixture.Settings.Timezone != "UTC" ||
		fixture.Settings.DailyTargetMinutes != 450 ||
		fixture.Settings.ReviewCadence != domain.ReviewCadenceWeekly {
		t.Fatalf("settings = %+v, want UTC/450/weekly", fixture.Settings)
	}
}

func TestLoadFixtureOverridesOnlyTheFilesPresent(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "settings.json", `{
		"timezone": "Europe/Amsterdam",
		"dailyTargetMinutes": 300,
		"reviewCadence": "monthly"
	}`)

	fixture, err := demo.LoadFixture(dir)
	if err != nil {
		t.Fatalf("load overridden fixture: %v", err)
	}

	if fixture.Settings.Timezone != "Europe/Amsterdam" ||
		fixture.Settings.DailyTargetMinutes != 300 ||
		fixture.Settings.ReviewCadence != domain.ReviewCadenceMonthly {
		t.Fatalf("settings = %+v, want the directory override", fixture.Settings)
	}

	// Missing files fall back to the embedded domain, not to an empty value.
	if len(fixture.Taxonomy.Categories) != 5 {
		t.Fatalf("categories = %d, want the embedded 5", len(fixture.Taxonomy.Categories))
	}
	if len(fixture.People.Roster) != 8 {
		t.Fatalf("roster = %v, want the embedded 8", fixture.People.Roster)
	}
}

func TestLoadFixtureRejectsAnInvalidDomainFile(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "people.json", `{"roster": [`)

	_, err := demo.LoadFixture(dir)
	if err == nil {
		t.Fatal("invalid people.json loaded successfully")
	}
	if !strings.Contains(err.Error(), "people.json") {
		t.Fatalf("error = %q, want the offending filename", err)
	}
}

func TestLoadFixtureRejectsUnknownFields(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "settings.json", `{
		"timezone": "UTC",
		"dailyTargetMinutes": 450,
		"reviewCadence": "weekly",
		"surprise": true
	}`)

	_, err := demo.LoadFixture(dir)
	if err == nil || !strings.Contains(err.Error(), "surprise") {
		t.Fatalf("error = %v, want the unknown field named", err)
	}
}

func TestLoadFixtureRejectsAMissingDirectory(t *testing.T) {
	_, err := demo.LoadFixture(filepath.Join(t.TempDir(), "absent"))
	if err == nil {
		t.Fatal("missing fixture directory loaded successfully")
	}
	if !strings.Contains(err.Error(), "fixture") {
		t.Fatalf("error = %q, want a fixture path error", err)
	}
}

func TestLoadFixtureRejectsAFilePath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := os.WriteFile(path, []byte(`{}`), 0o600); err != nil {
		t.Fatalf("write fixture file: %v", err)
	}

	_, err := demo.LoadFixture(path)
	if err == nil || !strings.Contains(err.Error(), "not a directory") {
		t.Fatalf("error = %v, want a not-a-directory error", err)
	}
}

func writeFixtureFile(t *testing.T, dir, name, content string) {
	t.Helper()

	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
		t.Fatalf("write %s: %v", name, err)
	}
}
