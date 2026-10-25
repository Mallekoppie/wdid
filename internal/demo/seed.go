// Package demo seeds development-only demo databases. Every record it writes
// is deterministic for a given scenario and anchor date, so a reseed produces
// the same identifiers and content. It is never used by the service.
package demo

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// Fixed demo credentials. Makefile targets, tests and docs all use these
// values; changing one means changing all of them.
const (
	DemoEmail       = "demo@wdid.local"
	DemoPassword    = "demo-password-123"
	DemoDisplayName = "Demo Admin"
)

// Options describes one seed run.
type Options struct {
	// Scenario selects the dataset. "empty" seeds only the account, default
	// settings and default taxonomy; "demo" applies the declarative fixture.
	Scenario string
	// Anchor is the calendar date every seeded timestamp derives from. A zero
	// value means today in UTC. The time-of-day component is ignored.
	Anchor time.Time
	// Fixture is an optional directory of per-domain JSON files that override
	// the embedded fixture. A missing or empty file falls back to the embedded
	// domain. Only the "demo" scenario reads it.
	Fixture string
	// Timezone overrides the fixture's (or, for "empty", the default's)
	// timezone. An empty value keeps the scenario's timezone.
	Timezone string
}

// Summary reports how many records the seed wrote. It is used for the CLI's
// stable count output.
type Summary struct {
	Users         int
	Categories    int
	Subcategories int
	Entries       int
	Notes         int
	Milestones    int
	CheckIns      int
	ActiveTimer   bool
}

type seedFunc func(*store.Store, Options) (Summary, error)

// scenarios is the registry the CLI and tests share. Later tickets add their
// fixture-backed datasets here; the command itself never needs to change.
var scenarios = map[string]seedFunc{
	"empty": seedBase,
	"demo":  seedDemo,
}

