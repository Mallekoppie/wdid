package domain_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func assertField(t *testing.T, err error, want string) {
	t.Helper()

	var validation domain.ValidationError
	if !errors.As(err, &validation) {
		t.Fatalf("expected ValidationError, got %v", err)
	}
	if validation.Field != want {
		t.Fatalf("field = %q, want %q (%v)", validation.Field, want, err)
	}
}

func validCategory() domain.Category {
	now := time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)
	return domain.Category{
		ID:        "category-1",
		UserID:    "user-1",
		Name:      "Initiatives",
		Role:      domain.CategoryRoleInitiative,
		Color:     "#00696D",
		SortOrder: 0,
		CreatedAt: now,
		UpdatedAt: now,
	}
}

func TestValidateCategory(t *testing.T) {
	tests := []struct {
		name      string
		mutate    func(*domain.Category)
		wantField string
	}{
		{name: "valid"},
		{name: "missing name", mutate: func(c *domain.Category) { c.Name = "  " }, wantField: "name"},
		{name: "long name", mutate: func(c *domain.Category) { c.Name = strings.Repeat("a", 121) }, wantField: "name"},
		{name: "unknown role", mutate: func(c *domain.Category) { c.Role = "project" }, wantField: "role"},
		{name: "bad color", mutate: func(c *domain.Category) { c.Color = "teal" }, wantField: "color"},
		{name: "negative sort order", mutate: func(c *domain.Category) { c.SortOrder = -1 }, wantField: "sortOrder"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			category := validCategory()
			if test.mutate != nil {
				test.mutate(&category)
			}

			err := domain.ValidateCategory(category)
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			assertField(t, err, test.wantField)
		})
	}
}

func validSubcategory() domain.Subcategory {
	now := time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)
	return domain.Subcategory{
		ID:            "subcategory-1",
		UserID:        "user-1",
		CategoryID:    "category-1",
		Name:          "Billing migration",
		Description:   "Move invoicing to the new pipeline",
		Status:        domain.SubcategoryActive,
		Progress:      64,
		TargetOutcome: "Invoice generation under 5 minutes",
		TargetDate:    "2026-11-30",
		Links:         []domain.Link{{Label: "Epic", URL: "https://example.com/epic"}},
		CreatedAt:     now,
		UpdatedAt:     now,
	}
}

func TestValidateSubcategory(t *testing.T) {
	tests := []struct {
		name      string
		mutate    func(*domain.Subcategory)
		wantField string
	}{
		{name: "valid"},
		{name: "missing name", mutate: func(s *domain.Subcategory) { s.Name = "" }, wantField: "name"},
		{name: "no target date", mutate: func(s *domain.Subcategory) { s.TargetDate = "" }},
		{
			name:      "belongs to another category",
			mutate:    func(s *domain.Subcategory) { s.CategoryID = "category-2" },
			wantField: "categoryId",
		},
		{
			name:      "belongs to another user",
			mutate:    func(s *domain.Subcategory) { s.UserID = "user-2" },
			wantField: "categoryId",
		},
		{name: "unknown status", mutate: func(s *domain.Subcategory) { s.Status = "paused" }, wantField: "status"},
		{name: "progress below zero", mutate: func(s *domain.Subcategory) { s.Progress = -1 }, wantField: "progress"},
		{name: "progress above one hundred", mutate: func(s *domain.Subcategory) { s.Progress = 101 }, wantField: "progress"},
		{name: "non-iso target date", mutate: func(s *domain.Subcategory) { s.TargetDate = "30-11-2026" }, wantField: "targetDate"},
		{
			name: "too many links",
			mutate: func(s *domain.Subcategory) {
				s.Links = make([]domain.Link, 21)
				for i := range s.Links {
					s.Links[i] = domain.Link{URL: "https://example.com"}
				}
			},
			wantField: "links",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			subcategory := validSubcategory()
			if test.mutate != nil {
				test.mutate(&subcategory)
			}

			err := domain.ValidateSubcategory(subcategory, validCategory())
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			assertField(t, err, test.wantField)
		})
	}
}

