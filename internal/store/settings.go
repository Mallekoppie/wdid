package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
)

// Settings returns the user's behaviour and appearance settings. A missing
// record means the account predates settings seeding; callers get ErrNotFound.
func (s *Store) Settings(userID string) (domain.Settings, error) {
	var settings domain.Settings
	if err := readObject(userBucket(userID, settingsBucket), settingsKey, &settings); err != nil {
		return domain.Settings{}, err
	}
	return settings, nil
}

// SaveSettings creates or replaces the user's settings record.
func (s *Store) SaveSettings(settings domain.Settings) error {
	settings.Normalize()
	if err := domain.ValidateSettings(settings); err != nil {
		return err
	}
	return saveObject(userBucket(settings.UserID, settingsBucket), settingsKey, settings)
}

// EnsureSupportPeople materialises the user's settings record and seeds the
// support-person roster from that account's existing support-role entries the
// first time it runs. The read-check-write happens in one transaction, so the
// seed runs exactly once even under concurrent loads. The internal seeded
// marker means a deliberately emptied roster is never re-seeded.
func (s *Store) EnsureSupportPeople(userID string) (domain.Settings, error) {
	settings := domain.DefaultSettings(userID)

	err := platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		bucket := userBucket(userID, settingsBucket)
		err := readTxObject(tx, bucket, settingsKey, &settings)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return err
		}
		if settings.SupportPeopleSeeded {
			return nil
		}

		people, err := supportPeopleFromEntriesTx(tx, userID)
		if err != nil {
			return err
		}
		settings.SupportPeople = domain.NormalizeList(append(settings.SupportPeople, people...))
		settings.SupportPeopleSeeded = true
		settings.Normalize()
		return putJSON(tx, bucket, settingsKey, settings)
	})
	if err != nil {
		return domain.Settings{}, err
	}
	return settings, nil
}

// supportPeopleFromEntriesTx collects the Person values on support-role
// entries, in bucket (UUIDv7) order. It returns the raw spellings; the caller
// canonicalises them so the first spelling and the order are preserved.
func supportPeopleFromEntriesTx(tx *bbolt.Tx, userID string) ([]string, error) {
	roles := make(map[string]domain.CategoryRole)
	if categories := tx.Bucket([]byte(userBucket(userID, categoriesBucket))); categories != nil {
		cursor := categories.Cursor()
		for key, value := cursor.First(); key != nil; key, value = cursor.Next() {
			var category domain.Category
			if err := json.Unmarshal(value, &category); err != nil {
				return nil, fmt.Errorf("decode category: %w", err)
			}
			roles[category.ID] = category.Role
		}
	}

	entries := tx.Bucket([]byte(userBucket(userID, entriesBucket)))
	if entries == nil {
		return nil, nil
	}

	var people []string
	cursor := entries.Cursor()
	for key, value := cursor.First(); key != nil; key, value = cursor.Next() {
		var entry domain.WorkEntry
		if err := json.Unmarshal(value, &entry); err != nil {
			return nil, fmt.Errorf("decode entry: %w", err)
		}
		if roles[entry.CategoryID] != domain.CategoryRoleSupport {
			continue
		}
		if strings.TrimSpace(entry.Person) == "" {
			continue
		}
		people = append(people, entry.Person)
	}
	return people, nil
}

// PrimarySettings returns the settings of the workspace's primary account. The
// first admin account wins; when there is no admin the oldest account is used.
// Backups are instance-wide, so their preferences come from this account.
// found is false when the database has no accounts or the primary account has
// no settings record.
func (s *Store) PrimarySettings() (domain.Settings, bool, error) {
	users, err := readAllRaw(sysUsersBucket)
	if err != nil {
		return domain.Settings{}, false, err
	}

	ids := make([]string, 0, len(users))
	for id := range users {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	var primary domain.User
	found := false
	for _, id := range ids {
		var user domain.User
		if err := json.Unmarshal([]byte(users[id]), &user); err != nil {
			return domain.Settings{}, false, fmt.Errorf("decode user: %w", err)
		}
		if !found || (user.Role == domain.RoleAdmin && primary.Role != domain.RoleAdmin) {
			primary = user
			found = true
		}
		if primary.Role == domain.RoleAdmin {
			break
		}
	}
	if !found {
		return domain.Settings{}, false, nil
	}

	settings, err := s.Settings(primary.ID)
	if errors.Is(err, ErrNotFound) {
		return domain.Settings{}, false, nil
	}
	if err != nil {
		return domain.Settings{}, false, err
	}
	return settings, true, nil
}
