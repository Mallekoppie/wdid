package demo_test

import (
	"errors"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/demo"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

const (
	managerFocusNotes = "Cutover readiness, Globex onboarding and the auth refresh-token fix. Keep support time visible next period."
	managerSummary    = "## Previous period\n\nShipped the auth session-rotation foundation and closed two migration ordering gaps. The Acme cutover is the main risk: the rollback window still needs a signed runbook.\n\n- Acme migration: dry run complete, blockers assigned\n- Globex onboarding: import rehearsal clean\n- Support: on-call coverage only, no escalations"

	personalFocusNotes = "What moved the projects forward this week, and where did support work interrupt deep work?"
	personalSummary    = "## Draft review\n\nSteady progress on the self-serve trial and search relevance. Support stayed bounded to the on-call day. Next: protect a longer block for the cutover runbook."
)

// seedDemoWithCheckIns seeds the demo scenario and returns the store, the demo
// user and the seeded check-ins in list order.
func seedDemoWithCheckIns(t *testing.T, path string) (*store.Store, domain.User, []domain.CheckIn, demo.Summary) {
	t.Helper()

	database := openStore(t, filepath.Join(t.TempDir(), path))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{Scenario: "demo", Anchor: testAnchor})
	if err != nil {
		t.Fatalf("seed demo scenario: %v", err)
	}

	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	checkIns, err := database.CheckIns(user.ID, "")
	if err != nil {
		t.Fatalf("list check-ins: %v", err)
	}
	return database, user, checkIns, summary
}

func checkInByKind(t *testing.T, checkIns []domain.CheckIn, kind domain.CheckInKind) domain.CheckIn {
	t.Helper()

	var matches []domain.CheckIn
	for _, checkIn := range checkIns {
		if checkIn.Kind == kind {
			matches = append(matches, checkIn)
		}
	}
	if len(matches) != 1 {
		t.Fatalf("%s check-ins = %d, want exactly one", kind, len(matches))
	}
	return matches[0]
}

func TestSeedDemoSeedsOneFinalManagerCheckInAndOnePersonalReview(t *testing.T) {
	database, user, checkIns, summary := seedDemoWithCheckIns(t, "check-ins.db")

	if summary.CheckIns != 2 || len(checkIns) != 2 {
		t.Fatalf("check-ins = %d, summary check-ins = %d, want 2", len(checkIns), summary.CheckIns)
	}

	manager := checkInByKind(t, checkIns, domain.CheckInKindManager)
	if manager.State != domain.CheckInStateFinal {
		t.Fatalf("manager state = %q, want final", manager.State)
	}
	if manager.Audience != domain.AudienceOneOnOne {
		t.Fatalf("manager audience = %q, want one_on_one", manager.Audience)
	}
	if manager.PeriodStart != anchorDaysAgo(13) || manager.PeriodEnd != anchorDaysAgo(7) {
		t.Fatalf("manager period = %s..%s, want %s..%s",
			manager.PeriodStart, manager.PeriodEnd, anchorDaysAgo(13), anchorDaysAgo(7))
	}
	if manager.FocusNotes != managerFocusNotes {
		t.Fatalf("manager focus notes = %q, want the documented text", manager.FocusNotes)
	}
	if manager.SummaryMarkdown != managerSummary {
		t.Fatalf("manager summary = %q, want the documented text", manager.SummaryMarkdown)
	}

	personal := checkInByKind(t, checkIns, domain.CheckInKindPersonal)
	if personal.State != domain.CheckInStateDraft {
		t.Fatalf("personal state = %q, want draft", personal.State)
	}
	if personal.Audience != "" {
		t.Fatalf("personal audience = %q, want none", personal.Audience)
	}
	if personal.PeriodStart != anchorDaysAgo(6) || personal.PeriodEnd != anchorDaysAgo(0) {
		t.Fatalf("personal period = %s..%s, want %s..%s",
			personal.PeriodStart, personal.PeriodEnd, anchorDaysAgo(6), anchorDaysAgo(0))
	}
	if personal.FocusNotes != personalFocusNotes {
		t.Fatalf("personal focus notes = %q, want the documented text", personal.FocusNotes)
	}
	if personal.SummaryMarkdown != personalSummary {
		t.Fatalf("personal summary = %q, want the documented text", personal.SummaryMarkdown)
	}

	// The list is newest first, so the current-period personal review leads.
	if checkIns[0].ID != personal.ID || checkIns[1].ID != manager.ID {
		t.Fatalf("check-in order = %s, %s, want personal then manager", checkIns[0].Kind, checkIns[1].Kind)
	}
	if manager.ID == personal.ID {
		t.Fatal("manager and personal check-ins share an ID")
	}
	if !personal.CreatedAt.After(manager.CreatedAt) {
		t.Fatalf("created at = %s and %s, want the personal review newest",
			manager.CreatedAt, personal.CreatedAt)
	}

	// Re-reading the list must produce the same ordering; the timestamps are
	// distinct, not tied.
	again, err := database.CheckIns(user.ID, "")
	if err != nil {
		t.Fatalf("list check-ins again: %v", err)
	}
	if !reflect.DeepEqual(checkInIDs(again), checkInIDs(checkIns)) {
		t.Fatalf("check-in order changed between reads: %v then %v", checkInIDs(checkIns), checkInIDs(again))
	}
}

