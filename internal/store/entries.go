package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
)

const (
	idxEntriesDayBucket         = "idx_entries_day"
	idxEntriesCategoryBucket    = "idx_entries_category"
	idxEntriesSubcategoryBucket = "idx_entries_subcategory"
	idxEntriesPersonBucket      = "idx_entries_person"
)

// WorkEntryFilter narrows a work-entry listing. LocalDate and the identifiers
// are served by the per-user entry indexes.
type WorkEntryFilter struct {
	From          time.Time
	To            time.Time
	LocalDate     string
	CategoryID    string
	SubcategoryID string
	Person        string
	Query         string
	Limit         int
}

// SaveWorkEntry creates or replaces a work entry. The entry's category and
// subcategory must exist for the same user, and the support-person rule is
// enforced before anything is written. LocalDate is derived from the user's
// timezone at write time.
func (s *Store) SaveWorkEntry(entry domain.WorkEntry) error {
	entry.Normalize()
	if entry.Minutes == 0 && entry.EndedAt.After(entry.StartedAt) {
		entry.Minutes = int(entry.EndedAt.Sub(entry.StartedAt).Minutes())
	}

	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		var category domain.Category
		err := readTxObject(tx, userBucket(entry.UserID, categoriesBucket), entry.CategoryID, &category)
		if errors.Is(err, ErrNotFound) {
			return ErrCategoryNotFound
		}
		if err != nil {
			return err
		}

		var subcategory *domain.Subcategory
		if entry.SubcategoryID != "" {
			var stored domain.Subcategory
			err := readTxObject(tx, userBucket(entry.UserID, subcategoriesBucket), entry.SubcategoryID, &stored)
			if errors.Is(err, ErrNotFound) {
				return ErrSubcategoryNotFound
			}
			if err != nil {
				return err
			}
			subcategory = &stored
		}

		entry.LocalDate = entryLocalDate(tx, entry.UserID, entry.StartedAt)
		if err := domain.ValidateWorkEntry(entry, category, subcategory, 0); err != nil {
			return err
		}

		bucket := userBucket(entry.UserID, entriesBucket)
		var previous domain.WorkEntry
		err = readTxObject(tx, bucket, entry.ID, &previous)
		switch {
		case err == nil:
			if err := removeEntryIndexes(tx, previous); err != nil {
				return err
			}
		case !errors.Is(err, ErrNotFound):
			return err
		}

		if err := putJSON(tx, bucket, entry.ID, entry); err != nil {
			return err
		}
		return addEntryIndexes(tx, entry)
	})
}

// LocalDate returns the user's calendar date for an instant in the timezone
// configured in their settings.
func (s *Store) LocalDate(userID string, instant time.Time) (string, error) {
	var date string
	err := platform.Database.BoltDb.View(func(tx *bbolt.Tx) error {
		date = entryLocalDate(tx, userID, instant)
		return nil
	})
	if err != nil {
		return "", err
	}
	return date, nil
}

// WorkEntry returns one entry owned by the user.
func (s *Store) WorkEntry(userID, id string) (domain.WorkEntry, error) {
	var entry domain.WorkEntry
	if err := readObject(userBucket(userID, entriesBucket), id, &entry); err != nil {
		return domain.WorkEntry{}, err
	}
	return entry, nil
}

// WorkEntries returns the user's entries matching the filter, newest first.
func (s *Store) WorkEntries(userID string, filter WorkEntryFilter) ([]domain.WorkEntry, error) {
	candidates, err := entryCandidates(userID, filter)
	if err != nil {
		return nil, err
	}

	raw, err := readAllRaw(userBucket(userID, entriesBucket))
	if err != nil {
		return nil, err
	}

	query := strings.ToLower(strings.TrimSpace(filter.Query))
	entries := make([]domain.WorkEntry, 0, len(raw))
	for id, value := range raw {
		if candidates != nil {
			if _, ok := candidates[id]; !ok {
				continue
			}
		}

		var entry domain.WorkEntry
		if err := json.Unmarshal([]byte(value), &entry); err != nil {
			return nil, fmt.Errorf("decode entry: %w", err)
		}
		if !workEntryMatches(entry, filter, query) {
			continue
		}
		entries = append(entries, entry)
	}

	sort.Slice(entries, func(i, j int) bool {
		if entries[i].StartedAt.Equal(entries[j].StartedAt) {
			return entries[i].CreatedAt.After(entries[j].CreatedAt)
		}
		return entries[i].StartedAt.After(entries[j].StartedAt)
	})

	if filter.Limit > 0 && len(entries) > filter.Limit {
		entries = entries[:filter.Limit]
	}

	return entries, nil
}

