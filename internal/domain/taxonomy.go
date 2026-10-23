package domain

import (
	"strings"
	"time"
)

// DateLayout is the canonical form of a local calendar date.
const DateLayout = "2006-01-02"

func utc(t time.Time) time.Time {
	if t.IsZero() {
		return t
	}
	return t.UTC()
}

// CategoryRole is what a category means for reporting and validation. It is
// chosen when the category is created and never changes.
type CategoryRole string

const (
	CategoryRoleInitiative CategoryRole = "initiative"
	CategoryRoleSupport    CategoryRole = "support"
	CategoryRoleOther      CategoryRole = "other"
)

// Valid reports whether the reporting role is known.
func (r CategoryRole) Valid() bool {
	switch r {
	case CategoryRoleInitiative, CategoryRoleSupport, CategoryRoleOther:
		return true
	default:
		return false
	}
}

// SubcategoryStatus describes where a project subcategory sits in its
// lifecycle.
type SubcategoryStatus string

const (
	SubcategoryPlanned  SubcategoryStatus = "planned"
	SubcategoryActive   SubcategoryStatus = "active"
	SubcategoryBlocked  SubcategoryStatus = "blocked"
	SubcategoryDone     SubcategoryStatus = "done"
	SubcategoryArchived SubcategoryStatus = "archived"
)

// Valid reports whether the status is a known lifecycle state.
func (s SubcategoryStatus) Valid() bool {
	switch s {
	case SubcategoryPlanned, SubcategoryActive, SubcategoryBlocked, SubcategoryDone, SubcategoryArchived:
		return true
	default:
		return false
	}
}

// Link is a labelled external reference attached to a record.
type Link struct {
	Label string `json:"label"`
	URL   string `json:"url"`
}

// Category is a user-defined top-level grouping of work with one immutable
// reporting role.
type Category struct {
	ID        string       `json:"id"`
	UserID    string       `json:"userId"`
	Name      string       `json:"name"`
	Role      CategoryRole `json:"role"`
	Color     string       `json:"color,omitempty"`
	SortOrder int          `json:"sortOrder"`
	Archived  bool         `json:"archived"`
	CreatedAt time.Time    `json:"createdAt"`
	UpdatedAt time.Time    `json:"updatedAt"`
}

// Subcategory is the optional second level under a category. Project fields are
// meaningful only under an initiative-role category.
type Subcategory struct {
	ID            string            `json:"id"`
	UserID        string            `json:"userId"`
	CategoryID    string            `json:"categoryId"`
	Name          string            `json:"name"`
	Description   string            `json:"description,omitempty"`
	Status        SubcategoryStatus `json:"status"`
	Progress      int               `json:"progress"`
	TargetOutcome string            `json:"targetOutcome,omitempty"`
	TargetDate    string            `json:"targetDate,omitempty"`
	Links         []Link            `json:"links,omitempty"`
	SortOrder     int               `json:"sortOrder"`
	Archived      bool              `json:"archived"`
	CreatedAt     time.Time         `json:"createdAt"`
	UpdatedAt     time.Time         `json:"updatedAt"`
}

// EntrySource records how a work entry was captured.
type EntrySource string

const (
	EntrySourceTimer  EntrySource = "timer"
	EntrySourceManual EntrySource = "manual"
)

// Valid reports whether the source is known.
func (s EntrySource) Valid() bool {
	switch s {
	case EntrySourceTimer, EntrySourceManual:
		return true
	default:
		return false
	}
}

// WorkEntry is a recorded block of work time with exactly one category and an
// optional subcategory from that category.
type WorkEntry struct {
	ID            string      `json:"id"`
	UserID        string      `json:"userId"`
	CategoryID    string      `json:"categoryId"`
	SubcategoryID string      `json:"subcategoryId,omitempty"`
	Description   string      `json:"description"`
	Outcome       string      `json:"outcome,omitempty"`
	StartedAt     time.Time   `json:"startedAt"`
	EndedAt       time.Time   `json:"endedAt"`
	Minutes       int         `json:"minutes"`
	LocalDate     string      `json:"localDate"`
	Person        string      `json:"person,omitempty"`
	Team          string      `json:"team,omitempty"`
	Tags          []string    `json:"tags,omitempty"`
	Links         []Link      `json:"links,omitempty"`
	Source        EntrySource `json:"source"`
	CreatedAt     time.Time   `json:"createdAt"`
	UpdatedAt     time.Time   `json:"updatedAt"`
}

