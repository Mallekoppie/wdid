package demo

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// Day selectors describe a fixture entry's place in the window relative to the
// anchor, never a literal date. The window is the 14 calendar days ending at
// the anchor.
const (
	// entryDayNormalWeekday is every weekday in the window except the sparse day.
	entryDayNormalWeekday = "normal-weekday"
	// entryDaySparse is the first weekday in the window; it carries 1-2 entries.
	entryDaySparse = "sparse"
	// entryDayOnCall is the Saturday closest to the anchor. In a 14-day window
	// there are always two Saturdays, so "the on-call Saturday" is the latest one
	// on or before the anchor.
	entryDayOnCall = "on-call"
	// entryDayAnchor is the anchor day itself.
	entryDayAnchor = "anchor"
)

// EntryFixture is one work-entry template. A template is expanded once for every
// window day that matches one of its day selectors. Key is the stable identity
// of the template; the per-day instance adds the window-relative day index, so
// the same fixture and anchor always produce the same IDs.
type EntryFixture struct {
	Key         string             `json:"key"`
	Days        []string           `json:"days"`
	Start       string             `json:"start"`
	Minutes     int                `json:"minutes"`
	Category    string             `json:"category"`
	Subcategory string             `json:"subcategory,omitempty"`
	People      []string           `json:"people,omitempty"`
	Description string             `json:"description"`
	Outcome     string             `json:"outcome,omitempty"`
	Source      domain.EntrySource `json:"source"`
}

// EntriesFixture is the declarative work-entry dataset. An entry without a
// subcategory is the "interrupt / needs a mode" support row and must fall on
// the anchor day.
type EntriesFixture struct {
	Entries []EntryFixture `json:"entries"`
}

// validateEntries checks that every template can be expanded into a valid row
// against the fixture taxonomy. The dataset contract also requires exactly one
// mode-less support entry, on the anchor day, because Today uses it to show the
// "Set mode" affordance.
func (f Fixture) validateEntries() error {
	if len(f.Entries.Entries) == 0 {
		return fmt.Errorf("fixture entries: at least one entry is required")
	}

	keys := make(map[string]struct{}, len(f.Entries.Entries))
	noMode := 0
	for i, entry := range f.Entries.Entries {
		key := strings.TrimSpace(entry.Key)
		if key == "" {
			return fmt.Errorf("fixture entry %d: key is required", i)
		}
		if _, ok := keys[key]; ok {
			return fmt.Errorf("fixture entry %q is duplicated", key)
		}
		keys[key] = struct{}{}

		if len(entry.Days) == 0 {
			return fmt.Errorf("fixture entry %q: at least one day selector is required", key)
		}
		days := make(map[string]struct{}, len(entry.Days))
		for _, raw := range entry.Days {
			day := strings.TrimSpace(raw)
			switch day {
			case entryDayNormalWeekday, entryDaySparse, entryDayOnCall, entryDayAnchor:
				days[day] = struct{}{}
			default:
				return fmt.Errorf("fixture entry %q: unknown day selector %q", key, raw)
			}
		}

		start, err := entryClockMinutes(entry.Start)
		if err != nil {
			return fmt.Errorf("fixture entry %q: %w", key, err)
		}
		if entry.Minutes < 1 || entry.Minutes > 24*60 {
			return fmt.Errorf("fixture entry %q: minutes must be between 1 and 1440", key)
		}
		if start+entry.Minutes > 24*60 {
			return fmt.Errorf("fixture entry %q: must end before midnight", key)
		}

		category, ok := fixtureCategory(f, entry.Category)
		if !ok {
			return fmt.Errorf("fixture entry %q: category %q does not exist", key, entry.Category)
		}
		subcategory := strings.TrimSpace(entry.Subcategory)
		if subcategory != "" {
			if _, ok := fixtureSubcategory(category, subcategory); !ok {
				return fmt.Errorf("fixture entry %q: subcategory %q does not belong to %q", key, subcategory, category.Name)
			}
		}

		if strings.TrimSpace(entry.Description) == "" {
			return fmt.Errorf("fixture entry %q: description is required", key)
		}
		if !entry.Source.Valid() {
			return fmt.Errorf("fixture entry %q: invalid source %q", key, entry.Source)
		}
		if category.Role == domain.CategoryRoleSupport {
			if len(domain.NormalizeList(entry.People)) == 0 {
				return fmt.Errorf("fixture entry %q: at least one person is required for support entries", key)
			}
		} else if subcategory == "" {
			return fmt.Errorf("fixture entry %q: a %s entry needs a subcategory", key, category.Role)
		}

		if subcategory == "" {
			noMode++
			if _, ok := days[entryDayAnchor]; !ok {
				return fmt.Errorf("fixture entry %q: the entry without a mode must use the %q day selector", key, entryDayAnchor)
			}
		}
	}
	if noMode != 1 {
		return fmt.Errorf("fixture entries: exactly one support entry without a mode is required, got %d", noMode)
	}
	return nil
}