// DeleteWorkEntry removes one entry and its index keys.
func (s *Store) DeleteWorkEntry(userID, id string) error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		bucket := userBucket(userID, entriesBucket)
		var entry domain.WorkEntry
		if err := readTxObject(tx, bucket, id, &entry); err != nil {
			return err
		}
		if err := removeEntryIndexes(tx, entry); err != nil {
			return err
		}
		return tx.Bucket([]byte(bucket)).Delete([]byte(id))
	})
}

// entryCandidates returns the IDs selected by the most specific index, or nil
// when the filter has no indexed field and the caller should scan the bucket.
func entryCandidates(userID string, filter WorkEntryFilter) (map[string]struct{}, error) {
	var bucket, prefix string
	switch {
	case filter.LocalDate != "":
		bucket, prefix = idxEntriesDayBucket, filter.LocalDate
	case filter.CategoryID != "":
		bucket, prefix = idxEntriesCategoryBucket, filter.CategoryID
	case filter.SubcategoryID != "":
		bucket, prefix = idxEntriesSubcategoryBucket, filter.SubcategoryID
	case filter.Person != "":
		bucket, prefix = idxEntriesPersonBucket, strings.ToLower(strings.TrimSpace(filter.Person))
	default:
		return nil, nil
	}

	raw, err := readAllRaw(userBucket(userID, bucket))
	if err != nil {
		return nil, err
	}

	keyPrefix := prefix + "/"
	candidates := make(map[string]struct{}, len(raw))
	for key, id := range raw {
		if strings.HasPrefix(key, keyPrefix) {
			candidates[id] = struct{}{}
		}
	}
	return candidates, nil
}

func workEntryMatches(entry domain.WorkEntry, filter WorkEntryFilter, query string) bool {
	if filter.LocalDate != "" && entry.LocalDate != filter.LocalDate {
		return false
	}
	if filter.CategoryID != "" && entry.CategoryID != filter.CategoryID {
		return false
	}
	if filter.SubcategoryID != "" && entry.SubcategoryID != filter.SubcategoryID {
		return false
	}
	if filter.Person != "" && !strings.EqualFold(entry.Person, strings.TrimSpace(filter.Person)) {
		return false
	}
	if !filter.From.IsZero() && entry.StartedAt.Before(filter.From) {
		return false
	}
	if !filter.To.IsZero() && !entry.StartedAt.Before(filter.To) {
		return false
	}
	if query != "" {
		haystack := strings.ToLower(entry.Description + " " + entry.Outcome)
		if !strings.Contains(haystack, query) {
			return false
		}
	}
	return true
}

// entryIndexValues maps each populated index to the values it keys the entry
// by. Index writes and deletes share it so the shapes cannot drift apart.
func entryIndexValues(entry domain.WorkEntry) map[string][]string {
	indexes := map[string][]string{
		idxEntriesCategoryBucket: {entry.CategoryID},
	}
	if entry.LocalDate != "" {
		indexes[idxEntriesDayBucket] = []string{entry.LocalDate}
	}
	if entry.SubcategoryID != "" {
		indexes[idxEntriesSubcategoryBucket] = []string{entry.SubcategoryID}
	}
	if entry.Person != "" {
		indexes[idxEntriesPersonBucket] = []string{strings.ToLower(entry.Person)}
	}
	return indexes
}

func addEntryIndexes(tx *bbolt.Tx, entry domain.WorkEntry) error {
	for name, values := range entryIndexValues(entry) {
		bucket, err := tx.CreateBucketIfNotExists([]byte(userBucket(entry.UserID, name)))
		if err != nil {
			return fmt.Errorf("create index bucket %s: %w", name, err)
		}
		for _, value := range values {
			key := value + "/" + entry.ID
			if err := bucket.Put([]byte(key), []byte(entry.ID)); err != nil {
				return fmt.Errorf("write index %s/%s: %w", name, key, err)
			}
		}
	}
	return nil
}

func removeEntryIndexes(tx *bbolt.Tx, entry domain.WorkEntry) error {
	for name, values := range entryIndexValues(entry) {
		bucket := tx.Bucket([]byte(userBucket(entry.UserID, name)))
		if bucket == nil {
			continue
		}
		for _, value := range values {
			key := value + "/" + entry.ID
			if err := bucket.Delete([]byte(key)); err != nil {
				return fmt.Errorf("delete index %s/%s: %w", name, key, err)
			}
		}
	}
	return nil
}

// entryLocalDate derives the grouping day from an instant in the user's
// configured timezone. Missing settings fall back to UTC.
func entryLocalDate(tx *bbolt.Tx, userID string, startedAt time.Time) string {
	settings := domain.DefaultSettings(userID)
	_ = readTxObject(tx, userBucket(userID, settingsBucket), settingsKey, &settings)

	location, err := time.LoadLocation(settings.Timezone)
	if err != nil {
		location = time.UTC
	}
	return startedAt.In(location).Format(domain.DateLayout)
}
