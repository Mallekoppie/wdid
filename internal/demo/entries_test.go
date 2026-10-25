package demo_test

import (
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/demo"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// entrySundayAnchor covers an anchor whose final day is a weekend day, so the
// day-role rules cannot assume the anchor is a weekday.
var entrySundayAnchor = time.Date(2026, time.March, 15, 0, 0, 0, 0, time.UTC)

func TestSeedDemoWritesTwoWeeksOfEntriesForAnyAnchorWeekday(t *testing.T) {
	for _, tc := range []struct {
		name   string
		anchor time.Time
	}{
		{name: "monday", anchor: testAnchor},
		{name: "sunday", anchor: entrySundayAnchor},
	} {
		t.Run(tc.name, func(t *testing.T) {
			database := openStore(t, filepath.Join(t.TempDir(), tc.name+".db"))
			t.Cleanup(func() { _ = database.Close() })

			summary, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: tc.anchor})
			if err != nil {
				t.Fatalf("seed demo scenario: %v", err)
			}
			if summary.Entries != 62 {
				t.Fatalf("summary entries = %d, want 62", summary.Entries)
			}

			user, err := database.UserByEmail(demo.DemoEmail)
			if err != nil {
				t.Fatalf("read demo account: %v", err)
			}
			entries, err := database.WorkEntries(user.ID, store.WorkEntryFilter{})
			if err != nil {
				t.Fatalf("list entries: %v", err)
			}
			if len(entries) != 62 {
				t.Fatalf("entries = %d, want 62", len(entries))
			}

			fromDate := tc.anchor.AddDate(0, 0, -13).Format(domain.DateLayout)
			toDate := tc.anchor.Format(domain.DateLayout)
			byDate := make(map[string]int)
			for _, entry := range entries {
				if entry.LocalDate < fromDate || entry.LocalDate > toDate {
					t.Fatalf("entry %q local date = %s, want within %s..%s",
						entry.ID, entry.LocalDate, fromDate, toDate)
				}
				byDate[entry.LocalDate]++
			}
			if len(byDate) == 0 {
				t.Fatal("no entry days recorded")
			}
			if _, ok := byDate[fromDate]; !ok {
				t.Fatalf("no entries on the first day of the window %s", fromDate)
			}
			if _, ok := byDate[toDate]; !ok {
				t.Fatalf("no entries on the last day of the window %s", toDate)
			}

			sparse := firstWeekdayOnOrAfter(tc.anchor.AddDate(0, 0, -13))
			onCall := latestSaturdayOnOrBefore(tc.anchor)

			for i := 0; i < 14; i++ {
				day := tc.anchor.AddDate(0, 0, i-13)
				count := byDate[day.Format(domain.DateLayout)]
				switch {
				case sameDate(day, sparse):
					if count != 2 {
						t.Fatalf("%s (sparse) entries = %d, want 2", day.Format(domain.DateLayout), count)
					}
				case sameDate(day, onCall) && sameDate(day, tc.anchor):
					if count != 6 {
						t.Fatalf("%s (on-call anchor) entries = %d, want 5 on-call plus the interrupt", day.Format(domain.DateLayout), count)
					}
				case sameDate(day, onCall):
					if count != 5 {
						t.Fatalf("%s (on-call) entries = %d, want 5", day.Format(domain.DateLayout), count)
					}
				case sameDate(day, tc.anchor) && (day.Weekday() == time.Saturday || day.Weekday() == time.Sunday):
					if count != 1 {
						t.Fatalf("%s (weekend anchor) entries = %d, want only the no-mode interrupt", day.Format(domain.DateLayout), count)
					}
				case day.Weekday() == time.Saturday || day.Weekday() == time.Sunday:
					if count != 0 {
						t.Fatalf("%s (weekend) entries = %d, want 0", day.Format(domain.DateLayout), count)
					}
				default:
					if count < 5 || count > 7 {
						t.Fatalf("%s (weekday) entries = %d, want 5-7", day.Format(domain.DateLayout), count)
					}
				}
			}
		})
	}
}

func firstWeekdayOnOrAfter(date time.Time) time.Time {
	for date.Weekday() == time.Saturday || date.Weekday() == time.Sunday {
		date = date.AddDate(0, 0, 1)
	}
	return date
}

func latestSaturdayOnOrBefore(date time.Time) time.Time {
	for date.Weekday() != time.Saturday {
		date = date.AddDate(0, 0, -1)
	}
	return date
}

