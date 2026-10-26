package domain_test

import (
	"testing"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestCheckInTotalsFromReportKeepsSupportTotalsAuthoritative(t *testing.T) {
	// Per-person rows credit each name the full entry minutes, so they add up
	// to 120 here. The snapshot's totals must stay at the entry total of 75.
	report := domain.PeriodReport{
		TotalMinutes:        75,
		SupportMinutes:      75,
		SupportInteractions: 2,
		SupportPeople: []domain.SupportPersonTotal{
			{Person: "Alex", Minutes: 75, Interactions: 2},
			{Person: "Sam", Minutes: 45, Interactions: 1},
		},
	}

	totals := domain.CheckInTotalsFromReport(report)

	if totals.SupportMinutes != 75 || totals.SupportInteractions != 2 {
		t.Fatalf("support totals = %dm/%d interactions, want the authoritative 75m across 2 entries",
			totals.SupportMinutes, totals.SupportInteractions)
	}
	if got := totals.SupportByPerson["Alex"] + totals.SupportByPerson["Sam"]; got != 120 {
		t.Fatalf("support by person sums to %dm, want full credit per person (120m)", got)
	}
}
