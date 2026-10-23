package store

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
)

// PeriodReport aggregates the user's work entries, support and note context
// for an inclusive range of local calendar dates. The local day and week
// boundaries come from the user's settings, so the report cannot disagree with
// how the same entries are grouped elsewhere in the product.
func (s *Store) PeriodReport(userID, fromDate, toDate string) (domain.PeriodReport, error) {
	var report domain.PeriodReport
	err := platform.Database.BoltDb.View(func(tx *bbolt.Tx) error {
		settings := domain.DefaultSettings(userID)
		_ = readTxObject(tx, userBucket(userID, settingsBucket), settingsKey, &settings)

		// The day index selects the entries in range; categories, subcategories
		// and notes are small enough to scan for their names and context.
		entries, err := entriesInDateRangeTx(tx, userID, fromDate, toDate)
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
		notes, err := readBucketTx[domain.Note](tx, userBucket(userID, notesBucket))
		if err != nil {
			return err
		}

		report, err = domain.BuildPeriodReport(
			fromDate,
			toDate,
			userLocation(tx, userID),
			settings.WeekStart,
			entries,
			categories,
			subcategories,
			notes,
		)
		return err
	})
	if err != nil {
		return domain.PeriodReport{}, err
	}
	return report, nil
}

// CurrentWeekRange returns the inclusive local dates of the week containing
// now, resolved in the user's configured timezone and week start. The service
// uses it so "this week" never depends on the device clock.
func (s *Store) CurrentWeekRange(userID string, now time.Time) (string, string, error) {
	var from, to string
	err := platform.Database.BoltDb.View(func(tx *bbolt.Tx) error {
		settings := domain.DefaultSettings(userID)
		_ = readTxObject(tx, userBucket(userID, settingsBucket), settingsKey, &settings)

		start := domain.StartOfWeek(now.In(userLocation(tx, userID)), settings.WeekStart)
		from = start.Format(domain.DateLayout)
		to = start.AddDate(0, 0, 6).Format(domain.DateLayout)
		return nil
	})
	if err != nil {
		return "", "", err
	}
	return from, to, nil
}

// entriesInDateRangeTx walks the day index between two inclusive local dates.
// Index keys are `<YYYY-MM-DD>/<entry id>`, so the range is one cursor seek
// plus sequential reads.
func entriesInDateRangeTx(tx *bbolt.Tx, userID, fromDate, toDate string) ([]domain.WorkEntry, error) {
	index := tx.Bucket([]byte(userBucket(userID, idxEntriesDayBucket)))
	entries := tx.Bucket([]byte(userBucket(userID, entriesBucket)))
	if index == nil || entries == nil {
		return nil, nil
	}

	result := make([]domain.WorkEntry, 0)
	seen := make(map[string]struct{})
	cursor := index.Cursor()
	for key, value := cursor.Seek([]byte(fromDate)); key != nil; key, value = cursor.Next() {
		slash := strings.IndexByte(string(key), '/')
		if slash < 0 {
			continue
		}
		day := string(key[:slash])
		if day > toDate {
			break
		}
		if day < fromDate {
			continue
		}

		id := string(value)
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}

		raw := entries.Get([]byte(id))
		if raw == nil {
			continue
		}
		var entry domain.WorkEntry
		if err := json.Unmarshal(raw, &entry); err != nil {
			return nil, fmt.Errorf("decode entry %s: %w", id, err)
		}
		result = append(result, entry)
	}
	return result, nil
}

// readBucketTx decodes every value in a bucket inside the caller's read
// transaction. A missing bucket is an empty result, matching readAllRaw.
func readBucketTx[T any](tx *bbolt.Tx, bucket string) ([]T, error) {
	target := tx.Bucket([]byte(bucket))
	if target == nil {
		return nil, nil
	}

	values := make([]T, 0)
	cursor := target.Cursor()
	for key, raw := cursor.First(); key != nil; key, raw = cursor.Next() {
		var value T
		if err := json.Unmarshal(raw, &value); err != nil {
			return nil, fmt.Errorf("decode %s/%s: %w", bucket, key, err)
		}
		values = append(values, value)
	}
	return values, nil
}