func validWorkEntry() domain.WorkEntry {
	start := time.Date(2026, 10, 17, 7, 15, 0, 0, time.UTC)
	return domain.WorkEntry{
		ID:            "entry-1",
		UserID:        "user-1",
		CategoryID:    "category-1",
		SubcategoryID: "subcategory-1",
		Description:   "Backfill script skeleton",
		Outcome:       "Script runs against staging",
		StartedAt:     start,
		EndedAt:       start.Add(42 * time.Minute),
		Minutes:       42,
		LocalDate:     "2026-10-17",
		Source:        domain.EntrySourceTimer,
		CreatedAt:     start,
		UpdatedAt:     start,
	}
}

func TestValidateWorkEntry(t *testing.T) {
	subcategory := validSubcategory()

	tests := []struct {
		name      string
		mutate    func(*domain.WorkEntry)
		wantField string
	}{
		{name: "valid"},
		{name: "no subcategory", mutate: func(e *domain.WorkEntry) { e.SubcategoryID = "" }},
		{name: "manual source", mutate: func(e *domain.WorkEntry) { e.Source = domain.EntrySourceManual }},
		{name: "missing category", mutate: func(e *domain.WorkEntry) { e.CategoryID = "" }, wantField: "categoryId"},
		{name: "category mismatch", mutate: func(e *domain.WorkEntry) { e.CategoryID = "category-2" }, wantField: "categoryId"},
		{name: "missing description", mutate: func(e *domain.WorkEntry) { e.Description = " " }, wantField: "description"},
		{name: "long outcome", mutate: func(e *domain.WorkEntry) { e.Outcome = strings.Repeat("a", 1001) }, wantField: "outcome"},
		{name: "missing start", mutate: func(e *domain.WorkEntry) { e.StartedAt = time.Time{} }, wantField: "startedAt"},
		{name: "missing end", mutate: func(e *domain.WorkEntry) { e.EndedAt = time.Time{} }, wantField: "endedAt"},
		{
			name:      "subcategory from another category",
			mutate:    func(e *domain.WorkEntry) { e.SubcategoryID = "subcategory-2" },
			wantField: "subcategoryId",
		},
		{name: "unknown source", mutate: func(e *domain.WorkEntry) { e.Source = "import" }, wantField: "source"},
		{
			name: "too many tags",
			mutate: func(e *domain.WorkEntry) {
				e.Tags = make([]string, 21)
				for i := range e.Tags {
					e.Tags[i] = "tag"
				}
			},
			wantField: "tags",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			entry := validWorkEntry()
			if test.mutate != nil {
				test.mutate(&entry)
			}

			var sub *domain.Subcategory
			if entry.SubcategoryID != "" {
				sub = &subcategory
			}

			err := domain.ValidateWorkEntry(entry, validCategory(), sub, 240)
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			assertField(t, err, test.wantField)
		})
	}
}

func TestValidateWorkEntryBlockLimit(t *testing.T) {
	entry := validWorkEntry()
	entry.Minutes = 300

	assertField(t, domain.ValidateWorkEntry(entry, validCategory(), nil, 240), "minutes")
}

func TestValidateWorkEntryRequiresPersonForSupport(t *testing.T) {
	category := validCategory()
	category.ID = "category-support"
	category.Role = domain.CategoryRoleSupport

	subcategory := validSubcategory()
	subcategory.CategoryID = category.ID

	entry := validWorkEntry()
	entry.CategoryID = category.ID
	entry.SubcategoryID = subcategory.ID

	assertField(t, domain.ValidateWorkEntry(entry, category, &subcategory, 0), "person")

	// Blank names do not count as a person.
	entry.People = []string{"  ", ""}
	assertField(t, domain.ValidateWorkEntry(entry, category, &subcategory, 0), "person")

	entry.People = []string{"Priya"}
	if err := domain.ValidateWorkEntry(entry, category, &subcategory, 0); err != nil {
		t.Fatalf("support entry with a person: %v", err)
	}

	// An entry may support several people.
	entry.People = []string{"Priya", "Sam"}
	if err := domain.ValidateWorkEntry(entry, category, &subcategory, 0); err != nil {
		t.Fatalf("support entry with several people: %v", err)
	}

	// A person is optional outside support-role categories.
	initiative := validCategory()
	initiativeSubcategory := validSubcategory()
	entry = validWorkEntry()
	entry.People = nil
	if err := domain.ValidateWorkEntry(entry, initiative, &initiativeSubcategory, 0); err != nil {
		t.Fatalf("non-support entry without a person: %v", err)
	}
}