func sameDate(a, b time.Time) bool {
	ay, am, ad := a.Date()
	by, bm, bd := b.Date()
	return ay == by && am == bm && ad == bd
}

func TestSeedDemoEntriesKeepTaxonomyAndRosterAttribution(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "attribution.db"))
	t.Cleanup(func() { _ = database.Close() })

	if _, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: testAnchor}); err != nil {
		t.Fatalf("seed demo scenario: %v", err)
	}
	user, entries := readDemoEntries(t, database)

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

	categoryByID := make(map[string]domain.Category, len(categories))
	roleMinutes := make(map[domain.CategoryRole]int)
	for _, category := range categories {
		categoryByID[category.ID] = category
	}
	subcategoryByID := make(map[string]domain.Subcategory, len(subcategories))
	for _, subcategory := range subcategories {
		subcategoryByID[subcategory.ID] = subcategory
	}
	roster := make(map[string]struct{}, len(settings.SupportPeople))
	for _, person := range settings.SupportPeople {
		roster[strings.ToLower(person)] = struct{}{}
	}

	timerEntries, manualEntries := 0, 0
	var noMode []domain.WorkEntry
	supportModes := make(map[string]struct{})
	for _, entry := range entries {
		category, ok := categoryByID[entry.CategoryID]
		if !ok {
			t.Fatalf("entry %q category %q does not exist", entry.ID, entry.CategoryID)
		}
		if strings.TrimSpace(entry.Description) == "" {
			t.Fatalf("entry %q has an empty description", entry.ID)
		}
		roleMinutes[category.Role] += entry.DurationMinutes()

		switch category.Role {
		case domain.CategoryRoleInitiative:
			if entry.SubcategoryID == "" {
				t.Fatalf("initiative entry %q has no project subcategory", entry.ID)
			}
			subcategory, ok := subcategoryByID[entry.SubcategoryID]
			if !ok || subcategory.CategoryID != category.ID {
				t.Fatalf("initiative entry %q subcategory %q does not belong to %q",
					entry.ID, entry.SubcategoryID, category.Name)
			}
		case domain.CategoryRoleSupport:
			if entry.Person == "" {
				t.Fatalf("support entry %q has no person", entry.ID)
			}
			if _, ok := roster[strings.ToLower(entry.Person)]; !ok {
				t.Fatalf("support entry %q person %q is not on the roster %v",
					entry.ID, entry.Person, settings.SupportPeople)
			}
			if entry.SubcategoryID == "" {
				noMode = append(noMode, entry)
				continue
			}
			subcategory, ok := subcategoryByID[entry.SubcategoryID]
			if !ok || subcategory.CategoryID != category.ID {
				t.Fatalf("support entry %q mode %q does not belong to %q",
					entry.ID, entry.SubcategoryID, category.Name)
			}
			supportModes[subcategory.Name] = struct{}{}
		case domain.CategoryRoleOther:
			if entry.SubcategoryID == "" {
				t.Fatalf("other entry %q has no subcategory", entry.ID)
			}
			subcategory, ok := subcategoryByID[entry.SubcategoryID]
			if !ok || subcategory.CategoryID != category.ID {
				t.Fatalf("other entry %q subcategory %q does not belong to %q",
					entry.ID, entry.SubcategoryID, category.Name)
			}
		default:
			t.Fatalf("entry %q has an unknown category role %q", entry.ID, category.Role)
		}

		switch entry.Source {
		case domain.EntrySourceTimer:
			timerEntries++
		case domain.EntrySourceManual:
			manualEntries++
		default:
			t.Fatalf("entry %q has an invalid source %q", entry.ID, entry.Source)
		}
	}

	if roleMinutes[domain.CategoryRoleInitiative] == 0 ||
		roleMinutes[domain.CategoryRoleSupport] == 0 ||
		roleMinutes[domain.CategoryRoleOther] == 0 {
		t.Fatalf("role minutes = %v, want initiative, support and other time", roleMinutes)
	}
	if timerEntries == 0 || manualEntries == 0 {
		t.Fatalf("timer/manual entries = %d/%d, want both sources", timerEntries, manualEntries)
	}

	if len(noMode) != 1 {
		t.Fatalf("entries without a mode = %d, want exactly one", len(noMode))
	}
	anchorDate := testAnchor.Format(domain.DateLayout)
	if noMode[0].LocalDate != anchorDate {
		t.Fatalf("no-mode entry local date = %s, want the anchor %s", noMode[0].LocalDate, anchorDate)
	}
	if noMode[0].Person == "" || noMode[0].Description == "" {
		t.Fatalf("no-mode entry = %+v, want a person and description", noMode[0])
	}

	wantModes := []string{"Mentoring", "Pairing", "Incident support", "Code review", "1:1"}
	modeNames := make([]string, 0, len(supportModes))
	for mode := range supportModes {
		modeNames = append(modeNames, mode)
	}
	sort.Strings(modeNames)
	sort.Strings(wantModes)
	if !reflect.DeepEqual(modeNames, wantModes) {
		t.Fatalf("support modes = %v, want %v", modeNames, wantModes)
	}

	assertNonOverlappingDays(t, entries)

	if _, active, err := database.ActiveTimer(user.ID); err != nil {
		t.Fatalf("read active timer: %v", err)
	} else if active {
		t.Fatal("active timer = running, want none")
	}
}

