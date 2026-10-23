package store

import (
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
