package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
)

var (
	// ErrNotFound is returned when a record does not exist for the given user.
	ErrNotFound = errors.New("record not found")
	// ErrEmailExists is returned when an account already uses the email address.
	ErrEmailExists = errors.New("email already registered")
)

const (
	sysUsersBucket       = "sys:users"
	sysUserEmailsBucket  = "sys:user_emails"
	sysCredentialsBucket = "sys:user_credentials"
	timerKey             = "active"
)

// Store persists domain records in BoltDB through goslow's platform helpers.
// Every user-owned record lives in a bucket prefixed with the user identifier,
// which keeps tenant data isolated by construction.
type Store struct{}

// Open configures goslow and opens the BoltDB database.
func Open(cfg config.Config) (*Store, error) {
	if err := platform.SetPlatformConfiguration(cfg.PlatformConfig()); err != nil {
		return nil, fmt.Errorf("configure platform: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(cfg.DBPath), 0o750); err != nil {
		return nil, fmt.Errorf("create data directory: %w", err)
	}

	// goslow opens BoltDB with os.ModeExclusive as the file mode. For a new
	// file that resolves to permissions 0000, so the database cannot be
	// reopened. Pre-creating the file with usable, restrictive permissions
	// keeps goslow's helper untouched and the data readable by the service.
	file, err := os.OpenFile(cfg.DBPath, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("prepare database file: %w", err)
	}
	if err := file.Close(); err != nil {
		return nil, fmt.Errorf("close database file: %w", err)
	}

	if err := platform.SetupBoltDB(); err != nil {
		return nil, fmt.Errorf("open boltdb: %w", err)
	}

	return &Store{}, nil
}

// Close releases the database handle.
func (s *Store) Close() error {
	return platform.Database.BoltDb.Close()
}

// --- users ---------------------------------------------------------------

// CreateUser stores a new account and its email index entry.
func (s *Store) CreateUser(user domain.User) error {
	emailKey := strings.ToLower(strings.TrimSpace(user.Email))

	var existingID string
	err := readObject(sysUserEmailsBucket, emailKey, &existingID)
	switch {
	case err == nil:
		return ErrEmailExists
	case !errors.Is(err, ErrNotFound):
		return err
	}

	if err := saveObject(sysUsersBucket, user.ID, user); err != nil {
		return err
	}

	return saveObject(sysUserEmailsBucket, emailKey, user.ID)
}

// UserByID returns an account by identifier.
func (s *Store) UserByID(id string) (domain.User, error) {
	var user domain.User
	if err := readObject(sysUsersBucket, id, &user); err != nil {
		return domain.User{}, err
	}
	return user, nil
}

// UserByEmail returns an account by email address.
func (s *Store) UserByEmail(email string) (domain.User, error) {
	var userID string
	if err := readObject(sysUserEmailsBucket, strings.ToLower(strings.TrimSpace(email)), &userID); err != nil {
		return domain.User{}, err
	}
	return s.UserByID(userID)
}

// CountUsers returns the number of registered accounts.
func (s *Store) CountUsers() (int, error) {
	users, err := readAllRaw(sysUsersBucket)
	if err != nil {
		return 0, err
	}
	return len(users), nil
}

// SetPasswordHash stores the local login credential for an account.
// Credentials live outside the user profile so they are never serialized into
// API responses.
func (s *Store) SetPasswordHash(userID, hash string) error {
	return saveObject(sysCredentialsBucket, userID, hash)
}

// PasswordHash returns the stored local login credential.
func (s *Store) PasswordHash(userID string) (string, error) {
	var hash string
	if err := readObject(sysCredentialsBucket, userID, &hash); err != nil {
		return "", err
	}
	return hash, nil
}

// --- initiatives ---------------------------------------------------------

// SaveInitiative creates or replaces an initiative.
func (s *Store) SaveInitiative(initiative domain.Initiative) error {
	return saveObject(userBucket(initiative.UserID, "initiatives"), initiative.ID, initiative)
}

// Initiative returns one initiative owned by the user.
func (s *Store) Initiative(userID, id string) (domain.Initiative, error) {
	var initiative domain.Initiative
	if err := readObject(userBucket(userID, "initiatives"), id, &initiative); err != nil {
		return domain.Initiative{}, err
	}
	return initiative, nil
}

// Initiatives returns the user's initiatives, most recently updated first.
func (s *Store) Initiatives(userID string) ([]domain.Initiative, error) {
	raw, err := readAllRaw(userBucket(userID, "initiatives"))
	if err != nil {
		return nil, err
	}

	initiatives := make([]domain.Initiative, 0, len(raw))
	for _, value := range raw {
		var initiative domain.Initiative
		if err := json.Unmarshal([]byte(value), &initiative); err != nil {
			return nil, fmt.Errorf("decode initiative: %w", err)
		}
		initiatives = append(initiatives, initiative)
	}

	sort.Slice(initiatives, func(i, j int) bool {
		return initiatives[i].UpdatedAt.After(initiatives[j].UpdatedAt)
	})

	return initiatives, nil
}

// DeleteInitiative removes an initiative record. Existing entries keep their
// initiative identifier so historical reporting stays intact.
func (s *Store) DeleteInitiative(userID, id string) error {
	if _, err := s.Initiative(userID, id); err != nil {
		return err
	}
	return platform.Database.BoltDb.RemoveObject(userBucket(userID, "initiatives"), id)
}

// --- entries -------------------------------------------------------------

// EntryFilter narrows an entry listing.
type EntryFilter struct {
	From         time.Time
	To           time.Time
	Kind         domain.EntryKind
	InitiativeID string
	Query        string
	Limit        int
}

// SaveEntry creates or replaces a work entry.
func (s *Store) SaveEntry(entry domain.Entry) error {
	return saveObject(userBucket(entry.UserID, "entries"), entry.ID, entry)
}

// Entry returns one entry owned by the user.
func (s *Store) Entry(userID, id string) (domain.Entry, error) {
	var entry domain.Entry
	if err := readObject(userBucket(userID, "entries"), id, &entry); err != nil {
		return domain.Entry{}, err
	}
	return entry, nil
}

// DeleteEntry removes one entry owned by the user.
func (s *Store) DeleteEntry(userID, id string) error {
	if _, err := s.Entry(userID, id); err != nil {
		return err
	}
	return platform.Database.BoltDb.RemoveObject(userBucket(userID, "entries"), id)
}

// Entries returns the user's entries matching the filter, newest first.
func (s *Store) Entries(userID string, filter EntryFilter) ([]domain.Entry, error) {
	raw, err := readAllRaw(userBucket(userID, "entries"))
	if err != nil {
		return nil, err
	}

	query := strings.ToLower(strings.TrimSpace(filter.Query))
	entries := make([]domain.Entry, 0, len(raw))
	for _, value := range raw {
		var entry domain.Entry
		if err := json.Unmarshal([]byte(value), &entry); err != nil {
			return nil, fmt.Errorf("decode entry: %w", err)
		}
		if !entryMatches(entry, filter, query) {
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

func entryMatches(entry domain.Entry, filter EntryFilter, query string) bool {
	if !filter.From.IsZero() && entry.StartedAt.Before(filter.From) {
		return false
	}
	if !filter.To.IsZero() && !entry.StartedAt.Before(filter.To) {
		return false
	}
	if filter.Kind != "" && entry.Kind != filter.Kind {
		return false
	}
	if filter.InitiativeID != "" && entry.InitiativeID != filter.InitiativeID {
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

// --- timer ---------------------------------------------------------------

// ActiveTimer returns the user's running timer, if one exists.
func (s *Store) ActiveTimer(userID string) (domain.ActiveTimer, bool, error) {
	var timer domain.ActiveTimer
	err := readObject(userBucket(userID, "timer"), timerKey, &timer)
	if errors.Is(err, ErrNotFound) {
		return domain.ActiveTimer{}, false, nil
	}
	if err != nil {
		return domain.ActiveTimer{}, false, err
	}
	return timer, true, nil
}

// SaveTimer stores the user's running timer.
func (s *Store) SaveTimer(timer domain.ActiveTimer) error {
	return saveObject(userBucket(timer.UserID, "timer"), timerKey, timer)
}

// ClearTimer removes the user's running timer.
func (s *Store) ClearTimer(userID string) error {
	return platform.Database.BoltDb.RemoveObject(userBucket(userID, "timer"), timerKey)
}

// --- helpers -------------------------------------------------------------

func userBucket(userID, name string) string {
	return "user_" + userID + ":" + name
}

func saveObject(bucket, id string, object interface{}) error {
	return platform.Database.BoltDb.SaveObject(bucket, id, object)
}

// readObject reads through ReadAllObjects because goslow's ReadObject panics
// on a missing bucket (it dereferences a nil *bolt.Bucket).
func readObject(bucket, id string, out interface{}) error {
	values, err := readAllRaw(bucket)
	if err != nil {
		return err
	}
	raw, ok := values[id]
	if !ok {
		return ErrNotFound
	}
	if err := json.Unmarshal([]byte(raw), out); err != nil {
		return fmt.Errorf("decode %s/%s: %w", bucket, id, err)
	}
	return nil
}

// readAllRaw returns the raw JSON values in a bucket. A missing bucket is an
// empty result rather than an error.
func readAllRaw(bucket string) (map[string]string, error) {
	values, err := platform.Database.BoltDb.ReadAllObjects(bucket)
	if errors.Is(err, platform.ErrNoEntryFoundInDB) {
		return map[string]string{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read bucket %s: %w", bucket, err)
	}
	return values, nil
}