func validMilestone() domain.Milestone {
	now := time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)
	return domain.Milestone{
		ID:            "milestone-1",
		UserID:        "user-1",
		SubcategoryID: "subcategory-1",
		Title:         "Ship backfill to staging",
		DueDate:       "2026-10-31",
		CreatedAt:     now,
		UpdatedAt:     now,
	}
}

func TestValidateMilestone(t *testing.T) {
	tests := []struct {
		name      string
		mutate    func(*domain.Milestone)
		wantField string
	}{
		{name: "valid"},
		{name: "without due date", mutate: func(m *domain.Milestone) { m.DueDate = "" }},
		{name: "missing title", mutate: func(m *domain.Milestone) { m.Title = " " }, wantField: "title"},
		{name: "missing subcategory", mutate: func(m *domain.Milestone) { m.SubcategoryID = "" }, wantField: "subcategoryId"},
		{name: "bad due date", mutate: func(m *domain.Milestone) { m.DueDate = "31/10/2026" }, wantField: "dueDate"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			milestone := validMilestone()
			if test.mutate != nil {
				test.mutate(&milestone)
			}

			err := domain.ValidateMilestone(milestone)
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			assertField(t, err, test.wantField)
		})
	}
}

func validNote() domain.Note {
	return domain.Note{
		ID:            "note-1",
		UserID:        "user-1",
		Date:          "2026-10-17",
		SubcategoryID: "subcategory-1",
		Text:          "Backfill work is stable enough to track by project.",
		CreatedAt:     time.Date(2026, 10, 17, 18, 0, 0, 0, time.UTC),
	}
}

func TestValidateNote(t *testing.T) {
	tests := []struct {
		name      string
		mutate    func(*domain.Note)
		wantField string
	}{
		{name: "date and subcategory"},
		{name: "date only", mutate: func(n *domain.Note) { n.SubcategoryID = "" }},
		{name: "subcategory only", mutate: func(n *domain.Note) { n.Date = "" }},
		{
			name:      "neither date nor subcategory",
			mutate:    func(n *domain.Note) { n.Date = ""; n.SubcategoryID = "" },
			wantField: "date",
		},
		{name: "missing text", mutate: func(n *domain.Note) { n.Text = "" }, wantField: "text"},
		{name: "bad date", mutate: func(n *domain.Note) { n.Date = "17-10-2026" }, wantField: "date"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			note := validNote()
			if test.mutate != nil {
				test.mutate(&note)
			}

			err := domain.ValidateNote(note)
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			assertField(t, err, test.wantField)
		})
	}
}

func validCheckIn() domain.CheckIn {
	now := time.Date(2026, 10, 2, 17, 0, 0, 0, time.UTC)
	return domain.CheckIn{
		ID:              "checkin-1",
		UserID:          "user-1",
		Kind:            domain.CheckInKindManager,
		PeriodStart:     "2026-07-01",
		PeriodEnd:       "2026-10-02",
		State:           domain.CheckInStateDraft,
		Audience:        domain.AudienceOneOnOne,
		FocusNotes:      "Focus on the billing migration.",
		SummaryMarkdown: "## Summary",
		SummaryModel:    "test-model",
		PromptVersion:   "v1",
		Totals: domain.CheckInTotals{
			Minutes:         12780,
			ByCategory:      map[string]int{"Initiatives": 2300, "Support": 870},
			BySubcategory:   map[string]int{"Billing migration": 2300},
			SupportByPerson: map[string]int{"Priya": 250},
		},
		CreatedAt: now,
		UpdatedAt: now,
	}
}

