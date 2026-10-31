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

// AI provider presets. The model is always editable; these values only seed a
// new account or a newly chosen preset.
const (
	AIProviderAnthropicBaseURL = "https://api.anthropic.com"
	AIProviderAnthropicModel   = "claude-sonnet-5-5"
	AIProviderDeepSeekBaseURL  = "https://api.deepseek.com/anthropic"
	AIProviderDeepSeekModel    = "deepseek-flash"

	// retiredOpenAIBaseURL and retiredOpenAIModel were the deployment-wide
	// defaults before the Anthropic Messages provider and per-user keys. Stored
	// settings records may still carry them.
	retiredOpenAIBaseURL = "https://api.openai.com/v1"
	retiredOpenAIModel   = "gpt-4.1-mini"
)

// Settings is the single per-user behaviour and appearance record. The AI key
// is stored in this record in cleartext for now; encryption is backlog. It is
// write-only over the RPC surface and never exported.
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
	// PromptTemplates holds the caller's own instruction body per check-in
	// variant. A missing or blank entry means the variant's built-in body; the
	// server-owned PromptRules are always appended and cannot be overridden.
	PromptTemplates map[PromptVariant]string `json:"promptTemplates,omitempty"`
	// AIAPIKey is the caller's own provider key. It is write-only over RPC and
	// never leaves the service except as the provider request header.
	AIAPIKey         string    `json:"aiApiKey,omitempty"`
	Theme            Theme     `json:"theme"`
	Density          Density   `json:"density"`
	JournalStartDate string    `json:"journalStartDate,omitempty"`
	UpdatedAt        time.Time `json:"updatedAt"`

	// SupportPeople is the per-user roster of names offered wherever a support
	// person is entered. It is a list of names, not references to a Person
	// entity, so renaming or removing one never rewrites historical entries.
	SupportPeople []string `json:"supportPeople,omitempty"`
	// SupportPeopleSeeded records that the roster has been seeded from the
	// account's existing support entries. It is an internal marker and is never
	// sent over the wire: once set, a deliberately emptied roster stays empty.
	SupportPeopleSeeded bool `json:"supportPeopleSeeded,omitempty"`
}

// HasAIKey reports whether the account has stored a provider key. The key
// itself is never exposed to clients.
func (s Settings) HasAIKey() bool {
	return strings.TrimSpace(s.AIAPIKey) != ""
}

// MigrateLegacyAIDefaults rewrites the retired OpenAI base URL and model, and
// empty AI endpoint values, to the Anthropic preset. Accounts created before
// the Anthropic provider therefore generate without a manual reselection.
// Custom base URLs and models are preserved. It returns whether the record
// changed. The API key is never touched.
func (s *Settings) MigrateLegacyAIDefaults() bool {
	changed := false

	switch strings.TrimSpace(s.AIBaseURL) {
	case "", retiredOpenAIBaseURL:
		if s.AIBaseURL != AIProviderAnthropicBaseURL {
			s.AIBaseURL = AIProviderAnthropicBaseURL
			changed = true
		}
	}

	switch strings.TrimSpace(s.AIModel) {
	case "", retiredOpenAIModel:
		if s.AIModel != AIProviderAnthropicModel {
			s.AIModel = AIProviderAnthropicModel
			changed = true
		}
	}

	return changed
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
		AIBaseURL:              AIProviderAnthropicBaseURL,
		AIModel:                AIProviderAnthropicModel,
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
	s.AIAPIKey = strings.TrimSpace(s.AIAPIKey)
	s.JournalStartDate = strings.TrimSpace(s.JournalStartDate)
	s.SupportPeople = NormalizeList(s.SupportPeople)
	s.PromptTemplates = normalizePromptTemplates(s.PromptTemplates)
	s.UpdatedAt = utc(s.UpdatedAt)
}

// normalizePromptTemplates trims every stored body and drops blank entries, so
// a whitespace-only save is recorded as "use the built-in" rather than as an
// override that resolves to nothing.
func normalizePromptTemplates(templates map[PromptVariant]string) map[PromptVariant]string {
	if len(templates) == 0 {
		return nil
	}
	normalized := make(map[PromptVariant]string, len(templates))
	for variant, body := range templates {
		if !variant.Valid() {
			continue
		}
		if trimmed := strings.TrimSpace(body); trimmed != "" {
			normalized[variant] = trimmed
		}
	}
	if len(normalized) == 0 {
		return nil
	}
	return normalized
}