// seedEntries expands the fixture templates over the 14-day window ending at
// the anchor and writes them through SaveWorkEntry, so LocalDate and the entry
// indexes are derived exactly as for a user-created entry. Times are wall-clock
// times in the resolved settings timezone.
func seedEntries(
	database *store.Store,
	scenario string,
	user domain.User,
	fixture Fixture,
	location *time.Location,
	anchor time.Time,
) (int, error) {
	if location == nil {
		location = time.UTC
	}

	windowStart := anchor.AddDate(0, 0, -13)
	sparse := firstWeekday(windowStart)
	onCall := latestSaturday(anchor)

	count := 0
	for dayIndex := 0; dayIndex < 14; dayIndex++ {
		day := windowStart.AddDate(0, 0, dayIndex)
		roles := entryDayRoles(day, sparse, onCall, anchor)

		for _, fixtureEntry := range fixture.Entries.Entries {
			if !entryMatchesDays(fixtureEntry.Days, roles) {
				continue
			}

			category, ok := fixtureCategory(fixture, fixtureEntry.Category)
			if !ok {
				return count, fmt.Errorf("fixture entry %q: category %q does not exist", fixtureEntry.Key, fixtureEntry.Category)
			}
			categoryID := stableCategoryID(scenario, category.Name)
			subcategoryID := ""
			if subcategory := strings.TrimSpace(fixtureEntry.Subcategory); subcategory != "" {
				subcategoryID = stableSubcategoryID(scenario, category.Name, subcategory)
			}

			start, err := entryClockMinutes(fixtureEntry.Start)
			if err != nil {
				return count, fmt.Errorf("fixture entry %q: %w", fixtureEntry.Key, err)
			}
			started := time.Date(day.Year(), day.Month(), day.Day(), start/60, start%60, 0, 0, location)
			ended := started.Add(time.Duration(fixtureEntry.Minutes) * time.Minute)

			entry := domain.WorkEntry{
				ID:            stableID(scenario, "entry", strings.TrimSpace(fixtureEntry.Key)+"/"+strconv.Itoa(dayIndex)),
				UserID:        user.ID,
				CategoryID:    categoryID,
				SubcategoryID: subcategoryID,
				Description:   strings.TrimSpace(fixtureEntry.Description),
				Outcome:       strings.TrimSpace(fixtureEntry.Outcome),
				StartedAt:     started,
				EndedAt:       ended,
				Minutes:       fixtureEntry.Minutes,
				People:        domain.NormalizeList(fixtureEntry.People),
				Source:        fixtureEntry.Source,
				CreatedAt:     ended.UTC(),
				UpdatedAt:     ended.UTC(),
			}
			if err := database.SaveWorkEntry(entry); err != nil {
				return count, fmt.Errorf("save demo entry %q on %s: %w",
					fixtureEntry.Key, day.Format(domain.DateLayout), err)
			}
			count++
		}
	}
	return count, nil
}

// entryDayRoles resolves which selectors a concrete window day matches. A
// weekday anchor matches both normal-weekday and anchor; a Saturday anchor
// matches both on-call and anchor, so the mode-less interrupt shares the day
// with the on-call work.
func entryDayRoles(day, sparse, onCall, anchor time.Time) map[string]struct{} {
	roles := make(map[string]struct{}, 4)
	if day.Weekday() != time.Saturday && day.Weekday() != time.Sunday && !sameDay(day, sparse) {
		roles[entryDayNormalWeekday] = struct{}{}
	}
	if sameDay(day, sparse) {
		roles[entryDaySparse] = struct{}{}
	}
	if sameDay(day, onCall) {
		roles[entryDayOnCall] = struct{}{}
	}
	if sameDay(day, anchor) {
		roles[entryDayAnchor] = struct{}{}
	}
	return roles
}

func entryMatchesDays(selectors []string, roles map[string]struct{}) bool {
	for _, raw := range selectors {
		if _, ok := roles[strings.TrimSpace(raw)]; ok {
			return true
		}
	}
	return false
}

// firstWeekday returns date when it is a weekday, otherwise the next Monday.
func firstWeekday(date time.Time) time.Time {
	for date.Weekday() == time.Saturday || date.Weekday() == time.Sunday {
		date = date.AddDate(0, 0, 1)
	}
	return date
}

// latestSaturday returns the most recent Saturday on or before date.
func latestSaturday(date time.Time) time.Time {
	for date.Weekday() != time.Saturday {
		date = date.AddDate(0, 0, -1)
	}
	return date
}

func sameDay(a, b time.Time) bool {
	ay, am, ad := a.Date()
	by, bm, bd := b.Date()
	return ay == by && am == bm && ad == bd
}

// entryClockMinutes parses a fixture wall-clock time in HH:MM form.
func entryClockMinutes(value string) (int, error) {
	parsed, err := time.Parse("15:04", strings.TrimSpace(value))
	if err != nil {
		return 0, fmt.Errorf("start must be HH:MM, got %q", value)
	}
	return parsed.Hour()*60 + parsed.Minute(), nil
}

// fixtureCategory finds a category by its trimmed fixture name.
func fixtureCategory(fixture Fixture, name string) (CategoryFixture, bool) {
	name = strings.TrimSpace(name)
	for _, category := range fixture.Taxonomy.Categories {
		if strings.TrimSpace(category.Name) == name {
			return category, true
		}
	}
	return CategoryFixture{}, false
}

// fixtureSubcategory finds a subcategory by name beneath one category.
func fixtureSubcategory(category CategoryFixture, name string) (SubcategoryFixture, bool) {
	name = strings.TrimSpace(name)
	for _, subcategory := range category.Subcategories {
		if strings.TrimSpace(subcategory.Name) == name {
			return subcategory, true
		}
	}
	return SubcategoryFixture{}, false
}
