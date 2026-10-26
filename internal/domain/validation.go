package domain

import (
	"fmt"
	"net/mail"
	"regexp"
	"strings"
	"time"
)

const (
	minPasswordLength = 10
	maxNameLength     = 120
	maxDescription    = 500
	maxOutcome        = 1000
	maxNoteLength     = 4000
	maxListItems      = 20
)

var colorPattern = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)

// ValidationError describes a single invalid field.
type ValidationError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

func (e ValidationError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

func invalid(field, message string) error {
	return ValidationError{Field: field, Message: message}
}

// ValidateRegistration checks the fields required to create an account.
func ValidateRegistration(email, password, displayName string) error {
	if err := ValidateEmail(email); err != nil {
		return err
	}
	if len(password) < minPasswordLength {
		return invalid("password", fmt.Sprintf("must be at least %d characters", minPasswordLength))
	}
	if len(strings.TrimSpace(displayName)) > maxNameLength {
		return invalid("displayName", fmt.Sprintf("must be at most %d characters", maxNameLength))
	}
	return nil
}

// ValidateEmail checks for a bare, parseable email address.
func ValidateEmail(email string) error {
	trimmed := strings.TrimSpace(email)
	if trimmed == "" {
		return invalid("email", "is required")
	}
	address, err := mail.ParseAddress(trimmed)
	if err != nil || address.Address != trimmed || !strings.Contains(trimmed, "@") {
		return invalid("email", "must be a valid email address")
	}
	return nil
}

// ValidateRole checks the account role.
func ValidateRole(role Role) error {
	switch role {
	case RoleAdmin, RoleUser:
		return nil
	default:
		return invalid("role", "must be admin or user")
	}
}

// ValidateTimerStart checks the fields needed to start a timer.
func ValidateTimerStart(description string) error {
	if len(strings.TrimSpace(description)) > maxDescription {
		return invalid("description", fmt.Sprintf("must be at most %d characters", maxDescription))
	}
	return nil
}

// ValidateTimeRange checks a period boundary pair.
func ValidateTimeRange(from, to time.Time) error {
	if from.IsZero() || to.IsZero() {
		return invalid("period", "from and to are required")
	}
	if !to.After(from) {
		return invalid("period", "to must be after from")
	}
	return nil
}

// ValidateCategory checks the taxonomy invariants that do not depend on
// existing records. Role immutability is enforced when the category is saved.
func ValidateCategory(category Category) error {
	name := strings.TrimSpace(category.Name)
	if name == "" {
		return invalid("name", "is required")
	}
	if len(name) > maxNameLength {
		return invalid("name", fmt.Sprintf("must be at most %d characters", maxNameLength))
	}
	if !category.Role.Valid() {
		return invalid("role", "must be initiative, support or other")
	}
	if color := strings.TrimSpace(category.Color); color != "" && !colorPattern.MatchString(color) {
		return invalid("color", "must be a hex colour such as #00696D")
	}
	if category.SortOrder < 0 {
		return invalid("sortOrder", "must not be negative")
	}
	return nil
}

// ValidateSubcategory checks a subcategory and confirms that it belongs to the
// given category and user.
func ValidateSubcategory(subcategory Subcategory, category Category) error {
	if strings.TrimSpace(subcategory.CategoryID) == "" {
		return invalid("categoryId", "is required")
	}
	if subcategory.CategoryID != category.ID ||
		(subcategory.UserID != "" && category.UserID != "" && subcategory.UserID != category.UserID) {
		return invalid("categoryId", "subcategory must belong to its category")
	}

	name := strings.TrimSpace(subcategory.Name)
	if name == "" {
		return invalid("name", "is required")
	}
	if len(name) > maxNameLength {
		return invalid("name", fmt.Sprintf("must be at most %d characters", maxNameLength))
	}
	if len(strings.TrimSpace(subcategory.Description)) > maxDescription {
		return invalid("description", fmt.Sprintf("must be at most %d characters", maxDescription))
	}
	if !subcategory.Status.Valid() {
		return invalid("status", "must be planned, active, blocked, done or archived")
	}
	if subcategory.Progress < 0 || subcategory.Progress > 100 {
		return invalid("progress", "must be between 0 and 100")
	}
	if len(strings.TrimSpace(subcategory.TargetOutcome)) > maxOutcome {
		return invalid("targetOutcome", fmt.Sprintf("must be at most %d characters", maxOutcome))
	}
	if err := validateLocalDate("targetDate", subcategory.TargetDate); err != nil {
		return err
	}
	if err := validateLinkList(subcategory.Links); err != nil {
		return err
	}
	if subcategory.SortOrder < 0 {
		return invalid("sortOrder", "must not be negative")
	}
	return nil
}

// ValidateWorkEntry checks attribution, timeframe and length invariants. The
// category and subcategory are the records the entry points at, so the
// role-dependent rules and the category/subcategory relationship can be
// enforced here. maxBlockMinutes rejects accidental always-on timers; pass 0 to
// disable it for manual and historical entries.
func ValidateWorkEntry(entry WorkEntry, category Category, subcategory *Subcategory, maxBlockMinutes int) error {
	if strings.TrimSpace(entry.CategoryID) == "" {
		return invalid("categoryId", "is required")
	}
	if entry.CategoryID != category.ID {
		return invalid("categoryId", "category does not exist")
	}
	if entry.UserID != "" && category.UserID != "" && entry.UserID != category.UserID {
		return invalid("categoryId", "category does not belong to this user")
	}

	description := strings.TrimSpace(entry.Description)
	if description == "" {
		return invalid("description", "is required")
	}
	if len(description) > maxDescription {
		return invalid("description", fmt.Sprintf("must be at most %d characters", maxDescription))
	}
	if len(strings.TrimSpace(entry.Outcome)) > maxOutcome {
		return invalid("outcome", fmt.Sprintf("must be at most %d characters", maxOutcome))
	}

	if entry.StartedAt.IsZero() {
		return invalid("startedAt", "is required")
	}
	if entry.EndedAt.IsZero() {
		return invalid("endedAt", "is required")
	}
	if entry.Minutes < 0 {
		return invalid("minutes", "must not be negative")
	}
	if entry.DurationMinutes() < 1 {
		return invalid("minutes", "entry must be at least one minute long")
	}
	if maxBlockMinutes > 0 && entry.DurationMinutes() > maxBlockMinutes {
		return invalid("minutes", fmt.Sprintf("entry exceeds the %d minute block limit", maxBlockMinutes))
	}
	if !entry.Source.Valid() {
		return invalid("source", "must be timer or manual")
	}

	if entry.SubcategoryID != "" {
		if subcategory == nil || subcategory.ID != entry.SubcategoryID || subcategory.CategoryID != entry.CategoryID {
			return invalid("subcategoryId", "subcategory must belong to its category")
		}
		if entry.UserID != "" && subcategory.UserID != "" && entry.UserID != subcategory.UserID {
			return invalid("subcategoryId", "subcategory does not belong to this user")
		}
	}

	if category.Role == CategoryRoleSupport && len(NormalizeList(entry.People)) == 0 {
		return invalid("person", "is required for support entries")
	}

	if len(entry.Tags) > maxListItems {
		return invalid("tags", fmt.Sprintf("must contain at most %d items", maxListItems))
	}
	if err := validateLinkList(entry.Links); err != nil {
		return err
	}

	return nil
}

// ValidateMilestone checks the fields required for a dated checkpoint. The due
// date is optional; when present it must be a canonical local calendar date.
func ValidateMilestone(milestone Milestone) error {
	title := strings.TrimSpace(milestone.Title)
	if title == "" {
		return invalid("title", "is required")
	}
	if len(title) > maxNameLength {
		return invalid("title", fmt.Sprintf("must be at most %d characters", maxNameLength))
	}
	if strings.TrimSpace(milestone.SubcategoryID) == "" {
		return invalid("subcategoryId", "is required")
	}
	if strings.TrimSpace(milestone.DueDate) == "" {
		return nil
	}
	return validateLocalDate("dueDate", milestone.DueDate)
}

// ValidateNote checks that a note has text and is attached to a day, a
// subcategory, or both.
func ValidateNote(note Note) error {
	text := strings.TrimSpace(note.Text)
	if text == "" {
		return invalid("text", "is required")
	}
	if len(text) > maxNoteLength {
		return invalid("text", fmt.Sprintf("must be at most %d characters", maxNoteLength))
	}
	if strings.TrimSpace(note.Date) == "" && strings.TrimSpace(note.SubcategoryID) == "" {
		return invalid("date", "a note needs a date, a subcategory or both")
	}
	return validateLocalDate("date", note.Date)
}

// ValidateCheckIn checks the kind, period and lifecycle invariants. A personal
// review never carries an audience and can never be final.
func ValidateCheckIn(checkIn CheckIn) error {
	if !checkIn.Kind.Valid() {
		return invalid("kind", "must be manager or personal")
	}
	if err := validateLocalDate("periodStart", checkIn.PeriodStart); err != nil {
		return err
	}
	if strings.TrimSpace(checkIn.PeriodStart) == "" {
		return invalid("periodStart", "is required")
	}
	if err := validateLocalDate("periodEnd", checkIn.PeriodEnd); err != nil {
		return err
	}
	if strings.TrimSpace(checkIn.PeriodEnd) == "" {
		return invalid("periodEnd", "is required")
	}
	if checkIn.PeriodEnd < checkIn.PeriodStart {
		return invalid("periodEnd", "must not be before periodStart")
	}
	if !checkIn.State.Valid() {
		return invalid("state", "must be draft, generated, edited or final")
	}
	if checkIn.State == CheckInStateFinal && checkIn.Kind != CheckInKindManager {
		return invalid("state", "only a manager check-in can be final")
	}
	if checkIn.Audience != "" && !checkIn.Audience.Valid() {
		return invalid("audience", "must be one_on_one or performance_review")
	}
	if checkIn.Kind == CheckInKindPersonal && checkIn.Audience != "" {
		return invalid("audience", "only applies to manager check-ins")
	}
	if checkIn.Totals.Minutes < 0 {
		return invalid("totals", "minutes must not be negative")
	}
	for _, minutes := range checkIn.Totals.ByCategory {
		if minutes < 0 {
			return invalid("totals", "minutes must not be negative")
		}
	}
	for _, minutes := range checkIn.Totals.BySubcategory {
		if minutes < 0 {
			return invalid("totals", "minutes must not be negative")
		}
	}
	for _, minutes := range checkIn.Totals.SupportByPerson {
		if minutes < 0 {
			return invalid("totals", "minutes must not be negative")
		}
	}
	if checkIn.Totals.SupportMinutes < 0 || checkIn.Totals.SupportInteractions < 0 {
		return invalid("totals", "support totals must not be negative")
	}
	return nil
}

// ValidateSettings checks the behaviour and appearance preferences. Enum
// values and numeric ranges are rejected with a field error.
func ValidateSettings(settings Settings) error {
	timezone := strings.TrimSpace(settings.Timezone)
	if timezone == "" {
		return invalid("timezone", "is required")
	}
	if _, err := time.LoadLocation(timezone); err != nil {
		return invalid("timezone", "must be an IANA timezone such as Europe/Amsterdam")
	}
	// 1 is Monday and 7 is Sunday, matching the ISO week number the UI uses.
	if settings.WeekStart < 1 || settings.WeekStart > 7 {
		return invalid("weekStart", "must be between 1 (Monday) and 7 (Sunday)")
	}
	if settings.DailyTargetMinutes < 0 || settings.DailyTargetMinutes > 24*60 {
		return invalid("dailyTargetMinutes", "must be between 0 and 1440")
	}
	if !settings.ReviewCadence.Valid() {
		return invalid("reviewCadence", "must be weekly, monthly or off")
	}
	if settings.LongTimerMinutes <= 0 {
		return invalid("longTimerMinutes", "must be greater than zero")
	}
	if settings.DefaultDurationMinutes <= 0 {
		return invalid("defaultDurationMinutes", "must be greater than zero")
	}
	if settings.BackupIntervalHours <= 0 {
		return invalid("backupIntervalHours", "must be greater than zero")
	}
	if settings.BackupRetention <= 0 {
		return invalid("backupRetention", "must be greater than zero")
	}
	if !settings.Theme.Valid() {
		return invalid("theme", "must be system, light, dark or high_contrast")
	}
	if !settings.Density.Valid() {
		return invalid("density", "must be comfortable or compact")
	}
	return validateLocalDate("journalStartDate", settings.JournalStartDate)
}

func validateLocalDate(field, value string) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parsed, err := time.Parse(DateLayout, value)
	if err != nil || parsed.Format(DateLayout) != value {
		return invalid(field, "must be a date in YYYY-MM-DD form")
	}
	return nil
}

func validateLinkList(links []Link) error {
	if len(links) > maxListItems {
		return invalid("links", fmt.Sprintf("must contain at most %d items", maxListItems))
	}
	for _, link := range links {
		if strings.TrimSpace(link.URL) == "" {
			return invalid("links", "each link needs a URL")
		}
	}
	return nil
}
