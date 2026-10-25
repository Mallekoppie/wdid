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
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
)

var (
	// ErrNotFound is returned when a record does not exist for the given user.
	ErrNotFound = errors.New("record not found")
	// ErrEmailExists is returned when an account already uses the email address.
	ErrEmailExists = errors.New("email already registered")
	// ErrAlreadyBootstrapped is returned when the first account already exists.
	ErrAlreadyBootstrapped = errors.New("workspace is already bootstrapped")
	// ErrInviteUsed is returned when an invite code has already been redeemed.
	ErrInviteUsed = errors.New("invite already used")
	// ErrInviteEmailMismatch is returned when a code is used for another email.
	ErrInviteEmailMismatch = errors.New("invite is for a different email")
	// ErrCategoryNotFound is returned when a category does not exist for the user.
	ErrCategoryNotFound = errors.New("category not found")
	// ErrSubcategoryNotFound is returned when a subcategory does not exist for the user.
	ErrSubcategoryNotFound = errors.New("subcategory not found")
	// ErrCategoryRoleImmutable is returned when a save tries to change a role.
	ErrCategoryRoleImmutable = errors.New("category role cannot change")
	// ErrCategoryInUse is returned when a referenced category is deleted.
	ErrCategoryInUse = errors.New("category is referenced and cannot be deleted")
	// ErrSubcategoryInUse is returned when a referenced subcategory is deleted.
	ErrSubcategoryInUse = errors.New("subcategory is referenced and cannot be deleted")
	// ErrSubcategoryReparent is returned when a referenced subcategory moves.
	ErrSubcategoryReparent = errors.New("a referenced subcategory cannot change category")
	// ErrFinalCheckInReadOnly is returned when a final manager check-in is
	// edited or deleted.
	ErrFinalCheckInReadOnly = errors.New("a final manager check-in is read-only")
	// ErrTimerRunning is returned when a start is attempted while a timer is
	// already active for the user.
	ErrTimerRunning = errors.New("a timer is already running")
	// ErrTimerNotRunning is returned when a transition needs an active timer
	// and the user has none.
	ErrTimerNotRunning = errors.New("no timer is running")
)

const (
	sysUsersBucket       = "sys:users"
	sysUserEmailsBucket  = "sys:user_emails"
	sysCredentialsBucket = "sys:user_credentials"
	sysInvitesBucket     = "sys:invites"
	timerBucket          = "timer"
	timerKey             = "active"
	settingsKey          = "app"
)

// Store persists domain records in BoltDB through goslow's platform helpers.
// Every user-owned record lives in a bucket prefixed with the user identifier,
// which keeps tenant data isolated by construction.
type Store struct {
	// dbPath is the live database file. Restore needs it to replace and reopen
	// the file that goslow opened through its package-level handle.
	dbPath string
}

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

	if err := ensureMeta(); err != nil {
		return nil, fmt.Errorf("record instance metadata: %w", err)
	}
	if err := ensureEntryIndexes(); err != nil {
		return nil, fmt.Errorf("rebuild entry indexes: %w", err)
	}

	return &Store{dbPath: cfg.DBPath}, nil
}

// Close releases the database handle.
func (s *Store) Close() error {
	return platform.Database.BoltDb.Close()
}

// --- users ---------------------------------------------------------------

// CreateUser stores a new account and its email index entry. It is used for
// accounts without a local password, such as the first OIDC login.
func (s *Store) CreateUser(user domain.User) error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		return createUserTx(tx, user, nil)
	})
}

// CreateSeedUser stores an account with its local credential and email index in
// one transaction, without the default taxonomy and settings that
// CreateUser-backed paths seed. A caller that owns the account's records, such
// as the demo seeder, uses it to avoid inheriting randomly identified defaults.
func (s *Store) CreateSeedUser(user domain.User, passwordHash string) error {
	user.Normalize()
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		return createUserRecordTx(tx, user, &passwordHash)
	})
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

// PasswordHash returns the stored local login credential.
func (s *Store) PasswordHash(userID string) (string, error) {
	var hash string
	if err := readObject(sysCredentialsBucket, userID, &hash); err != nil {
		return "", err
	}
	return hash, nil
}

