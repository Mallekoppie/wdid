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