func TestSeedDemoEntriesFeedThePeriodReportAndAnchorDay(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "report.db"))
	t.Cleanup(func() { _ = database.Close() })

	if _, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: testAnchor}); err != nil {
		t.Fatalf("seed demo scenario: %v", err)
	}
	user, entries := readDemoEntries(t, database)

	categories, err := database.Categories(user.ID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	categoryRoles := make(map[string]domain.CategoryRole, len(categories))
	for _, category := range categories {
		categoryRoles[category.ID] = category.Role
	}

	fromDate := testAnchor.AddDate(0, 0, -13).Format(domain.DateLayout)
	toDate := testAnchor.Format(domain.DateLayout)

	totalMinutes := 0
	wantRoleMinutes := make(map[domain.CategoryRole]int)
	supportEntries := 0
	for _, entry := range entries {
		totalMinutes += entry.DurationMinutes()
		wantRoleMinutes[categoryRoles[entry.CategoryID]] += entry.DurationMinutes()
		if categoryRoles[entry.CategoryID] == domain.CategoryRoleSupport {
			supportEntries++
		}
	}

	report, err := database.PeriodReport(user.ID, fromDate, toDate)
	if err != nil {
		t.Fatalf("period report: %v", err)
	}
	if report.EntryCount != len(entries) {
		t.Fatalf("report entries = %d, want %d", report.EntryCount, len(entries))
	}
	if report.TotalMinutes != totalMinutes {
		t.Fatalf("report minutes = %d, want %d", report.TotalMinutes, totalMinutes)
	}

	reportRoleMinutes := make(map[domain.CategoryRole]int)
	for _, total := range report.Categories {
		reportRoleMinutes[categoryRoles[total.CategoryID]] += total.Minutes
	}
	if !reflect.DeepEqual(reportRoleMinutes, wantRoleMinutes) {
		t.Fatalf("report role minutes = %v, want %v", reportRoleMinutes, wantRoleMinutes)
	}

	settings, err := database.Settings(user.ID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	roster := make(map[string]struct{}, len(settings.SupportPeople))
	for _, person := range settings.SupportPeople {
		roster[strings.ToLower(person)] = struct{}{}
	}
	interactions := 0
	for _, person := range report.SupportPeople {
		if _, ok := roster[strings.ToLower(person.Person)]; !ok {
			t.Fatalf("report support person %q is not on the roster", person.Person)
		}
		interactions += person.Interactions
	}
	if interactions != supportEntries {
		t.Fatalf("report support interactions = %d, want %d", interactions, supportEntries)
	}

	inRange, err := database.WorkEntriesInDateRange(user.ID, fromDate, toDate)
	if err != nil {
		t.Fatalf("list entries in range: %v", err)
	}
	if len(inRange) != len(entries) {
		t.Fatalf("entries in range = %d, want %d", len(inRange), len(entries))
	}

	anchorRows, err := database.WorkEntries(user.ID, store.WorkEntryFilter{LocalDate: toDate})
	if err != nil {
		t.Fatalf("list anchor day entries: %v", err)
	}
	wantAnchorRows := 0
	for _, entry := range entries {
		if entry.LocalDate == toDate {
			wantAnchorRows++
		}
	}
	if wantAnchorRows == 0 || len(anchorRows) != wantAnchorRows {
		t.Fatalf("anchor day entries = %d, want %d", len(anchorRows), wantAnchorRows)
	}
	for _, entry := range anchorRows {
		if entry.LocalDate != toDate {
			t.Fatalf("anchor filter returned entry on %s, want %s", entry.LocalDate, toDate)
		}
	}
}

func TestSeedDemoEntriesFixtureDirectoryOverride(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "entries.json", `{
		"entries": [
			{
				"key": "override-standup",
				"days": ["anchor"],
				"start": "10:00",
				"minutes": 30,
				"category": "Client Delivery",
				"subcategory": "Acme migration",
				"description": "Override standup",
				"source": "manual"
			},
			{
				"key": "override-interrupt",
				"days": ["anchor"],
				"start": "11:00",
				"minutes": 15,
				"category": "Support",
				"person": "Priya",
				"description": "Override interrupt",
				"source": "manual"
			}
		]
	}`)

	database := openStore(t, filepath.Join(t.TempDir(), "override.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{
		Scenario: "demo",
		Anchor:   testAnchor,
		Fixture:  dir,
	})
	if err != nil {
		t.Fatalf("seed with entries override: %v", err)
	}
	if summary.Entries != 2 {
		t.Fatalf("summary entries = %d, want the 2 override rows", summary.Entries)
	}

	_, entries := readDemoEntries(t, database)
	if len(entries) != 2 {
		t.Fatalf("entries = %d, want the 2 override rows", len(entries))
	}
	anchorDate := testAnchor.Format(domain.DateLayout)
	descriptions := map[string]string{}
	for _, entry := range entries {
		if entry.LocalDate != anchorDate {
			t.Fatalf("override entry local date = %s, want %s", entry.LocalDate, anchorDate)
		}
		descriptions[entry.Description] = entry.Person
	}
	if _, ok := descriptions["Override standup"]; !ok {
		t.Fatalf("descriptions = %v, want the override standup row", descriptions)
	}
	if person, ok := descriptions["Override interrupt"]; !ok || person != "Priya" {
		t.Fatalf("descriptions = %v, want the override interrupt row for Priya", descriptions)
	}
}

