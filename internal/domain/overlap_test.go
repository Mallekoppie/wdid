package domain_test

import (
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func overlapEntry(id string, start time.Time, minutes int) domain.WorkEntry {
	return domain.WorkEntry{
		ID:        id,
		StartedAt: start,
		EndedAt:   start.Add(time.Duration(minutes) * time.Minute),
		Minutes:   minutes,
	}
}

func TestOverlappingEntryIDsFlagsBothSidesOfAnIntersection(t *testing.T) {
	day := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC)
	entries := []domain.WorkEntry{
		overlapEntry("a", day, 60),                     // 09:00–10:00
		overlapEntry("b", day.Add(30*time.Minute), 60), // 09:30–10:30
		overlapEntry("c", day.Add(90*time.Minute), 30), // 10:30–11:00, adjacent to b
	}

	got := domain.OverlappingEntryIDs(entries)
	if len(got) != 2 || got[0] != "a" || got[1] != "b" {
		t.Fatalf("overlapping ids = %v, want [a b]", got)
	}
}

func TestOverlappingEntryIDsIgnoresAdjacentAndEmptyEntries(t *testing.T) {
	day := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC)
	entries := []domain.WorkEntry{
		overlapEntry("first", day, 30),                      // 09:00–09:30
		overlapEntry("second", day.Add(30*time.Minute), 30), // 09:30–10:00
		{ID: "empty", StartedAt: day, EndedAt: day},
	}

	if got := domain.OverlappingEntryIDs(entries); len(got) != 0 {
		t.Fatalf("overlapping ids = %v, want none", got)
	}
}
