package domain_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestValidateRegistration(t *testing.T) {
	tests := []struct {
		name        string
		email       string
		password    string
		displayName string
		wantField   string
	}{
		{name: "valid", email: "dev@example.com", password: "longenough1", displayName: "Dev"},
		{name: "missing email", password: "longenough1", wantField: "email"},
		{name: "invalid email", email: "not-an-email", password: "longenough1", wantField: "email"},
		{name: "short password", email: "dev@example.com", password: "short", wantField: "password"},
		{name: "long display name", email: "dev@example.com", password: "longenough1", displayName: strings.Repeat("a", 200), wantField: "displayName"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			err := domain.ValidateRegistration(test.email, test.password, test.displayName)
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}

			var validation domain.ValidationError
			if !errors.As(err, &validation) {
				t.Fatalf("expected ValidationError, got %v", err)
			}
			if validation.Field != test.wantField {
				t.Fatalf("field = %q, want %q", validation.Field, test.wantField)
			}
		})
	}
}

func validEntry() domain.Entry {
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	return domain.Entry{
		Kind:         domain.EntryInitiative,
		InitiativeID: "initiative-1",
		Description:  "Backfill script",
		StartedAt:    start,
		EndedAt:      start.Add(45 * time.Minute),
		Minutes:      45,
	}
}

func TestValidateEntry(t *testing.T) {
	tests := []struct {
		name      string
		mutate    func(*domain.Entry)
		wantField string
	}{
		{name: "valid initiative entry"},
		{name: "invalid kind", mutate: func(e *domain.Entry) { e.Kind = "meeting" }, wantField: "kind"},
		{name: "missing description", mutate: func(e *domain.Entry) { e.Description = " " }, wantField: "description"},
		{name: "missing initiative", mutate: func(e *domain.Entry) { e.InitiativeID = "" }, wantField: "initiativeId"},
		{name: "initiative with support", mutate: func(e *domain.Entry) { e.Support = &domain.SupportDetail{Person: "Priya", Mode: domain.SupportReview} }, wantField: "support"},
		{name: "zero duration", mutate: func(e *domain.Entry) { e.Minutes = 0; e.EndedAt = e.StartedAt }, wantField: "minutes"},
		{
			name: "support without person",
			mutate: func(e *domain.Entry) {
				e.Kind = domain.EntrySupport
				e.InitiativeID = ""
				e.Support = &domain.SupportDetail{Mode: domain.SupportReview}
			},
			wantField: "support.person",
		},
		{
			name: "support with invalid mode",
			mutate: func(e *domain.Entry) {
				e.Kind = domain.EntrySupport
				e.InitiativeID = ""
				e.Support = &domain.SupportDetail{Person: "Priya", Mode: "chat"}
			},
			wantField: "support.mode",
		},
		{
			name: "other with initiative",
			mutate: func(e *domain.Entry) {
				e.Kind = domain.EntryOther
			},
			wantField: "initiativeId",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			entry := validEntry()
			if test.mutate != nil {
				test.mutate(&entry)
			}

			err := domain.ValidateEntry(entry, 240)
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}

			var validation domain.ValidationError
			if !errors.As(err, &validation) {
				t.Fatalf("expected ValidationError, got %v", err)
			}
			if validation.Field != test.wantField {
				t.Fatalf("field = %q, want %q", validation.Field, test.wantField)
			}
		})
	}
}

func TestValidateEntryBlockLimit(t *testing.T) {
	entry := validEntry()
	entry.Minutes = 300

	err := domain.ValidateEntry(entry, 240)
	var validation domain.ValidationError
	if !errors.As(err, &validation) {
		t.Fatalf("expected ValidationError, got %v", err)
	}
	if validation.Field != "minutes" {
		t.Fatalf("field = %q, want minutes", validation.Field)
	}
}

func TestActiveTimerElapsed(t *testing.T) {
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)

	timer := domain.ActiveTimer{StartedAt: start, SegmentStartedAt: start}
	if got := timer.Elapsed(start.Add(30 * time.Minute)); got != 30*time.Minute {
		t.Fatalf("running elapsed = %v, want 30m", got)
	}

	pausedAt := start.Add(30 * time.Minute)
	timer.AccumulatedSeconds = 1800
	timer.PausedAt = &pausedAt
	timer.SegmentStartedAt = pausedAt
	if got := timer.Elapsed(start.Add(90 * time.Minute)); got != 30*time.Minute {
		t.Fatalf("paused elapsed = %v, want 30m", got)
	}

	timer.PausedAt = nil
	timer.SegmentStartedAt = start.Add(90 * time.Minute)
	if got := timer.Elapsed(start.Add(105 * time.Minute)); got != 45*time.Minute {
		t.Fatalf("resumed elapsed = %v, want 45m", got)
	}
}
