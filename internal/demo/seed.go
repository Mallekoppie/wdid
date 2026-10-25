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
	// settings and default taxonomy.
	Scenario string
	// Anchor is the calendar date every seeded timestamp derives from. A zero
	// value means today in UTC. The time-of-day component is ignored.
	Anchor time.Time
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
	// demo is deliberately the same bare base until ticket #7 adds its
	// declarative fixture. It is registered now so the command and docs have
	// their final shape.
	"demo": seedBase,
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

// seedBase writes the dataset every scenario shares: the demo admin account
// (with a bcrypt credential), default settings, and the deterministic default
// taxonomy. It writes no work entries, notes, milestones, check-ins or timer.
func seedBase(database *store.Store, opts Options) (Summary, error) {
	anchor := anchorDate(opts.Anchor)

	user := demoUser(opts.Scenario, anchor)
	hash, err := bcrypt.GenerateFromPassword([]byte(DemoPassword), bcrypt.DefaultCost)
	if err != nil {
		return Summary{}, fmt.Errorf("hash demo password: %w", err)
	}
	if err := database.CreateSeedUser(user, string(hash)); err != nil {
		return Summary{}, fmt.Errorf("create demo account: %w", err)
	}

	settings := domain.DefaultSettings(user.ID)
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

	_, active, err := database.ActiveTimer(user.ID)
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
