package store

import (
	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
)

// ExportSnapshot is one consistent read of everything an export renders: the
// authoritative report, the raw rows behind it, the taxonomy, the milestones,
// the check-ins and the settings. Reading it inside one BoltDB View means an
// export can never combine a report from one instant with rows from another.
type ExportSnapshot struct {
	Report        domain.PeriodReport
	Entries       []domain.WorkEntry
	Categories    []domain.Category
	Subcategories []domain.Subcategory
	Milestones    []domain.Milestone
	CheckIns      []domain.CheckIn
	Settings      domain.Settings
	// ScopedCheckIn is the check-in the export belongs to, when checkInID was
	// supplied. The report's dates then come from that record, so the bundle
	// cannot disagree with the artifact it belongs to.
	ScopedCheckIn *domain.CheckIn
}

// ExportSnapshot gathers the export input inside a single read transaction.
// When checkInID is non-empty its stored period overrides fromDate/toDate, and
// the check-in itself is returned from the same snapshot.
func (s *Store) ExportSnapshot(userID, fromDate, toDate, checkInID string) (ExportSnapshot, error) {
	var snapshot ExportSnapshot

	err := platform.Database.BoltDb.View(func(tx *bbolt.Tx) error {
		var scoped *domain.CheckIn
		if checkInID != "" {
			var checkIn domain.CheckIn
			if err := readTxObject(tx, userBucket(userID, checkInsBucket), checkInID, &checkIn); err != nil {
				return err
			}
			scoped = &checkIn
			fromDate, toDate = checkIn.PeriodStart, checkIn.PeriodEnd
		}

		settings := domain.DefaultSettings(userID)
		_ = readTxObject(tx, userBucket(userID, settingsBucket), settingsKey, &settings)

		report, err := periodReportTx(tx, userID, fromDate, toDate)
		if err != nil {
			return err
		}
		entries, err := entriesInDateRangeTx(tx, userID, report.FromDate, report.ToDate)
		if err != nil {
			return err
		}
		categories, err := readBucketTx[domain.Category](tx, userBucket(userID, categoriesBucket))
		if err != nil {
			return err
		}
		subcategories, err := readBucketTx[domain.Subcategory](tx, userBucket(userID, subcategoriesBucket))
		if err != nil {
			return err
		}
		milestones, err := readBucketTx[domain.Milestone](tx, userBucket(userID, milestonesBucket))
		if err != nil {
			return err
		}
		checkIns, err := readBucketTx[domain.CheckIn](tx, userBucket(userID, checkInsBucket))
		if err != nil {
			return err
		}

		// Apply the same ordering the individual listing methods use, so an
		// export built from this snapshot is byte-for-byte the bundle it built
		// before the reads were combined.
		sortCategories(categories)
		sortSubcategories(subcategories)
		sortMilestones(milestones)
		sortCheckIns(checkIns)

		snapshot = ExportSnapshot{
			Report:        report,
			Entries:       entries,
			Categories:    categories,
			Subcategories: subcategories,
			Milestones:    milestones,
			CheckIns:      checkIns,
			Settings:      settings,
			ScopedCheckIn: scoped,
		}
		return nil
	})
	if err != nil {
		return ExportSnapshot{}, err
	}
	return snapshot, nil
}
