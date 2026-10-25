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

// anchorDaysAgo returns the canonical date offset days before the test anchor.
func anchorDaysAgo(offset int) string {
	return testAnchor.AddDate(0, 0, -offset).Format(domain.DateLayout)
}

func TestSeedDemoSeedsNotes(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "notes.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: testAnchor})
	if err != nil {
		t.Fatalf("seed demo scenario: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	notes, err := database.Notes(user.ID, store.NoteFilter{})
	if err != nil {
		t.Fatalf("list notes: %v", err)
	}

	// Eight day notes plus three project notes, and the summary must agree.
	if summary.Notes != 11 || len(notes) != 11 {
		t.Fatalf("notes = %d, summary notes = %d, want 11", len(notes), summary.Notes)
	}

	wantDayNotes := map[string]string{
		anchorDaysAgo(0):  "Cutover dry run complete. Tomorrow: tighten the rollback window and confirm the Globex contact list.",
		anchorDaysAgo(1):  "Review day. Triaged the search relevance benchmark failures and parked the pricing copy until next week.",
		anchorDaysAgo(3):  "Pairing with Priya on the auth session rotation. The refresh-token edge case is real; wrote it up as a milestone.",
		anchorDaysAgo(5):  "Blocked most of the morning on staging credentials, then finished the observability dashboard skeleton.",
		anchorDaysAgo(6):  "Client check-in with Globex. They want the onboarding runbook before the next cohort.",
		anchorDaysAgo(9):  "Deep work on the pricing experiment. Three variants defined; waiting on finance for the margin floor.",
		anchorDaysAgo(11): "Incident support in the afternoon. No customer impact, but the alert threshold needs tuning.",
		anchorDaysAgo(13): "Planning the next two weeks. Cut scope on the audit deliverable and protected Friday for review.",
	}

	gotDayNotes := map[string]string{}
	var projectNotes []domain.Note
	createdAt := map[string]struct{}{}
	for _, note := range notes {
		if _, ok := createdAt[note.CreatedAt.Format(time.RFC3339Nano)]; ok {
			t.Fatalf("note %s reuses createdAt %s; ordering would be unstable", note.ID, note.CreatedAt)
		}
		createdAt[note.CreatedAt.Format(time.RFC3339Nano)] = struct{}{}

		if note.SubcategoryID == "" {
			if note.Date == "" {
				t.Fatalf("day note %s has no date", note.ID)
			}
			gotDayNotes[note.Date] = note.Text
			continue
		}
		if note.Date != "" {
			t.Fatalf("project note %s also carries date %q", note.ID, note.Date)
		}
		projectNotes = append(projectNotes, note)
	}

	if !reflect.DeepEqual(gotDayNotes, wantDayNotes) {
		t.Fatalf("day notes = %#v, want %#v", gotDayNotes, wantDayNotes)
	}
	if len(projectNotes) != 3 {
		t.Fatalf("project notes = %d, want 3", len(projectNotes))
	}

	projects := initiativeProjectNames(t, database, user.ID)
	byProject := map[string]domain.Note{}
	for _, note := range projectNotes {
		name, ok := projects[note.SubcategoryID]
		if !ok {
			t.Fatalf("project note %s is attached to %s, not an initiative project", note.ID, note.SubcategoryID)
		}
		if _, duplicate := byProject[name]; duplicate {
			t.Fatalf("project %s has more than one fixture note", name)
		}
		byProject[name] = note
	}

	gotProjects := make([]string, 0, len(byProject))
	for name := range byProject {
		gotProjects = append(gotProjects, name)
	}
	sort.Strings(gotProjects)
	wantProjects := []string{"Acme migration", "Search relevance", "Self-serve trial"}
	if !reflect.DeepEqual(gotProjects, wantProjects) {
		t.Fatalf("project notes attach to %v, want %v", gotProjects, wantProjects)
	}

	if got, want := byProject["Acme migration"].Text,
		"The dry run surfaced two ordering gaps in the migration scripts. Both are fixed; the remaining risk is the rollback window, which needs a signed runbook before the cutover."; got != want {
		t.Fatalf("Acme migration note = %q, want %q", got, want)
	}
	if got, want := byProject["Self-serve trial"].Text,
		"The trial cohort reached first value faster than the last one, mostly because the empty state now points at a sample project. Next question is whether the pricing page should appear before or after the first saved entry."; got != want {
		t.Fatalf("Self-serve trial note = %q, want %q", got, want)
	}

	long := byProject["Search relevance"].Text
	if !strings.HasPrefix(long, "The benchmark review turned into a longer investigation than expected") {
		t.Fatalf("long note starts with %q, want the benchmark review opening", firstRunes(long, 80))
	}
	if !strings.HasSuffix(long, "reconstruct it afterward.") {
		t.Fatalf("long note ends with %q, want the documented closing sentence", lastRunes(long, 80))
	}
	if len(long) < 2000 || len(long) > 3000 {
		t.Fatalf("long note length = %d, want roughly 2000-3000 characters", len(long))
	}
	for _, note := range notes {
		if len(note.Text) > 4000 {
			t.Fatalf("note %s length = %d, exceeds the 4000-character limit", note.ID, len(note.Text))
		}
	}
}

func TestSeedDemoSeedsMilestones(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "milestones.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: testAnchor})
	if err != nil {
		t.Fatalf("seed demo scenario: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	milestones, err := database.Milestones(user.ID, "")
	if err != nil {
		t.Fatalf("list milestones: %v", err)
	}

	if summary.Milestones != 20 || len(milestones) != 20 {
		t.Fatalf("milestones = %d, summary milestones = %d, want 20", len(milestones), summary.Milestones)
	}

	projects := initiativeProjectNames(t, database, user.ID)
	perProject := map[string]int{}
	seenIDs := map[string]struct{}{}
	var done, overdue, upcoming int
	for _, milestone := range milestones {
		name, ok := projects[milestone.SubcategoryID]
		if !ok {
			t.Fatalf("milestone %s is attached to %s, not an initiative project", milestone.ID, milestone.SubcategoryID)
		}
		if _, duplicate := seenIDs[milestone.ID]; duplicate {
			t.Fatalf("milestone ID %s is not unique", milestone.ID)
		}
		seenIDs[milestone.ID] = struct{}{}
		perProject[name]++

		if milestone.DueDate == "" {
			t.Fatalf("milestone %q has no due date", milestone.Title)
		}
		due, err := time.Parse(domain.DateLayout, milestone.DueDate)
		if err != nil || due.Format(domain.DateLayout) != milestone.DueDate {
			t.Fatalf("milestone %q due date = %q, want canonical YYYY-MM-DD", milestone.Title, milestone.DueDate)
		}

		// Status follows the domain rule: Done wins; otherwise the due date
		// against the anchor decides overdue versus upcoming.
		switch {
		case milestone.Done:
			if !due.Before(testAnchor) {
				t.Fatalf("done milestone %q is due %s, want a past date", milestone.Title, milestone.DueDate)
			}
			done++
		case due.Before(testAnchor):
			overdue++
		default:
			upcoming++
		}
	}

	wantPerProject := map[string]int{
		"Acme migration":     3,
		"Globex onboarding":  2,
		"Initech audit":      2,
		"Auth overhaul":      3,
		"Search relevance":   2,
		"Observability":      2,
		"Self-serve trial":   3,
		"Pricing experiment": 3,
	}
	if !reflect.DeepEqual(perProject, wantPerProject) {
		t.Fatalf("milestones per project = %v, want %v", perProject, wantPerProject)
	}
	if done != 9 || overdue != 4 || upcoming != 7 {
		t.Fatalf("milestone states = %d done / %d overdue / %d upcoming, want 9 / 4 / 7", done, overdue, upcoming)
	}
}

func TestSeedDemoNotesAndMilestonesAreDeterministic(t *testing.T) {
	first := journalSnapshotFor(t, filepath.Join(t.TempDir(), "first.db"), "demo")
	second := journalSnapshotFor(t, filepath.Join(t.TempDir(), "second.db"), "demo")

	if !reflect.DeepEqual(first, second) {
		t.Fatalf("same anchor produced different journal data:\nfirst:  %+v\nsecond: %+v", first, second)
	}
	if len(first.Notes) != 11 || len(first.Milestones) != 20 {
		t.Fatalf("snapshot = %d notes / %d milestones, want 11 / 20", len(first.Notes), len(first.Milestones))
	}
}

func TestSeedDemoNotesFixtureOverride(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "notes.json", `{
		"dayNotes": [
			{"daysBeforeAnchor": 0, "text": "Override day note."}
		],
		"projectNotes": []
	}`)

	database := openStore(t, filepath.Join(t.TempDir(), "notes-override.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{
		Scenario: "demo",
		Anchor:   testAnchor,
		Fixture:  dir,
	})
	if err != nil {
		t.Fatalf("seed with notes override: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	notes, err := database.Notes(user.ID, store.NoteFilter{})
	if err != nil {
		t.Fatalf("list notes: %v", err)
	}
	if summary.Notes != 1 || len(notes) != 1 {
		t.Fatalf("notes = %d, summary notes = %d, want the single override note", len(notes), summary.Notes)
	}
	if notes[0].Date != anchorDaysAgo(0) || notes[0].Text != "Override day note." {
		t.Fatalf("override note = %+v, want the anchor-day override", notes[0])
	}

	// milestones.json is absent from the override directory, so it falls back
	// to the embedded domain.
	milestones, err := database.Milestones(user.ID, "")
	if err != nil {
		t.Fatalf("list milestones: %v", err)
	}
	if summary.Milestones != 20 || len(milestones) != 20 {
		t.Fatalf("milestones = %d, summary milestones = %d, want the embedded 20", len(milestones), summary.Milestones)
	}
}

func TestSeedEmptyHasNoNotesOrMilestones(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "empty-journal.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{Scenario: "empty", Anchor: testAnchor})
	if err != nil {
		t.Fatalf("seed empty scenario: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	notes, err := database.Notes(user.ID, store.NoteFilter{})
	if err != nil {
		t.Fatalf("list notes: %v", err)
	}
	milestones, err := database.Milestones(user.ID, "")
	if err != nil {
		t.Fatalf("list milestones: %v", err)
	}
	if summary.Notes != 0 || len(notes) != 0 {
		t.Fatalf("empty notes = %d, summary notes = %d, want 0", len(notes), summary.Notes)
	}
	if summary.Milestones != 0 || len(milestones) != 0 {
		t.Fatalf("empty milestones = %d, summary milestones = %d, want 0", len(milestones), summary.Milestones)
	}
}

type journalSnapshot struct {
	Notes      []noteSnapshot
	Milestones []milestoneSnapshot
}

type noteSnapshot struct {
	ID            string
	UserID        string
	Date          string
	SubcategoryID string
	Text          string
	CreatedAt     string
}

type milestoneSnapshot struct {
	ID            string
	UserID        string
	SubcategoryID string
	Title         string
	DueDate       string
	Done          bool
	CreatedAt     string
	UpdatedAt     string
}

func journalSnapshotFor(t *testing.T, path, scenario string) journalSnapshot {
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
	notes, err := database.Notes(user.ID, store.NoteFilter{})
	if err != nil {
		t.Fatalf("list notes: %v", err)
	}
	milestones, err := database.Milestones(user.ID, "")
	if err != nil {
		t.Fatalf("list milestones: %v", err)
	}

	snapshot := journalSnapshot{}
	for _, note := range notes {
		snapshot.Notes = append(snapshot.Notes, noteSnapshot{
			ID:            note.ID,
			UserID:        note.UserID,
			Date:          note.Date,
			SubcategoryID: note.SubcategoryID,
			Text:          note.Text,
			CreatedAt:     note.CreatedAt.Format(time.RFC3339Nano),
		})
	}
	for _, milestone := range milestones {
		snapshot.Milestones = append(snapshot.Milestones, milestoneSnapshot{
			ID:            milestone.ID,
			UserID:        milestone.UserID,
			SubcategoryID: milestone.SubcategoryID,
			Title:         milestone.Title,
			DueDate:       milestone.DueDate,
			Done:          milestone.Done,
			CreatedAt:     milestone.CreatedAt.Format(time.RFC3339Nano),
			UpdatedAt:     milestone.UpdatedAt.Format(time.RFC3339Nano),
		})
	}
	return snapshot
}

func firstRunes(value string, count int) string {
	if len(value) <= count {
		return value
	}
	return value[:count]
}

func lastRunes(value string, count int) string {
	if len(value) <= count {
		return value
	}
	return value[len(value)-count:]
}

// initiativeProjectNames maps every initiative-role subcategory ID to its
// project name, so tests can assert attachments without calling unexported
// seeding helpers.
func initiativeProjectNames(t *testing.T, database *store.Store, userID string) map[string]string {
	t.Helper()

	categories, err := database.Categories(userID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	roles := make(map[string]domain.CategoryRole, len(categories))
	for _, category := range categories {
		roles[category.ID] = category.Role
	}

	subcategories, err := database.Subcategories(userID, "")
	if err != nil {
		t.Fatalf("list subcategories: %v", err)
	}
	names := make(map[string]string)
	for _, subcategory := range subcategories {
		if roles[subcategory.CategoryID] == domain.CategoryRoleInitiative {
			names[subcategory.ID] = subcategory.Name
		}
	}
	return names
}