// DurationMinutes returns the recorded minutes, falling back to the timestamp
// span when an explicit duration was not supplied.
func (e WorkEntry) DurationMinutes() int {
	if e.Minutes > 0 {
		return e.Minutes
	}
	if e.EndedAt.After(e.StartedAt) {
		return int(e.EndedAt.Sub(e.StartedAt).Minutes())
	}
	return 0
}

// Normalize trims entry input into its canonical form.
func (e *WorkEntry) Normalize() {
	e.CategoryID = strings.TrimSpace(e.CategoryID)
	e.SubcategoryID = strings.TrimSpace(e.SubcategoryID)
	e.Description = strings.TrimSpace(e.Description)
	e.Outcome = strings.TrimSpace(e.Outcome)
	e.LocalDate = strings.TrimSpace(e.LocalDate)
	e.Person = strings.TrimSpace(e.Person)
	e.Team = strings.TrimSpace(e.Team)
	e.Tags = NormalizeList(e.Tags)
	e.Links = NormalizeLinks(e.Links)
	e.StartedAt = utc(e.StartedAt)
	e.EndedAt = utc(e.EndedAt)
	e.CreatedAt = utc(e.CreatedAt)
	e.UpdatedAt = utc(e.UpdatedAt)
}

// Normalize trims category input into its canonical form and stores
// timestamps in UTC.
func (c *Category) Normalize() {
	c.Name = strings.TrimSpace(c.Name)
	c.Color = strings.TrimSpace(c.Color)
	c.CreatedAt = utc(c.CreatedAt)
	c.UpdatedAt = utc(c.UpdatedAt)
}

// Normalize trims subcategory input into its canonical form.
func (s *Subcategory) Normalize() {
	s.Name = strings.TrimSpace(s.Name)
	s.Description = strings.TrimSpace(s.Description)
	s.TargetOutcome = strings.TrimSpace(s.TargetOutcome)
	s.TargetDate = strings.TrimSpace(s.TargetDate)
	s.Links = NormalizeLinks(s.Links)
	s.CreatedAt = utc(s.CreatedAt)
	s.UpdatedAt = utc(s.UpdatedAt)
}

// NormalizeLinks trims labels and URLs, drops entries without a URL and
// removes duplicate URLs.
func NormalizeLinks(links []Link) []Link {
	if len(links) == 0 {
		return nil
	}

	seen := make(map[string]struct{}, len(links))
	result := make([]Link, 0, len(links))
	for _, link := range links {
		trimmed := Link{
			Label: strings.TrimSpace(link.Label),
			URL:   strings.TrimSpace(link.URL),
		}
		if trimmed.URL == "" {
			continue
		}
		key := strings.ToLower(trimmed.URL)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, trimmed)
	}

	if len(result) == 0 {
		return nil
	}
	return result
}

// Milestone is a dated checkpoint attached to a subcategory.
type Milestone struct {
	ID            string    `json:"id"`
	UserID        string    `json:"userId"`
	SubcategoryID string    `json:"subcategoryId"`
	Title         string    `json:"title"`
	DueDate       string    `json:"dueDate,omitempty"`
	Done          bool      `json:"done"`
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

// Normalize trims milestone input into its canonical form.
func (m *Milestone) Normalize() {
	m.SubcategoryID = strings.TrimSpace(m.SubcategoryID)
	m.Title = strings.TrimSpace(m.Title)
	m.DueDate = strings.TrimSpace(m.DueDate)
	m.CreatedAt = utc(m.CreatedAt)
	m.UpdatedAt = utc(m.UpdatedAt)
}

// Note is free text attached to a day, a subcategory, or both.
type Note struct {
	ID            string    `json:"id"`
	UserID        string    `json:"userId"`
	Date          string    `json:"date,omitempty"`
	SubcategoryID string    `json:"subcategoryId,omitempty"`
	Text          string    `json:"text"`
	CreatedAt     time.Time `json:"createdAt"`
}

// Normalize trims note input into its canonical form.
func (n *Note) Normalize() {
	n.Date = strings.TrimSpace(n.Date)
	n.SubcategoryID = strings.TrimSpace(n.SubcategoryID)
	n.Text = strings.TrimSpace(n.Text)
	n.CreatedAt = utc(n.CreatedAt)
}