func checkInIDs(checkIns []domain.CheckIn) []string {
	ids := make([]string, 0, len(checkIns))
	for _, checkIn := range checkIns {
		ids = append(ids, checkIn.ID)
	}
	return ids
}

func TestSeedDemoCheckInTotalsSnapshotThePeriodReports(t *testing.T) {
	database, user, checkIns, _ := seedDemoWithCheckIns(t, "check-in-totals.db")

	categoryIDs := make(map[string]string)
	categories, err := database.Categories(user.ID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	for _, category := range categories {
		categoryIDs[category.Name] = category.ID
	}
	subcategoryIDs := make(map[string]string)
	subcategories, err := database.Subcategories(user.ID, "")
	if err != nil {
		t.Fatalf("list subcategories: %v", err)
	}
	for _, subcategory := range subcategories {
		subcategoryIDs[subcategory.Name] = subcategory.ID
	}

	manager := checkInByKind(t, checkIns, domain.CheckInKindManager)
	wantManager := domain.CheckInTotals{
		Minutes: 1545,
		ByCategory: map[string]int{
			categoryIDs["Client Delivery"]: 420,
			categoryIDs["Platform"]:        540,
			categoryIDs["Growth"]:          300,
			categoryIDs["Other"]:           285,
		},
		BySubcategory: map[string]int{
			subcategoryIDs["Acme migration"]:    180,
			subcategoryIDs["Auth overhaul"]:     360,
			subcategoryIDs["Globex onboarding"]: 240,
			subcategoryIDs["Meetings"]:          240,
			subcategoryIDs["Self-serve trial"]:  300,
			subcategoryIDs["Search relevance"]:  180,
			subcategoryIDs["Learning"]:          45,
		},
		// No support work in the previous period. The JSON omitempty tag
		// round-trips an empty map as nil.
		SupportByPerson: nil,
	}
	assertCheckInTotals(t, "manager", manager.Totals, wantManager)

	personal := checkInByKind(t, checkIns, domain.CheckInKindPersonal)
	wantPersonal := domain.CheckInTotals{
		Minutes: 2070,
		ByCategory: map[string]int{
			categoryIDs["Client Delivery"]: 450,
			categoryIDs["Platform"]:        675,
			categoryIDs["Growth"]:          375,
			categoryIDs["Other"]:           300,
			categoryIDs["Support"]:         270,
		},
		BySubcategory: map[string]int{
			subcategoryIDs["Acme migration"]:    150,
			subcategoryIDs["Auth overhaul"]:     450,
			subcategoryIDs["Globex onboarding"]: 300,
			subcategoryIDs["Meetings"]:          300,
			subcategoryIDs["Self-serve trial"]:  375,
			subcategoryIDs["Search relevance"]:  225,
			subcategoryIDs["Incident support"]:  90,
			subcategoryIDs["Pairing"]:           45,
			subcategoryIDs["Mentoring"]:         60,
			subcategoryIDs["Code review"]:       30,
			subcategoryIDs["1:1"]:               30,
		},
		SupportByPerson: map[string]int{
			// Alex also names the 45-minute pairing entry, so the per-person
			// rows add up to 315m while the authoritative total stays 270m.
			"Alex":   135,
			"Sam":    45,
			"Noor":   60,
			"Mei":    30,
			"Jordan": 30,
			"Priya":  15,
		},
		SupportMinutes:      270,
		SupportInteractions: 6,
	}
	assertCheckInTotals(t, "personal", personal.Totals, wantPersonal)

	// The stored snapshot must be exactly the authoritative period report for
	// the check-in's own inclusive period.
	for _, checkIn := range checkIns {
		report, err := database.PeriodReport(user.ID, checkIn.PeriodStart, checkIn.PeriodEnd)
		if err != nil {
			t.Fatalf("read %s period report: %v", checkIn.Kind, err)
		}
		if want := expectedTotalsFromReport(report); !reflect.DeepEqual(checkIn.Totals, want) {
			t.Fatalf("%s totals = %+v, want the period report snapshot %+v", checkIn.Kind, checkIn.Totals, want)
		}
	}
}

func assertCheckInTotals(t *testing.T, label string, got, want domain.CheckInTotals) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%s totals = %#v, want %#v", label, got, want)
	}
}

