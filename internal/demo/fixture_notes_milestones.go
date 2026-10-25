package demo

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// The fixture window is the 14-day demo window ending on the anchor date.
// Relative offsets keep notes and milestones meaningful for any --anchor.
const (
	fixtureWindowDays        = 14
	fixtureMaxNoteLength     = 4000
	fixtureMaxMilestoneTitle = 120
)

// NotesFixture is the declarative day-note and project-note dataset. Day notes
// attach to a calendar date; project notes attach to an initiative project.
type NotesFixture struct {
	DayNotes     []DayNoteFixture     `json:"dayNotes"`
	ProjectNotes []ProjectNoteFixture `json:"projectNotes"`
}

// DayNoteFixture is a note on one day of the 14-day window. DaysBeforeAnchor 0
// is the anchor day itself, which is the note Today displays.
type DayNoteFixture struct {
	DaysBeforeAnchor int    `json:"daysBeforeAnchor"`
	Text             string `json:"text"`
}

// ProjectNoteFixture is a note attached to an initiative project. Key only
// needs to be unique within its project; it keeps IDs stable when texts change.
type ProjectNoteFixture struct {
	Key              string `json:"key"`
	Category         string `json:"category"`
	Subcategory      string `json:"subcategory"`
	DaysBeforeAnchor int    `json:"daysBeforeAnchor"`
	Text             string `json:"text"`
}

// MilestonesFixture is the declarative milestone dataset.
type MilestonesFixture struct {
	Milestones []MilestoneFixture `json:"milestones"`
}

// MilestoneFixture is a dated checkpoint on an initiative project. DueOffsetDays
// is relative to the anchor: negative is past, zero is the anchor date, positive
// is future.
type MilestoneFixture struct {
	Key           string `json:"key"`
	Category      string `json:"category"`
	Subcategory   string `json:"subcategory"`
	Title         string `json:"title"`
	DueOffsetDays int    `json:"dueOffsetDays"`
	Done          bool   `json:"done"`
}

// projectRefs maps "category/subcategory" to the category role. Names are
// trimmed exactly as seedDemo trims them before deriving stable IDs.
func (f Fixture) projectRefs() map[string]domain.CategoryRole {
	refs := make(map[string]domain.CategoryRole)
	for _, category := range f.Taxonomy.Categories {
		categoryName := strings.TrimSpace(category.Name)
		for _, subcategory := range category.Subcategories {
			refs[fixtureProjectRef(categoryName, subcategory.Name)] = category.Role
		}
	}
	return refs
}

// validateNotes rejects ambiguous or inconsistent note fixtures. The dataset is
// spec-driven, so the validator checks structure and project attachments but
// leaves counts and exact texts to the fixture and its tests.
func (f Fixture) validateNotes() error {
	refs := f.projectRefs()

	seenDays := make(map[int]struct{}, len(f.Notes.DayNotes))
	hasAnchorDay := false
	for i, note := range f.Notes.DayNotes {
		text := strings.TrimSpace(note.Text)
		if text == "" {
			return fmt.Errorf("fixture notes dayNotes[%d]: text is required", i)
		}
		if len(text) > fixtureMaxNoteLength {
			return fmt.Errorf("fixture notes dayNotes[%d]: text must be at most %d characters", i, fixtureMaxNoteLength)
		}
		if note.DaysBeforeAnchor < 0 || note.DaysBeforeAnchor >= fixtureWindowDays {
			return fmt.Errorf("fixture notes dayNotes[%d]: daysBeforeAnchor must be between 0 and %d", i, fixtureWindowDays-1)
		}
		if _, duplicate := seenDays[note.DaysBeforeAnchor]; duplicate {
			return fmt.Errorf("fixture notes dayNotes[%d]: daysBeforeAnchor %d is duplicated", i, note.DaysBeforeAnchor)
		}
		seenDays[note.DaysBeforeAnchor] = struct{}{}
		if note.DaysBeforeAnchor == 0 {
			hasAnchorDay = true
		}
	}
	if len(f.Notes.DayNotes) > 0 && !hasAnchorDay {
		return fmt.Errorf("fixture notes: day notes must include the anchor day (daysBeforeAnchor 0)")
	}

	projectKeys := make(map[string]struct{}, len(f.Notes.ProjectNotes))
	for i, note := range f.Notes.ProjectNotes {
		if strings.TrimSpace(note.Category) == "" || strings.TrimSpace(note.Subcategory) == "" {
			return fmt.Errorf("fixture notes projectNotes[%d]: category and subcategory are required", i)
		}
		ref := fixtureProjectRef(note.Category, note.Subcategory)
		role, ok := refs[ref]
		if !ok {
			return fmt.Errorf("fixture notes projectNotes[%d]: unknown subcategory %q", i, ref)
		}
		if role != domain.CategoryRoleInitiative {
			return fmt.Errorf("fixture notes projectNotes[%d]: %q is not an initiative project", i, ref)
		}
		text := strings.TrimSpace(note.Text)
		if text == "" {
			return fmt.Errorf("fixture notes projectNotes[%d]: text is required", i)
		}
		if len(text) > fixtureMaxNoteLength {
			return fmt.Errorf("fixture notes projectNotes[%d]: text must be at most %d characters", i, fixtureMaxNoteLength)
		}
		if note.DaysBeforeAnchor < 0 || note.DaysBeforeAnchor >= fixtureWindowDays {
			return fmt.Errorf("fixture notes projectNotes[%d]: daysBeforeAnchor must be between 0 and %d", i, fixtureWindowDays-1)
		}
		key := strings.TrimSpace(note.Key)
		if key == "" {
			return fmt.Errorf("fixture notes projectNotes[%d]: key is required", i)
		}
		dedupeKey := ref + "/" + key
		if _, duplicate := projectKeys[dedupeKey]; duplicate {
			return fmt.Errorf("fixture notes projectNotes[%d]: key %q is duplicated for %s", i, key, ref)
		}
		projectKeys[dedupeKey] = struct{}{}
	}
	return nil
}

