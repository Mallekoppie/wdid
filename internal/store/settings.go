package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"

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