// expectedTotalsFromReport is an independent transcription of
// domain.CheckInTotalsFromReport: ID keys for categories and subcategories,
// display spelling for support people.
func expectedTotalsFromReport(report domain.PeriodReport) domain.CheckInTotals {
	totals := domain.CheckInTotals{
		Minutes:             report.TotalMinutes,
		SupportMinutes:      report.SupportMinutes,
		SupportInteractions: report.SupportInteractions,
	}
	// The totals maps are omitempty, so an empty report section is stored and
	// read back as nil rather than an allocated empty map.
	if len(report.Categories) > 0 {
		totals.ByCategory = make(map[string]int, len(report.Categories))
	}
	if len(report.Subcategories) > 0 {
		totals.BySubcategory = make(map[string]int, len(report.Subcategories))
	}
	if len(report.SupportPeople) > 0 {
		totals.SupportByPerson = make(map[string]int, len(report.SupportPeople))
	}
	for _, category := range report.Categories {
		totals.ByCategory[category.CategoryID] = category.Minutes
	}
	for _, subcategory := range report.Subcategories {
		totals.BySubcategory[subcategory.SubcategoryID] = subcategory.Minutes
	}
	for _, person := range report.SupportPeople {
		totals.SupportByPerson[person.Person] = person.Minutes
	}
	return totals
}

func TestSeedDemoLastFinalManagerCheckInIsTheSeededBoundary(t *testing.T) {
	database, user, checkIns, _ := seedDemoWithCheckIns(t, "check-in-boundary.db")

	manager := checkInByKind(t, checkIns, domain.CheckInKindManager)
	last, found, err := database.LastFinalManagerCheckIn(user.ID)
	if err != nil {
		t.Fatalf("read last final manager check-in: %v", err)
	}
	if !found {
		t.Fatal("no final manager check-in found")
	}
	if last.ID != manager.ID {
		t.Fatalf("boundary check-in = %s, want the seeded manager %s", last.ID, manager.ID)
	}
	if last.State != domain.CheckInStateFinal || last.Kind != domain.CheckInKindManager {
		t.Fatalf("boundary check-in = %s/%s, want manager/final", last.Kind, last.State)
	}
	if last.PeriodEnd != anchorDaysAgo(7) {
		t.Fatalf("boundary period end = %s, want %s", last.PeriodEnd, anchorDaysAgo(7))
	}
}

