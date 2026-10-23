package domain

import (
	"strings"
	"time"
)

// ReviewCadence controls the personal-review prompt.
type ReviewCadence string

const (
	ReviewCadenceWeekly  ReviewCadence = "weekly"
	ReviewCadenceMonthly ReviewCadence = "monthly"
	ReviewCadenceOff     ReviewCadence = "off"
)

// Valid reports whether the review cadence is known.
func (r ReviewCadence) Valid() bool {
	switch r {
	case ReviewCadenceWeekly, ReviewCadenceMonthly, ReviewCadenceOff:
		return true
	default:
		return false
	}
}

// Theme is the user's colour scheme preference.
type Theme string

const (
	ThemeSystem       Theme = "system"
	ThemeLight        Theme = "light"
	ThemeDark         Theme = "dark"
	ThemeHighContrast Theme = "high_contrast"
)

// Valid reports whether the theme is known.
func (t Theme) Valid() bool {
	switch t {
	case ThemeSystem, ThemeLight, ThemeDark, ThemeHighContrast:
		return true
	default:
		return false
	}
}

// Density is the user's row-density preference.
type Density string

const (
	DensityComfortable Density = "comfortable"
	DensityCompact     Density = "compact"
)

// Valid reports whether the density is known.
func (d Density) Valid() bool {
	switch d {
	case DensityComfortable, DensityCompact:
		return true
	default:
		return false
	}
}

// Settings is the single per-user behaviour and appearance record. The AI key
// is never stored here; it comes from the environment.
type Settings struct {
	UserID                 string        `json:"userId"`
	Timezone               string        `json:"timezone"`
	WeekStart              int           `json:"weekStart"`
	DailyTargetMinutes     int           `json:"dailyTargetMinutes"`
	ReviewCadence          ReviewCadence `json:"reviewCadence"`
	LongTimerMinutes       int           `json:"longTimerMinutes"`
	DefaultDurationMinutes int           `json:"defaultDurationMinutes"`
	BackupDirectory        string        `json:"backupDirectory,omitempty"`
	BackupIntervalHours    int           `json:"backupIntervalHours"`
	BackupRetention        int           `json:"backupRetention"`
	AIBaseURL              string        `json:"aiBaseUrl,omitempty"`
	AIModel                string        `json:"aiModel,omitempty"`
	AIRedact               bool          `json:"aiRedact"`
	Theme                  Theme         `json:"theme"`
	Density                Density       `json:"density"`
	JournalStartDate       string        `json:"journalStartDate,omitempty"`
	UpdatedAt              time.Time     `json:"updatedAt"`
}

// DefaultSettings returns the settings every new account starts with.
func DefaultSettings(userID string) Settings {
	return Settings{
		UserID:                 userID,
		Timezone:               "UTC",
		WeekStart:              int(time.Monday),
		DailyTargetMinutes:     450,
		ReviewCadence:          ReviewCadenceOff,
		LongTimerMinutes:       240,
		DefaultDurationMinutes: 30,
		BackupIntervalHours:    6,
		BackupRetention:        30,
		AIBaseURL:              "https://api.openai.com/v1",
		AIModel:                "gpt-4.1-mini",
		Theme:                  ThemeSystem,
		Density:                DensityComfortable,
	}
}

// Normalize trims settings input into its canonical form.
func (s *Settings) Normalize() {
	s.Timezone = strings.TrimSpace(s.Timezone)
	s.BackupDirectory = strings.TrimSpace(s.BackupDirectory)
	s.AIBaseURL = strings.TrimSpace(s.AIBaseURL)
	s.AIModel = strings.TrimSpace(s.AIModel)
	s.JournalStartDate = strings.TrimSpace(s.JournalStartDate)
	s.UpdatedAt = utc(s.UpdatedAt)
}