// validateMilestones rejects milestones that do not attach to an initiative
// project or that reuse a key within one project.
func (f Fixture) validateMilestones() error {
	refs := f.projectRefs()

	keys := make(map[string]struct{}, len(f.Milestones.Milestones))
	for i, milestone := range f.Milestones.Milestones {
		if strings.TrimSpace(milestone.Category) == "" || strings.TrimSpace(milestone.Subcategory) == "" {
			return fmt.Errorf("fixture milestones[%d]: category and subcategory are required", i)
		}
		ref := fixtureProjectRef(milestone.Category, milestone.Subcategory)
		role, ok := refs[ref]
		if !ok {
			return fmt.Errorf("fixture milestones[%d]: unknown subcategory %q", i, ref)
		}
		if role != domain.CategoryRoleInitiative {
			return fmt.Errorf("fixture milestones[%d]: %q is not an initiative project", i, ref)
		}
		title := strings.TrimSpace(milestone.Title)
		if title == "" {
			return fmt.Errorf("fixture milestones[%d]: title is required", i)
		}
		if len(title) > fixtureMaxMilestoneTitle {
			return fmt.Errorf("fixture milestones[%d]: title must be at most %d characters", i, fixtureMaxMilestoneTitle)
		}
		key := strings.TrimSpace(milestone.Key)
		if key == "" {
			return fmt.Errorf("fixture milestones[%d]: key is required", i)
		}
		dedupeKey := ref + "/" + key
		if _, duplicate := keys[dedupeKey]; duplicate {
			return fmt.Errorf("fixture milestones[%d]: key %q is duplicated for %s", i, key, ref)
		}
		keys[dedupeKey] = struct{}{}
	}
	return nil
}

// seedNotes writes the fixture's day notes and project notes. Day-note IDs key
// on the relative day, not the resolved date, so changing --anchor changes the
// content but not the identifiers.
func seedNotes(database *store.Store, userID, scenario string, fixture Fixture, anchor time.Time) (int, error) {
	count := 0

	for _, note := range fixture.Notes.DayNotes {
		date := anchor.AddDate(0, 0, -note.DaysBeforeAnchor)
		record := domain.Note{
			ID:        stableID(scenario, "note", "day/"+strconv.Itoa(note.DaysBeforeAnchor)),
			UserID:    userID,
			Date:      date.Format(domain.DateLayout),
			Text:      strings.TrimSpace(note.Text),
			CreatedAt: date.Add(18 * time.Hour),
		}
		if err := database.SaveNote(record); err != nil {
			return 0, fmt.Errorf("save demo day note for %s: %w", record.Date, err)
		}
		count++
	}

	for i, note := range fixture.Notes.ProjectNotes {
		date := anchor.AddDate(0, 0, -note.DaysBeforeAnchor)
		record := domain.Note{
			ID:            stableID(scenario, "note", "project/"+fixtureProjectRef(note.Category, note.Subcategory)+"/"+strings.TrimSpace(note.Key)),
			UserID:        userID,
			SubcategoryID: stableSubcategoryID(scenario, note.Category, note.Subcategory),
			Text:          strings.TrimSpace(note.Text),
			CreatedAt:     date.Add(10*time.Hour + time.Duration(i)*time.Minute),
		}
		if err := database.SaveNote(record); err != nil {
			return 0, fmt.Errorf("save demo project note %q: %w", note.Key, err)
		}
		count++
	}

	return count, nil
}

// seedMilestones writes the fixture's milestones. DueDate and timestamps derive
// from the anchor, so the done/overdue/upcoming mix holds for any anchor.
func seedMilestones(database *store.Store, userID, scenario string, fixture Fixture, anchor time.Time) (int, error) {
	for i, milestone := range fixture.Milestones.Milestones {
		due := anchor.AddDate(0, 0, milestone.DueOffsetDays)
		createdAt := anchor.AddDate(0, 0, -30).Add(time.Duration(i) * time.Minute)
		record := domain.Milestone{
			ID:            stableID(scenario, "milestone", fixtureProjectRef(milestone.Category, milestone.Subcategory)+"/"+strings.TrimSpace(milestone.Key)),
			UserID:        userID,
			SubcategoryID: stableSubcategoryID(scenario, milestone.Category, milestone.Subcategory),
			Title:         strings.TrimSpace(milestone.Title),
			DueDate:       due.Format(domain.DateLayout),
			Done:          milestone.Done,
			CreatedAt:     createdAt,
			UpdatedAt:     createdAt,
		}
		if err := database.SaveMilestone(record); err != nil {
			return 0, fmt.Errorf("save demo milestone %q: %w", milestone.Key, err)
		}
	}
	return len(fixture.Milestones.Milestones), nil
}