func TestSeedDemoPersonalReviewIsEditableAndFinalManagerIsReadOnly(t *testing.T) {
	database, user, checkIns, _ := seedDemoWithCheckIns(t, "check-in-editability.db")

	personal := checkInByKind(t, checkIns, domain.CheckInKindPersonal)
	updatedAt := personal.CreatedAt.Add(2 * time.Hour)
	personal.FocusNotes = "Revised focus: protect the cutover runbook block."
	personal.UpdatedAt = updatedAt
	if err := database.SaveCheckIn(personal); err != nil {
		t.Fatalf("edit personal review: %v", err)
	}

	stored, err := database.CheckIn(user.ID, personal.ID)
	if err != nil {
		t.Fatalf("read edited personal review: %v", err)
	}
	if stored.FocusNotes != "Revised focus: protect the cutover runbook block." {
		t.Fatalf("personal focus notes = %q, want the edit persisted", stored.FocusNotes)
	}
	if stored.State != domain.CheckInStateDraft {
		t.Fatalf("personal state = %q, want it to stay a draft", stored.State)
	}
	if !stored.UpdatedAt.Equal(updatedAt) {
		t.Fatalf("personal updated at = %s, want %s", stored.UpdatedAt, updatedAt)
	}

	manager := checkInByKind(t, checkIns, domain.CheckInKindManager)
	manager.FocusNotes = "Edited after the check-in became final."
	manager.UpdatedAt = manager.CreatedAt.Add(time.Hour)
	if err := database.SaveCheckIn(manager); !errors.Is(err, store.ErrFinalCheckInReadOnly) {
		t.Fatalf("edit final manager error = %v, want ErrFinalCheckInReadOnly", err)
	}
	if err := database.DeleteCheckIn(user.ID, manager.ID); !errors.Is(err, store.ErrFinalCheckInReadOnly) {
		t.Fatalf("delete final manager error = %v, want ErrFinalCheckInReadOnly", err)
	}

	storedManager, err := database.CheckIn(user.ID, manager.ID)
	if err != nil {
		t.Fatalf("read final manager: %v", err)
	}
	if storedManager.FocusNotes != managerFocusNotes {
		t.Fatalf("final manager focus notes = %q, want the original text", storedManager.FocusNotes)
	}
}

type checkInSnapshot struct {
	ID              string
	UserID          string
	Kind            domain.CheckInKind
	PeriodStart     string
	PeriodEnd       string
	State           domain.CheckInState
	Audience        domain.Audience
	FocusNotes      string
	SummaryMarkdown string
	Totals          domain.CheckInTotals
	CreatedAt       string
	UpdatedAt       string
}

func checkInSnapshotsFor(t *testing.T, path, scenario string) []checkInSnapshot {
	t.Helper()

	database := openStore(t, filepath.Join(t.TempDir(), path))
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
	checkIns, err := database.CheckIns(user.ID, "")
	if err != nil {
		t.Fatalf("list check-ins: %v", err)
	}

	snapshots := make([]checkInSnapshot, 0, len(checkIns))
	for _, checkIn := range checkIns {
		snapshots = append(snapshots, checkInSnapshot{
			ID:              checkIn.ID,
			UserID:          checkIn.UserID,
			Kind:            checkIn.Kind,
			PeriodStart:     checkIn.PeriodStart,
			PeriodEnd:       checkIn.PeriodEnd,
			State:           checkIn.State,
			Audience:        checkIn.Audience,
			FocusNotes:      checkIn.FocusNotes,
			SummaryMarkdown: checkIn.SummaryMarkdown,
			Totals:          checkIn.Totals,
			CreatedAt:       checkIn.CreatedAt.Format(time.RFC3339Nano),
			UpdatedAt:       checkIn.UpdatedAt.Format(time.RFC3339Nano),
		})
	}
	return snapshots
}

func TestSeedDemoCheckInsAreDeterministic(t *testing.T) {
	first := checkInSnapshotsFor(t, "check-ins-first.db", "demo")
	second := checkInSnapshotsFor(t, "check-ins-second.db", "demo")

	if !reflect.DeepEqual(first, second) {
		t.Fatalf("same anchor produced different check-ins:\nfirst:  %+v\nsecond: %+v", first, second)
	}
	if len(first) != 2 {
		t.Fatalf("check-ins = %d, want 2", len(first))
	}
}

