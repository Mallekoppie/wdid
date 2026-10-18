package domain

import (
	"strings"
	"time"

	"github.com/google/uuid"
)

// Role is the coarse access level of a user account.
type Role string

const (
	RoleAdmin Role = "admin"
	RoleUser  Role = "user"
)

// InitiativeStatus describes where an initiative sits in its lifecycle.
type InitiativeStatus string

const (
	InitiativePlanned  InitiativeStatus = "planned"
	InitiativeActive   InitiativeStatus = "active"
	InitiativeBlocked  InitiativeStatus = "blocked"
	InitiativeDone     InitiativeStatus = "done"
	InitiativeArchived InitiativeStatus = "archived"
)

// EntryKind is the single primary attribution of a work entry.
type EntryKind string

const (
	EntryInitiative EntryKind = "initiative"
	EntrySupport    EntryKind = "support"
	EntryOther      EntryKind = "other"
)

// SupportMode classifies how support was delivered.
type SupportMode string

const (
	SupportReview   SupportMode = "review"
	SupportPair     SupportMode = "pair"
	SupportUnblock  SupportMode = "unblock"
	SupportMentor   SupportMode = "mentor"
	SupportIncident SupportMode = "incident"
	SupportOther    SupportMode = "other"
)

// NewID returns a random identifier for a new record.
func NewID() string {
	return uuid.NewString()
}

// User is an account. Credentials are stored separately from the profile.
type User struct {
	ID          string    `json:"id"`
	Email       string    `json:"email"`
	DisplayName string    `json:"displayName"`
	Role        Role      `json:"role"`
	CreatedAt   time.Time `json:"createdAt"`
}

// Initiative is a major body of work that spans days or weeks.
type Initiative struct {
	ID            string           `json:"id"`
	UserID        string           `json:"userId"`
	Name          string           `json:"name"`
	Status        InitiativeStatus `json:"status"`
	TargetOutcome string           `json:"targetOutcome"`
	Progress      int              `json:"progress"`
	Links         []string         `json:"links"`
	CreatedAt     time.Time        `json:"createdAt"`
	UpdatedAt     time.Time        `json:"updatedAt"`
}

// SupportDetail captures the people and mode behind a support entry.
type SupportDetail struct {
	Person string      `json:"person"`
	Team   string      `json:"team,omitempty"`
	Mode   SupportMode `json:"mode"`
	Impact string      `json:"impact,omitempty"`
}

// Entry is a block of work with exactly one primary attribution.
type Entry struct {
	ID           string         `json:"id"`
	UserID       string         `json:"userId"`
	Kind         EntryKind      `json:"kind"`
	InitiativeID string         `json:"initiativeId,omitempty"`
	Description  string         `json:"description"`
	Outcome      string         `json:"outcome,omitempty"`
	StartedAt    time.Time      `json:"startedAt"`
	EndedAt      time.Time      `json:"endedAt"`
	Minutes      int            `json:"minutes"`
	Support      *SupportDetail `json:"support,omitempty"`
	Tags         []string       `json:"tags,omitempty"`
	Links        []string       `json:"links,omitempty"`
	CreatedAt    time.Time      `json:"createdAt"`
	UpdatedAt    time.Time      `json:"updatedAt"`
}

// DurationMinutes returns the recorded minutes, falling back to the timestamp
// span when an explicit duration was not supplied.
func (e Entry) DurationMinutes() int {
	if e.Minutes > 0 {
		return e.Minutes
	}
	if e.EndedAt.After(e.StartedAt) {
		return int(e.EndedAt.Sub(e.StartedAt).Minutes())
	}
	return 0
}

// ActiveTimer is the single running timer for a user.
type ActiveTimer struct {
	UserID             string     `json:"userId"`
	InitiativeID       string     `json:"initiativeId,omitempty"`
	Description        string     `json:"description,omitempty"`
	StartedAt          time.Time  `json:"startedAt"`
	PausedAt           *time.Time `json:"pausedAt,omitempty"`
	SegmentStartedAt   time.Time  `json:"segmentStartedAt"`
	AccumulatedSeconds int64      `json:"accumulatedSeconds"`
}

// Paused reports whether the timer is currently paused.
func (t ActiveTimer) Paused() bool {
	return t.PausedAt != nil
}

// Elapsed returns the running total, excluding paused segments.
func (t ActiveTimer) Elapsed(now time.Time) time.Duration {
	total := time.Duration(t.AccumulatedSeconds) * time.Second
	if t.PausedAt == nil && !t.SegmentStartedAt.IsZero() && now.After(t.SegmentStartedAt) {
		total += now.Sub(t.SegmentStartedAt)
	}
	return total
}

// Normalize trims user input into its canonical form.
func (u *User) Normalize() {
	u.Email = strings.ToLower(strings.TrimSpace(u.Email))
	u.DisplayName = strings.TrimSpace(u.DisplayName)
}

// Normalize trims initiative input into its canonical form.
func (i *Initiative) Normalize() {
	i.Name = strings.TrimSpace(i.Name)
	i.TargetOutcome = strings.TrimSpace(i.TargetOutcome)
	i.Links = NormalizeList(i.Links)
}

// Normalize trims entry input into its canonical form.
func (e *Entry) Normalize() {
	e.Description = strings.TrimSpace(e.Description)
	e.Outcome = strings.TrimSpace(e.Outcome)
	e.InitiativeID = strings.TrimSpace(e.InitiativeID)
	e.Tags = NormalizeList(e.Tags)
	e.Links = NormalizeList(e.Links)
	if e.Support != nil {
		e.Support.Person = strings.TrimSpace(e.Support.Person)
		e.Support.Team = strings.TrimSpace(e.Support.Team)
		e.Support.Impact = strings.TrimSpace(e.Support.Impact)
	}
}

// NormalizeList trims entries, drops empties and removes case-insensitive duplicates.
func NormalizeList(values []string) []string {
	if len(values) == 0 {
		return nil
	}

	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		key := strings.ToLower(trimmed)
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