func TestValidateCheckIn(t *testing.T) {
	tests := []struct {
		name      string
		mutate    func(*domain.CheckIn)
		wantField string
	}{
		{name: "valid manager check-in"},
		{name: "final manager check-in", mutate: func(c *domain.CheckIn) { c.State = domain.CheckInStateFinal }},
		{
			name: "personal review without audience",
			mutate: func(c *domain.CheckIn) {
				c.Kind = domain.CheckInKindPersonal
				c.Audience = ""
			},
		},
		{name: "unknown kind", mutate: func(c *domain.CheckIn) { c.Kind = "quarterly" }, wantField: "kind"},
		{name: "unknown state", mutate: func(c *domain.CheckIn) { c.State = "ready" }, wantField: "state"},
		{
			name: "final personal review",
			mutate: func(c *domain.CheckIn) {
				c.Kind = domain.CheckInKindPersonal
				c.Audience = ""
				c.State = domain.CheckInStateFinal
			},
			wantField: "state",
		},
		{name: "unknown audience", mutate: func(c *domain.CheckIn) { c.Audience = "all_hands" }, wantField: "audience"},
		{
			name: "personal review with audience",
			mutate: func(c *domain.CheckIn) {
				c.Kind = domain.CheckInKindPersonal
			},
			wantField: "audience",
		},
		{name: "bad period start", mutate: func(c *domain.CheckIn) { c.PeriodStart = "01-07-2026" }, wantField: "periodStart"},
		{name: "period ends before it starts", mutate: func(c *domain.CheckIn) { c.PeriodEnd = "2026-06-30" }, wantField: "periodEnd"},
		{name: "negative totals", mutate: func(c *domain.CheckIn) { c.Totals.Minutes = -1 }, wantField: "totals"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			checkIn := validCheckIn()
			if test.mutate != nil {
				test.mutate(&checkIn)
			}

			err := domain.ValidateCheckIn(checkIn)
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			assertField(t, err, test.wantField)
		})
	}
}

func TestDefaultSettings(t *testing.T) {
	settings := domain.DefaultSettings("user-1")

	if settings.UserID != "user-1" {
		t.Fatalf("userId = %q, want user-1", settings.UserID)
	}
	if settings.Timezone != "UTC" || settings.WeekStart != int(time.Monday) {
		t.Fatalf("defaults = %+v, want UTC and Monday week start", settings)
	}
	if settings.DailyTargetMinutes != 450 || settings.DefaultDurationMinutes != 30 {
		t.Fatalf("defaults = %+v, want 450 daily target and 30 minute entries", settings)
	}
	if settings.LongTimerMinutes != 240 {
		t.Fatalf("long timer = %d, want 240", settings.LongTimerMinutes)
	}
	if settings.Theme != domain.ThemeSystem || settings.Density != domain.DensityComfortable {
		t.Fatalf("defaults = %+v, want system theme and comfortable density", settings)
	}
	if err := domain.ValidateSettings(settings); err != nil {
		t.Fatalf("default settings must validate: %v", err)
	}
}

func TestValidateSettings(t *testing.T) {
	tests := []struct {
		name      string
		mutate    func(*domain.Settings)
		wantField string
	}{
		{name: "valid defaults"},
		{name: "unknown timezone", mutate: func(s *domain.Settings) { s.Timezone = "Mars/Olympus" }, wantField: "timezone"},
		{name: "week starts out of range", mutate: func(s *domain.Settings) { s.WeekStart = 8 }, wantField: "weekStart"},
		{name: "negative daily target", mutate: func(s *domain.Settings) { s.DailyTargetMinutes = -1 }, wantField: "dailyTargetMinutes"},
		{name: "unknown review cadence", mutate: func(s *domain.Settings) { s.ReviewCadence = "daily" }, wantField: "reviewCadence"},
		{name: "zero long timer", mutate: func(s *domain.Settings) { s.LongTimerMinutes = 0 }, wantField: "longTimerMinutes"},
		{name: "zero default duration", mutate: func(s *domain.Settings) { s.DefaultDurationMinutes = 0 }, wantField: "defaultDurationMinutes"},
		{name: "zero backup interval", mutate: func(s *domain.Settings) { s.BackupIntervalHours = 0 }, wantField: "backupIntervalHours"},
		{name: "zero backup retention", mutate: func(s *domain.Settings) { s.BackupRetention = 0 }, wantField: "backupRetention"},
		{name: "unknown theme", mutate: func(s *domain.Settings) { s.Theme = "solarized" }, wantField: "theme"},
		{name: "unknown density", mutate: func(s *domain.Settings) { s.Density = "spacious" }, wantField: "density"},
		{name: "bad journal start", mutate: func(s *domain.Settings) { s.JournalStartDate = "yesterday" }, wantField: "journalStartDate"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			settings := domain.DefaultSettings("user-1")
			if test.mutate != nil {
				test.mutate(&settings)
			}

			err := domain.ValidateSettings(settings)
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			assertField(t, err, test.wantField)
		})
	}
}