func TestSeedEmptyHasNoCheckIns(t *testing.T) {
	database := openStore(t, filepath.Join(t.TempDir(), "empty-check-ins.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{Scenario: "empty", Anchor: testAnchor})
	if err != nil {
		t.Fatalf("seed empty scenario: %v", err)
	}
	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	checkIns, err := database.CheckIns(user.ID, "")
	if err != nil {
		t.Fatalf("list check-ins: %v", err)
	}
	if summary.CheckIns != 0 || len(checkIns) != 0 {
		t.Fatalf("empty check-ins = %d, summary = %d, want 0", len(checkIns), summary.CheckIns)
	}
	if _, found, err := database.LastFinalManagerCheckIn(user.ID); err != nil {
		t.Fatalf("read empty boundary: %v", err)
	} else if found {
		t.Fatal("empty scenario has a final manager check-in")
	}
}

func TestSeedDemoCheckInsFixtureOverride(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "check_ins.json", `{
		"checkIns": [
			{
				"key": "override-review",
				"kind": "personal",
				"state": "draft",
				"periodStartOffset": 6,
				"periodEndOffset": 0,
				"createdDaysBeforeAnchor": 0,
				"focusNotes": "Override focus.",
				"summaryMarkdown": "Override summary."
			}
		]
	}`)

	database := openStore(t, filepath.Join(t.TempDir(), "check-ins-override.db"))
	t.Cleanup(func() { _ = database.Close() })

	summary, err := demo.Seed(database, demo.Options{
		Scenario: "demo",
		Anchor:   testAnchor,
		Fixture:  dir,
	})
	if err != nil {
		t.Fatalf("seed with check-ins override: %v", err)
	}
	user, err := database.UserByEmail(demo.DemoEmail)
	if err != nil {
		t.Fatalf("read demo account: %v", err)
	}
	checkIns, err := database.CheckIns(user.ID, "")
	if err != nil {
		t.Fatalf("list check-ins: %v", err)
	}
	if summary.CheckIns != 1 || len(checkIns) != 1 {
		t.Fatalf("check-ins = %d, summary = %d, want the single override", len(checkIns), summary.CheckIns)
	}
	checkIn := checkIns[0]
	if checkIn.Kind != domain.CheckInKindPersonal ||
		checkIn.FocusNotes != "Override focus." ||
		checkIn.SummaryMarkdown != "Override summary." {
		t.Fatalf("override check-in = %+v, want the declared personal draft", checkIn)
	}
	if checkIn.PeriodStart != anchorDaysAgo(6) || checkIn.PeriodEnd != anchorDaysAgo(0) {
		t.Fatalf("override period = %s..%s, want %s..%s",
			checkIn.PeriodStart, checkIn.PeriodEnd, anchorDaysAgo(6), anchorDaysAgo(0))
	}
	if checkIn.Totals.Minutes != 2070 {
		t.Fatalf("override totals minutes = %d, want the current-period report 2070", checkIn.Totals.Minutes)
	}
}

func TestLoadFixtureRejectsAFinalPersonalReview(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "check_ins.json", `{
		"checkIns": [
			{
				"key": "bad-review",
				"kind": "personal",
				"state": "final",
				"periodStartOffset": 6,
				"periodEndOffset": 0,
				"createdDaysBeforeAnchor": 0
			}
		]
	}`)

	_, err := demo.LoadFixture(dir)
	if err == nil || !strings.Contains(err.Error(), "only a manager") {
		t.Fatalf("error = %v, want the final-personal-review rejection", err)
	}
}

func TestLoadFixtureRejectsDuplicateCheckInCreatedOrdering(t *testing.T) {
	dir := t.TempDir()
	writeFixtureFile(t, dir, "check_ins.json", `{
		"checkIns": [
			{
				"key": "first",
				"kind": "manager",
				"state": "final",
				"periodStartOffset": 13,
				"periodEndOffset": 7,
				"createdDaysBeforeAnchor": 0
			},
			{
				"key": "second",
				"kind": "personal",
				"state": "draft",
				"periodStartOffset": 6,
				"periodEndOffset": 0,
				"createdDaysBeforeAnchor": 0
			}
		]
	}`)

	_, err := demo.LoadFixture(dir)
	if err == nil || !strings.Contains(err.Error(), "ordering would be unstable") {
		t.Fatalf("error = %v, want a duplicate-created-order rejection", err)
	}
}
