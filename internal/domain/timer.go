package domain

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// TimerStopAction is what to do with a timer when it is stopped.
type TimerStopAction string

const (
	// TimerStopSave stores the whole elapsed time. It is the default, but a
	// timer that runs past the block limit needs an explicit keep, trim or
	// discard choice instead.
	TimerStopSave TimerStopAction = "save"
	// TimerStopKeep stores the whole elapsed time even above the block limit.
	TimerStopKeep TimerStopAction = "keep"
	// TimerStopTrim stores only the block limit.
	TimerStopTrim TimerStopAction = "trim"
	// TimerStopDiscard removes the timer without creating an entry.
	TimerStopDiscard TimerStopAction = "discard"
)

// Valid reports whether the stop action is known.
func (a TimerStopAction) Valid() bool {
	switch a {
	case TimerStopSave, TimerStopKeep, TimerStopTrim, TimerStopDiscard:
		return true
	default:
		return false
	}
}

// TimerConflictReason identifies a stop that needs a decision from the caller.
type TimerConflictReason string

const (
	// TimerConflictTooShort means a stop under one minute that is not a discard.
	TimerConflictTooShort TimerConflictReason = "timer_too_short"
	// TimerConflictBlockLimit means the timer exceeded the block limit and the
	// caller must choose keep, trim or discard.
	TimerConflictBlockLimit TimerConflictReason = "timer_block_limit"
)

// TimerConflictError is returned when a stop cannot proceed without an
// explicit choice. The RPC layer carries the reason to the client so the UI
// can offer the decision instead of guessing.
type TimerConflictError struct {
	Reason            TimerConflictReason
	ElapsedMinutes    int
	BlockLimitMinutes int
}

func (e TimerConflictError) Error() string {
	switch e.Reason {
	case TimerConflictBlockLimit:
		return fmt.Sprintf("%s: %d minutes exceeds the %d minute block limit", e.Reason, e.ElapsedMinutes, e.BlockLimitMinutes)
	default:
		return fmt.Sprintf("%s: the timer has run for less than a minute", e.Reason)
	}
}

// ActiveTimer is the single running timer for a user.
type ActiveTimer struct {
	UserID             string     `json:"userId"`
	CategoryID         string     `json:"categoryId"`
	SubcategoryID      string     `json:"subcategoryId,omitempty"`
	Description        string     `json:"description,omitempty"`
	People             []string   `json:"people,omitempty"`
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

// Normalize trims timer input into its canonical form and stores timestamps in
// UTC.
func (t *ActiveTimer) Normalize() {
	t.CategoryID = strings.TrimSpace(t.CategoryID)
	t.SubcategoryID = strings.TrimSpace(t.SubcategoryID)
	t.Description = strings.TrimSpace(t.Description)
	t.People = NormalizeList(t.People)
	t.StartedAt = utc(t.StartedAt)
	t.SegmentStartedAt = utc(t.SegmentStartedAt)
	if t.PausedAt != nil {
		pausedAt := utc(*t.PausedAt)
		t.PausedAt = &pausedAt
	}
}

// UnmarshalJSON accepts the legacy single "person" field so a timer written
// before multi-person support loads as a one-name list.
func (t *ActiveTimer) UnmarshalJSON(data []byte) error {
	type activeTimer ActiveTimer
	aux := struct {
		*activeTimer
		LegacyPerson string `json:"person"`
	}{activeTimer: (*activeTimer)(t)}

	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}
	if len(t.People) == 0 && strings.TrimSpace(aux.LegacyPerson) != "" {
		t.People = NormalizeList([]string{aux.LegacyPerson})
	}
	return nil
}