func TestSeedDemoEntriesAreDeterministicForTheSameAnchor(t *testing.T) {
	first := seedEntrySnapshot(t, filepath.Join(t.TempDir(), "first.db"))
	second := seedEntrySnapshot(t, filepath.Join(t.TempDir(), "second.db"))

	if !reflect.DeepEqual(first, second) {
		t.Fatalf("same anchor produced different entries:\nfirst:  %+v\nsecond: %+v", first, second)
	}
	if len(first) != 62 {
		t.Fatalf("entries = %d, want 62", len(first))
	}
}

func seedEntrySnapshot(t *testing.T, path string) []domain.WorkEntry {
	t.Helper()

	database := openStore(t, path)
	defer func() {
		if err := database.Close(); err != nil {
			t.Fatalf("close store: %v", err)
		}
	}()

	if _, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: testAnchor}); err != nil {
		t.Fatalf("seed demo scenario: %v", err)
	}
	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	entries, err := database.WorkEntries(user.ID, store.WorkEntryFilter{})
	if err != nil {
		t.Fatalf("list entries: %v", err)
	}
	return entries
}

func readDemoEntries(t *testing.T, database *store.Store) (domain.User, []domain.WorkEntry) {
	t.Helper()

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	entries, err := database.WorkEntries(user.ID, store.WorkEntryFilter{})
	if err != nil {
		t.Fatalf("list entries: %v", err)
	}
	return user, entries
}

func assertNonOverlappingDays(t *testing.T, entries []domain.WorkEntry) {
	t.Helper()

	byDay := make(map[string][]domain.WorkEntry)
	for _, entry := range entries {
		byDay[entry.LocalDate] = append(byDay[entry.LocalDate], entry)
	}
	for day, dayEntries := range byDay {
		sort.Slice(dayEntries, func(i, j int) bool {
			return dayEntries[i].StartedAt.Before(dayEntries[j].StartedAt)
		})
		for i := 1; i < len(dayEntries); i++ {
			if dayEntries[i].StartedAt.Before(dayEntries[i-1].EndedAt) {
				t.Fatalf("%s has overlapping entries %q and %q",
					day, dayEntries[i-1].ID, dayEntries[i].ID)
			}
		}
	}
}