// --- invites -------------------------------------------------------------

// CreateInvite stores a single-use invite under the hash of its code.
func (s *Store) CreateInvite(invite domain.Invite, codeHash string) error {
	return saveObject(sysInvitesBucket, codeHash, invite)
}

// CheckInvite reports whether an invite code can still be redeemed by the
// address. Registration calls it before hashing the password; the write
// transaction re-checks the invite when it is actually consumed.
func (s *Store) CheckInvite(codeHash, email string) error {
	var invite domain.Invite
	if err := readObject(sysInvitesBucket, codeHash, &invite); err != nil {
		return err
	}

	invite.Normalize()
	return inviteUsable(invite, email)
}

func inviteUsable(invite domain.Invite, email string) error {
	if invite.UsedAt != nil {
		return ErrInviteUsed
	}
	if !strings.EqualFold(invite.Email, strings.TrimSpace(email)) {
		return ErrInviteEmailMismatch
	}
	return nil
}

// Invites returns every invite, newest first.
func (s *Store) Invites() ([]domain.Invite, error) {
	raw, err := readAllRaw(sysInvitesBucket)
	if err != nil {
		return nil, err
	}

	invites := make([]domain.Invite, 0, len(raw))
	for _, value := range raw {
		var invite domain.Invite
		if err := json.Unmarshal([]byte(value), &invite); err != nil {
			return nil, fmt.Errorf("decode invite: %w", err)
		}
		invites = append(invites, invite)
	}

	sort.Slice(invites, func(i, j int) bool {
		return invites[i].CreatedAt.After(invites[j].CreatedAt)
	})

	return invites, nil
}

// RevokeInvite removes an invite so its code can no longer be redeemed.
func (s *Store) RevokeInvite(id string) error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		bucket := tx.Bucket([]byte(sysInvitesBucket))
		if bucket == nil {
			return ErrNotFound
		}

		cursor := bucket.Cursor()
		for key, value := cursor.First(); key != nil; key, value = cursor.Next() {
			var invite domain.Invite
			if err := json.Unmarshal(value, &invite); err != nil {
				return fmt.Errorf("decode invite: %w", err)
			}
			if invite.ID == id {
				return bucket.Delete(key)
			}
		}

		return ErrNotFound
	})
}

// CreateBootstrapUser creates the first account in one transaction. It fails if
// any account exists, so the bootstrap secret cannot be reused.
func (s *Store) CreateBootstrapUser(user domain.User, passwordHash string) error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		users, err := tx.CreateBucketIfNotExists([]byte(sysUsersBucket))
		if err != nil {
			return fmt.Errorf("create user bucket: %w", err)
		}
		if key, _ := users.Cursor().First(); key != nil {
			return ErrAlreadyBootstrapped
		}
		return createUserTx(tx, user, &passwordHash)
	})
}

// CreateInvitedUser redeems an invite and creates the account in one
// transaction. Any failure leaves the invite unused.
func (s *Store) CreateInvitedUser(user domain.User, passwordHash, codeHash string, now time.Time) (domain.Invite, error) {
	var invite domain.Invite

	err := platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		invites, err := tx.CreateBucketIfNotExists([]byte(sysInvitesBucket))
		if err != nil {
			return fmt.Errorf("create invite bucket: %w", err)
		}

		raw := invites.Get([]byte(codeHash))
		if raw == nil {
			return ErrNotFound
		}
		if err := json.Unmarshal(raw, &invite); err != nil {
			return fmt.Errorf("decode invite: %w", err)
		}
		if invite.UsedAt != nil {
			return ErrInviteUsed
		}

		invite.Normalize()
		user.Normalize()
		if err := inviteUsable(invite, user.Email); err != nil {
			return err
		}

		if err := createUserTx(tx, user, &passwordHash); err != nil {
			return err
		}

		usedAt := now.UTC()
		invite.UsedAt = &usedAt
		invite.UsedBy = user.ID

		return putJSON(tx, sysInvitesBucket, codeHash, invite)
	})
	if err != nil {
		return domain.Invite{}, err
	}

	return invite, nil
}