// ScenarioNames returns the known scenario names in a stable order.
func ScenarioNames() []string {
	names := make([]string, 0, len(scenarios))
	for name := range scenarios {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// ValidateScenario reports whether name is a known scenario.
func ValidateScenario(name string) error {
	if _, ok := scenarios[name]; ok {
		return nil
	}
	return fmt.Errorf("unknown scenario %q; available scenarios: %s",
		name, strings.Join(ScenarioNames(), ", "))
}

// Seed writes opts.Scenario into database. The caller is responsible for
// writing into a disposable database and swapping it into place only after
// this returns successfully.
func Seed(database *store.Store, opts Options) (Summary, error) {
	if database == nil {
		return Summary{}, errors.New("a store is required")
	}
	if err := ValidateScenario(opts.Scenario); err != nil {
		return Summary{}, err
	}
	if err := ValidateTimezone(opts.Timezone); err != nil {
		return Summary{}, err
	}

	opts.Anchor = anchorDate(opts.Anchor)
	return scenarios[opts.Scenario](database, opts)
}

// anchorDate reduces an anchor instant to midnight UTC on that calendar date.
func anchorDate(anchor time.Time) time.Time {
	if anchor.IsZero() {
		anchor = time.Now().UTC()
	}
	year, month, day := anchor.UTC().Date()
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

// seedBase writes the empty scenario: the demo admin account (with a bcrypt
// credential), default settings, and the deterministic default taxonomy. It
// writes no work entries, notes, milestones, check-ins or timer.
func seedBase(database *store.Store, opts Options) (Summary, error) {
	anchor := anchorDate(opts.Anchor)

	user, err := seedDemoAccount(database, opts.Scenario, anchor)
	if err != nil {
		return Summary{}, err
	}

	settings := domain.DefaultSettings(user.ID)
	if timezone := strings.TrimSpace(opts.Timezone); timezone != "" {
		settings.Timezone = timezone
	}
	settings.SupportPeopleSeeded = true
	settings.UpdatedAt = anchor
	if err := database.SaveSettings(settings); err != nil {
		return Summary{}, fmt.Errorf("save demo settings: %w", err)
	}

	summary := Summary{Users: 1}
	for sortOrder, seed := range store.DefaultTaxonomy() {
		category := domain.Category{
			ID:        stableID(opts.Scenario, "category", seed.Name),
			UserID:    user.ID,
			Name:      seed.Name,
			Role:      seed.Role,
			SortOrder: sortOrder,
			CreatedAt: anchor,
			UpdatedAt: anchor,
		}
		if err := database.SaveCategory(category); err != nil {
			return Summary{}, fmt.Errorf("save demo category %q: %w", seed.Name, err)
		}
		summary.Categories++

		for subOrder, name := range seed.Subcategories {
			subcategory := domain.Subcategory{
				ID:         stableID(opts.Scenario, "subcategory", seed.Name+"/"+name),
				UserID:     user.ID,
				CategoryID: category.ID,
				Name:       name,
				Status:     domain.SubcategoryActive,
				SortOrder:  subOrder,
				CreatedAt:  anchor,
				UpdatedAt:  anchor,
			}
			if err := database.SaveSubcategory(subcategory); err != nil {
				return Summary{}, fmt.Errorf("save demo subcategory %q: %w", name, err)
			}
			summary.Subcategories++
		}
	}

	return withActiveTimer(database, user.ID, summary)
}

// seedDemo writes the account and applies the declarative fixture: settings
// first (later entry slices derive LocalDate from the timezone), then the
// category/project/mode tree. Fixture-owned rows use stable IDs and
// anchor-derived timestamps, so the same scenario and anchor always produce
// identical data.
func seedDemo(database *store.Store, opts Options) (Summary, error) {
	fixture, err := LoadFixture(opts.Fixture)
	if err != nil {
		return Summary{}, err
	}

	anchor := anchorDate(opts.Anchor)
	user, err := seedDemoAccount(database, opts.Scenario, anchor)
	if err != nil {
		return Summary{}, err
	}

	settings := demoFixtureSettings(user.ID, fixture, opts.Timezone, anchor)
	if err := database.SaveSettings(settings); err != nil {
		return Summary{}, fmt.Errorf("save demo settings: %w", err)
	}

	summary := Summary{Users: 1}
	for sortOrder, seed := range fixture.Taxonomy.Categories {
		name := strings.TrimSpace(seed.Name)
		category := domain.Category{
			ID:        stableID(opts.Scenario, "category", name),
			UserID:    user.ID,
			Name:      name,
			Role:      seed.Role,
			SortOrder: sortOrder,
			CreatedAt: anchor,
			UpdatedAt: anchor,
		}
		if err := database.SaveCategory(category); err != nil {
			return Summary{}, fmt.Errorf("save demo category %q: %w", name, err)
		}
		summary.Categories++

		for subOrder, subSeed := range seed.Subcategories {
			subName := strings.TrimSpace(subSeed.Name)
			status := subSeed.Status
			if status == "" {
				status = domain.SubcategoryActive
			}
			subcategory := domain.Subcategory{
				ID:            stableID(opts.Scenario, "subcategory", name+"/"+subName),
				UserID:        user.ID,
				CategoryID:    category.ID,
				Name:          subName,
				Status:        status,
				Progress:      subSeed.Progress,
				TargetOutcome: strings.TrimSpace(subSeed.TargetOutcome),
				SortOrder:     subOrder,
				CreatedAt:     anchor,
				UpdatedAt:     anchor,
			}
			if err := database.SaveSubcategory(subcategory); err != nil {
				return Summary{}, fmt.Errorf("save demo subcategory %q: %w", subName, err)
			}
			summary.Subcategories++
		}
	}

	// Work entries derive their LocalDate from the resolved timezone. Notes and
	// milestones reference subcategories. All three are independent fixture
	// domains, and check-ins (#10) will join them without changing this order.
	location, err := time.LoadLocation(settings.Timezone)
	if err != nil {
		return Summary{}, fmt.Errorf("load demo timezone %q: %w", settings.Timezone, err)
	}
	entryCount, err := seedEntries(database, opts.Scenario, user, fixture, location, anchor)
	if err != nil {
		return Summary{}, err
	}
	summary.Entries = entryCount

	notes, err := seedNotes(database, user.ID, opts.Scenario, fixture, anchor)
	if err != nil {
		return Summary{}, err
	}
	summary.Notes = notes
	milestones, err := seedMilestones(database, user.ID, opts.Scenario, fixture, anchor)
	if err != nil {
		return Summary{}, err
	}
	summary.Milestones = milestones

	return withActiveTimer(database, user.ID, summary)
}

// demoFixtureSettings starts from the account defaults and applies only the
// fixture-owned values. The roster comes from people.json, so taxonomy,
// people and settings cannot disagree.
func demoFixtureSettings(userID string, fixture Fixture, timezoneOverride string, anchor time.Time) domain.Settings {
	settings := domain.DefaultSettings(userID)
	settings.Timezone = strings.TrimSpace(fixture.Settings.Timezone)
	settings.DailyTargetMinutes = fixture.Settings.DailyTargetMinutes
	settings.ReviewCadence = fixture.Settings.ReviewCadence
	settings.SupportPeople = append([]string(nil), fixture.People.Roster...)
	settings.SupportPeopleSeeded = true
	if timezone := strings.TrimSpace(timezoneOverride); timezone != "" {
		settings.Timezone = timezone
	}
	settings.UpdatedAt = anchor
	return settings
}

// seedDemoAccount writes the account every scenario shares through the
// seed-safe path, which skips the randomly-identified default taxonomy.
func seedDemoAccount(database *store.Store, scenario string, anchor time.Time) (domain.User, error) {
	user := demoUser(scenario, anchor)
	hash, err := bcrypt.GenerateFromPassword([]byte(DemoPassword), bcrypt.DefaultCost)
	if err != nil {
		return domain.User{}, fmt.Errorf("hash demo password: %w", err)
	}
	if err := database.CreateSeedUser(user, string(hash)); err != nil {
		return domain.User{}, fmt.Errorf("create demo account: %w", err)
	}
	return user, nil
}

// withActiveTimer records the timer state. A fresh seed never starts one, but
// reading it back keeps the Summary honest.
func withActiveTimer(database *store.Store, userID string, summary Summary) (Summary, error) {
	_, active, err := database.ActiveTimer(userID)
	if err != nil {
		return Summary{}, fmt.Errorf("read demo timer: %w", err)
	}
	summary.ActiveTimer = active
	return summary, nil
}

func demoUser(scenario string, anchor time.Time) domain.User {
	return domain.User{
		ID:          stableID(scenario, "user", DemoEmail),
		Email:       DemoEmail,
		DisplayName: DemoDisplayName,
		Role:        domain.RoleAdmin,
		CreatedAt:   anchor,
	}
}

// stableID derives a UUID from a scenario and stable labels. It never includes
// the anchor, so the same scenario has the same identifiers for every run, and
// different scenarios cannot collide.
func stableID(scenario, kind, label string) string {
	key := strings.Join([]string{"wdid", scenario, kind, label}, "/")
	return uuid.NewSHA1(uuid.NameSpaceURL, []byte(key)).String()
}
