package domain

import (
	"fmt"
	"net/mail"
	"strings"
	"time"
)

const (
	minPasswordLength = 10
	maxNameLength     = 120
	maxDescription    = 500
	maxOutcome        = 1000
	maxListItems      = 20
)

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

// ValidateInitiative checks the initiative invariants.
func ValidateInitiative(initiative Initiative) error {
	if strings.TrimSpace(initiative.Name) == "" {
		return invalid("name", "is required")
	}
	if len(strings.TrimSpace(initiative.Name)) > maxNameLength {
		return invalid("name", fmt.Sprintf("must be at most %d characters", maxNameLength))
	}
	if !initiative.Status.Valid() {
		return invalid("status", "must be planned, active, blocked, done or archived")
	}
	if initiative.Progress < 0 || initiative.Progress > 100 {
		return invalid("progress", "must be between 0 and 100")
	}
	if len(initiative.Links) > maxListItems {
		return invalid("links", fmt.Sprintf("must contain at most %d items", maxListItems))
	}
	return nil
}

// Valid reports whether the status is a known lifecycle state.
func (s InitiativeStatus) Valid() bool {
	switch s {
	case InitiativePlanned, InitiativeActive, InitiativeBlocked, InitiativeDone, InitiativeArchived:
		return true
	default:
		return false
	}
}

// Valid reports whether the entry kind is a known attribution.
func (k EntryKind) Valid() bool {
	switch k {
	case EntryInitiative, EntrySupport, EntryOther:
		return true
	default:
		return false
	}
}

// Valid reports whether the support mode is known.
func (m SupportMode) Valid() bool {
	switch m {
	case SupportReview, SupportPair, SupportUnblock, SupportMentor, SupportIncident, SupportOther:
		return true
	default:
		return false
	}
}

// ValidateEntry checks attribution, timeframe and length invariants.
// maxBlockMinutes rejects accidental always-on timers; pass 0 to disable.
func ValidateEntry(entry Entry, maxBlockMinutes int) error {
	if !entry.Kind.Valid() {
		return invalid("kind", "must be initiative, support or other")
	}
	if strings.TrimSpace(entry.Description) == "" {
		return invalid("description", "is required")
	}
	if len(strings.TrimSpace(entry.Description)) > maxDescription {
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

	switch entry.Kind {
	case EntryInitiative:
		if strings.TrimSpace(entry.InitiativeID) == "" {
			return invalid("initiativeId", "is required for initiative entries")
		}
		if entry.Support != nil {
			return invalid("support", "must be empty for initiative entries")
		}
	case EntrySupport:
		if entry.InitiativeID != "" {
			return invalid("initiativeId", "must be empty for support entries")
		}
		if entry.Support == nil {
			return invalid("support", "is required for support entries")
		}
		if strings.TrimSpace(entry.Support.Person) == "" {
			return invalid("support.person", "is required")
		}
		if !entry.Support.Mode.Valid() {
			return invalid("support.mode", "must be review, pair, unblock, mentor, incident or other")
		}
	case EntryOther:
		if entry.InitiativeID != "" {
			return invalid("initiativeId", "must be empty for other entries")
		}
		if entry.Support != nil {
			return invalid("support", "must be empty for other entries")
		}
	}

	if len(entry.Tags) > maxListItems {
		return invalid("tags", fmt.Sprintf("must contain at most %d items", maxListItems))
	}
	if len(entry.Links) > maxListItems {
		return invalid("links", fmt.Sprintf("must contain at most %d items", maxListItems))
	}

	return nil
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