// --- timer ---------------------------------------------------------------

// ActiveTimer returns the user's running timer, if one exists.
func (s *Store) ActiveTimer(userID string) (domain.ActiveTimer, bool, error) {
	var timer domain.ActiveTimer
	err := readObject(userBucket(userID, timerBucket), timerKey, &timer)
	if errors.Is(err, ErrNotFound) {
		return domain.ActiveTimer{}, false, nil
	}
	if err != nil {
		return domain.ActiveTimer{}, false, err
	}
	return timer, true, nil
}

// SaveTimer stores the user's running timer. Lifecycle changes go through the
// transition methods so the one-timer invariant holds; this is for seeding and
// tests.
func (s *Store) SaveTimer(timer domain.ActiveTimer) error {
	timer.Normalize()
	return saveObject(userBucket(timer.UserID, timerBucket), timerKey, timer)
}

// ClearTimer removes the user's running timer.
func (s *Store) ClearTimer(userID string) error {
	return platform.Database.BoltDb.RemoveObject(userBucket(userID, timerBucket), timerKey)
}

// --- helpers -------------------------------------------------------------

func userBucket(userID, name string) string {
	return "user_" + userID + ":" + name
}

func saveObject(bucket, id string, object interface{}) error {
	return platform.Database.BoltDb.SaveObject(bucket, id, object)
}

// createUserTx writes the account records and then the default taxonomy and
// settings. Production account creation goes through it so an account either
// has its data core or does not exist at all.
func createUserTx(tx *bbolt.Tx, user domain.User, passwordHash *string) error {
	if err := createUserRecordTx(tx, user, passwordHash); err != nil {
		return err
	}
	return seedUserTx(tx, user)
}

// createUserRecordTx writes the profile, optional credential and email index in
// the caller's transaction. It does not create any user-owned seed records.
func createUserRecordTx(tx *bbolt.Tx, user domain.User, passwordHash *string) error {
	emails, err := tx.CreateBucketIfNotExists([]byte(sysUserEmailsBucket))
	if err != nil {
		return fmt.Errorf("create email bucket: %w", err)
	}

	emailKey := strings.ToLower(strings.TrimSpace(user.Email))
	if emails.Get([]byte(emailKey)) != nil {
		return ErrEmailExists
	}

	if passwordHash != nil {
		if err := putJSON(tx, sysCredentialsBucket, user.ID, *passwordHash); err != nil {
			return err
		}
	}
	if err := putJSON(tx, sysUsersBucket, user.ID, user); err != nil {
		return err
	}
	if err := putJSON(tx, sysUserEmailsBucket, emailKey, user.ID); err != nil {
		return err
	}

	return nil
}

// readTxObject reads one record inside an open transaction. A missing bucket
// or key is ErrNotFound.
func readTxObject(tx *bbolt.Tx, bucket, id string, out interface{}) error {
	target := tx.Bucket([]byte(bucket))
	if target == nil {
		return ErrNotFound
	}
	raw := target.Get([]byte(id))
	if raw == nil {
		return ErrNotFound
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return fmt.Errorf("decode %s/%s: %w", bucket, id, err)
	}
	return nil
}

// scanTxBucket visits every value in a bucket and stops at the first match.
func scanTxBucket(tx *bbolt.Tx, bucket string, match func([]byte) (bool, error)) (bool, error) {
	target := tx.Bucket([]byte(bucket))
	if target == nil {
		return false, nil
	}

	cursor := target.Cursor()
	for key, value := cursor.First(); key != nil; key, value = cursor.Next() {
		ok, err := match(value)
		if err != nil {
			return false, err
		}
		if ok {
			return true, nil
		}
	}
	return false, nil
}

func putJSON(tx *bbolt.Tx, bucket, id string, object interface{}) error {
	target, err := tx.CreateBucketIfNotExists([]byte(bucket))
	if err != nil {
		return fmt.Errorf("create bucket %s: %w", bucket, err)
	}

	data, err := json.Marshal(object)
	if err != nil {
		return fmt.Errorf("encode %s/%s: %w", bucket, id, err)
	}

	return target.Put([]byte(id), data)
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
