package demo

import (
	"fmt"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// checkInCreateHour is the UTC hour of a seeded check-in's CreatedAt. It makes
// the timestamp readable while keeping it strictly anchor-derived.
const checkInCreateHour = 18

// CheckInsFixture is the declarative check-in dataset. Totals are deliberately
// absent: the seeder snapshots the authoritative period report for each period.
type CheckInsFixture struct {
	CheckIns []CheckInFixture `json:"checkIns"`
}

// CheckInFixture is one manager check-in or personal review. Offsets are days
// before the anchor, so the dataset moves with --anchor; PeriodStartOffset is
// the earlier (larger) offset. CreatedDaysBeforeAnchor keeps the listing order
// stable because check-ins are sorted by CreatedAt.
type CheckInFixture struct {
	Key                     string              `json:"key"`
	Kind                    domain.CheckInKind  `json:"kind"`
	State                   domain.CheckInState `json:"state"`
	Audience                domain.Audience     `json:"audience,omitempty"`
	PeriodStartOffset       int                 `json:"periodStartOffset"`
	PeriodEndOffset         int                 `json:"periodEndOffset"`
	CreatedDaysBeforeAnchor int                 `json:"createdDaysBeforeAnchor"`
	FocusNotes              string              `json:"focusNotes,omitempty"`
	SummaryMarkdown         string              `json:"summaryMarkdown,omitempty"`
}

// validateCheckIns rejects check-ins that cannot produce valid, deterministically
// ordered rows. Period and creation offsets stay inside the 14-day window the
// work entries cover, so every seeded snapshot is based on real work.
func (f Fixture) validateCheckIns() error {
	keys := make(map[string]struct{}, len(f.CheckIns.CheckIns))
	createdOffsets := make(map[int]struct{}, len(f.CheckIns.CheckIns))
	for i, checkIn := range f.CheckIns.CheckIns {
		key := strings.TrimSpace(checkIn.Key)
		if key == "" {
			return fmt.Errorf("fixture checkIns[%d]: key is required", i)
		}
		if _, duplicate := keys[key]; duplicate {
			return fmt.Errorf("fixture checkIns[%d]: key %q is duplicated", i, key)
		}
		keys[key] = struct{}{}

		if !checkIn.Kind.Valid() {
			return fmt.Errorf("fixture checkIn %q: invalid kind %q", key, checkIn.Kind)
		}
		if !checkIn.State.Valid() {
			return fmt.Errorf("fixture checkIn %q: invalid state %q", key, checkIn.State)
		}
		if checkIn.State == domain.CheckInStateFinal && checkIn.Kind != domain.CheckInKindManager {
			return fmt.Errorf("fixture checkIn %q: only a manager check-in can be final", key)
		}
		if checkIn.Audience != "" && !checkIn.Audience.Valid() {
			return fmt.Errorf("fixture checkIn %q: invalid audience %q", key, checkIn.Audience)
		}
		if checkIn.Kind == domain.CheckInKindPersonal && checkIn.Audience != "" {
			return fmt.Errorf("fixture checkIn %q: audience only applies to manager check-ins", key)
		}

		if checkIn.PeriodStartOffset < 0 || checkIn.PeriodStartOffset >= fixtureWindowDays {
			return fmt.Errorf("fixture checkIn %q: periodStartOffset must be between 0 and %d", key, fixtureWindowDays-1)
		}
		if checkIn.PeriodEndOffset < 0 || checkIn.PeriodEndOffset >= fixtureWindowDays {
			return fmt.Errorf("fixture checkIn %q: periodEndOffset must be between 0 and %d", key, fixtureWindowDays-1)
		}
		if checkIn.PeriodStartOffset < checkIn.PeriodEndOffset {
			return fmt.Errorf("fixture checkIn %q: periodStartOffset must not be smaller than periodEndOffset", key)
		}
		if checkIn.CreatedDaysBeforeAnchor < 0 || checkIn.CreatedDaysBeforeAnchor >= fixtureWindowDays {
			return fmt.Errorf("fixture checkIn %q: createdDaysBeforeAnchor must be between 0 and %d", key, fixtureWindowDays-1)
		}
		if _, duplicate := createdOffsets[checkIn.CreatedDaysBeforeAnchor]; duplicate {
			return fmt.Errorf("fixture checkIn %q: createdDaysBeforeAnchor %d is duplicated; ordering would be unstable",
				key, checkIn.CreatedDaysBeforeAnchor)
		}
		createdOffsets[checkIn.CreatedDaysBeforeAnchor] = struct{}{}
	}
	return nil
}

// seedCheckIns writes the fixture's manager check-ins and personal reviews. It
// runs after the work entries so each stored record can snapshot the
// authoritative report for its period before the first save; a final manager
// check-in is read-only immediately afterwards.
func seedCheckIns(
	database *store.Store,
	scenario, userID string,
	fixture Fixture,
	anchor time.Time,
) (int, error) {
	for _, checkIn := range fixture.CheckIns.CheckIns {
		periodStart := anchor.AddDate(0, 0, -checkIn.PeriodStartOffset)
		periodEnd := anchor.AddDate(0, 0, -checkIn.PeriodEndOffset)
		createdAt := anchor.AddDate(0, 0, -checkIn.CreatedDaysBeforeAnchor).
			Add(checkInCreateHour * time.Hour)

		// A final manager check-in is immutable after its first save, so the
		// snapshot must be taken from the authoritative report right here.
		report, err := database.PeriodReport(
			userID,
			periodStart.Format(domain.DateLayout),
			periodEnd.Format(domain.DateLayout),
		)
		if err != nil {
			return 0, fmt.Errorf("read report for demo check-in %q: %w", checkIn.Key, err)
		}

		record := domain.CheckIn{
			ID:              stableID(scenario, "checkin", strings.TrimSpace(checkIn.Key)),
			UserID:          userID,
			Kind:            checkIn.Kind,
			PeriodStart:     periodStart.Format(domain.DateLayout),
			PeriodEnd:       periodEnd.Format(domain.DateLayout),
			State:           checkIn.State,
			Audience:        checkIn.Audience,
			FocusNotes:      strings.TrimSpace(checkIn.FocusNotes),
			SummaryMarkdown: strings.TrimSpace(checkIn.SummaryMarkdown),
			Totals:          domain.CheckInTotalsFromReport(report),
			CreatedAt:       createdAt,
			UpdatedAt:       createdAt,
		}
		if err := database.SaveCheckIn(record); err != nil {
			return 0, fmt.Errorf("save demo check-in %q: %w", checkIn.Key, err)
		}
	}
	return len(fixture.CheckIns.CheckIns), nil
}
