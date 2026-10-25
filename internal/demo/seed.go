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
	// the embedded fixture. A missing file falls back to the embedded domain;
	// an empty or malformed file is a JSON decode error. Only the "demo"
	// scenario reads it.
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

	taxonomy := make([]taxonomySeed, 0, len(store.DefaultTaxonomy()))
	for _, seed := range store.DefaultTaxonomy() {
		subcategories := make([]taxonomySeedSubcategory, 0, len(seed.Subcategories))
		for _, name := range seed.Subcategories {
			subcategories = append(subcategories, taxonomySeedSubcategory{Name: name})
		}
		taxonomy = append(taxonomy, taxonomySeed{
			Name:          seed.Name,
			Role:          seed.Role,
			Subcategories: subcategories,
		})
	}
	summary, err := seedTaxonomy(database, opts.Scenario, user.ID, anchor, taxonomy)
	if err != nil {
		return Summary{}, err
	}
	summary.Users = 1

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

	taxonomy := make([]taxonomySeed, 0, len(fixture.Taxonomy.Categories))
	for _, seed := range fixture.Taxonomy.Categories {
		subcategories := make([]taxonomySeedSubcategory, 0, len(seed.Subcategories))
		for _, subSeed := range seed.Subcategories {
			subcategories = append(subcategories, taxonomySeedSubcategory{
				Name:          subSeed.Name,
				Status:        subSeed.Status,
				Progress:      subSeed.Progress,
				TargetOutcome: subSeed.TargetOutcome,
			})
		}
		taxonomy = append(taxonomy, taxonomySeed{
			Name:          seed.Name,
			Role:          seed.Role,
			Subcategories: subcategories,
		})
	}
	summary, err := seedTaxonomy(database, opts.Scenario, user.ID, anchor, taxonomy)
	if err != nil {
		return Summary{}, err
	}
	summary.Users = 1

	// Work entries derive their LocalDate from the resolved timezone. Check-ins
	// run next because each one snapshots the authoritative report for its
	// period. Notes and milestones reference subcategories independently.
	location, err := time.LoadLocation(settings.Timezone)
	if err != nil {
		return Summary{}, fmt.Errorf("load demo timezone %q: %w", settings.Timezone, err)
	}
	entryCount, err := seedEntries(database, opts.Scenario, user, fixture, location, anchor)
	if err != nil {
		return Summary{}, err
	}
	summary.Entries = entryCount

	checkIns, err := seedCheckIns(database, opts.Scenario, user.ID, fixture, anchor)
	if err != nil {
		return Summary{}, err
	}
	summary.CheckIns = checkIns

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

// taxonomySeed is one category to write, with its subcategories in display
// order. It is the shared shape the built-in taxonomy and the fixture are
// converted into before seeding.
type taxonomySeed struct {
	Name          string
	Role          domain.CategoryRole
	Subcategories []taxonomySeedSubcategory
}

// taxonomySeedSubcategory is one subcategory below a taxonomySeed. An empty
// status means active.
type taxonomySeedSubcategory struct {
	Name          string
	Status        domain.SubcategoryStatus
	Progress      int
	TargetOutcome string
}

// seedTaxonomy writes the category/subcategory tree shared by both scenarios.
// It preserves the input order as the sort order, derives IDs through the
// stable helpers, defaults an empty status to active, and reports the counts.
// The production account path (seedUserTx) is intentionally separate.
func seedTaxonomy(
	database *store.Store,
	scenario, userID string,
	anchor time.Time,
	taxonomy []taxonomySeed,
) (Summary, error) {
	var summary Summary
	for sortOrder, seed := range taxonomy {
		name := strings.TrimSpace(seed.Name)
		category := domain.Category{
			ID:        stableCategoryID(scenario, name),
			UserID:    userID,
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
				ID:            stableSubcategoryID(scenario, name, subName),
				UserID:        userID,
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
	return summary, nil
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
