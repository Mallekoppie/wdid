package store

import (
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
)

const (
	sysMetaBucket    = "sys:meta"
	schemaVersionKey = "schema_version"
	instanceIDKey    = "instance_id"
	indexVersionKey  = "index_version"
	schemaVersion    = 1
	// indexVersion 2 rebuilds the person index with one key per name after the
	// single person string became an ordered list. Read-time JSON compatibility
	// lives on WorkEntry/ActiveTimer.UnmarshalJSON, not in a rewrite pass.
	indexVersion = 2
)

// DefaultCategory describes one entry in the taxonomy every new account
// receives.
type DefaultCategory struct {
	Name          string
	Role          domain.CategoryRole
	Subcategories []string
}

// defaultTaxonomy is the taxonomy every new account receives. Seeds are
// ordinary user-owned records: they can be renamed, extended and archived, and
// no code may special-case them by name.
var defaultTaxonomy = []DefaultCategory{
	{Name: "Initiatives", Role: domain.CategoryRoleInitiative},
	{
		Name:          "Support",
		Role:          domain.CategoryRoleSupport,
		Subcategories: []string{"Review", "Pair", "Unblock", "Mentor", "Incident", "Other"},
	},
	{
		Name:          "Other",
		Role:          domain.CategoryRoleOther,
		Subcategories: []string{"Meetings", "Admin", "Learning", "Unplanned"},
	},
}

// DefaultTaxonomy returns the taxonomy every new account receives. It is the
// single source of truth for production account seeding and the demo seeder.
// Callers must not modify the returned slice or its subcategory slices.
func DefaultTaxonomy() []DefaultCategory {
	return defaultTaxonomy
}

// seedUserTx writes the seeded taxonomy and default settings in the account
// creation transaction, so an account either has its data core or does not
// exist at all.
func seedUserTx(tx *bbolt.Tx, user domain.User) error {
	now := user.CreatedAt.UTC()
	if now.IsZero() {
		now = time.Now().UTC()
	}

	for sortOrder, seed := range defaultTaxonomy {
		category := domain.Category{
			ID:        domain.NewID(),
			UserID:    user.ID,
			Name:      seed.Name,
			Role:      seed.Role,
			SortOrder: sortOrder,
			CreatedAt: now,
			UpdatedAt: now,
		}
		if err := putJSON(tx, userBucket(user.ID, categoriesBucket), category.ID, category); err != nil {
			return err
		}

		for subOrder, name := range seed.Subcategories {
			subcategory := domain.Subcategory{
				ID:         domain.NewID(),
				UserID:     user.ID,
				CategoryID: category.ID,
				Name:       name,
				Status:     domain.SubcategoryActive,
				SortOrder:  subOrder,
				CreatedAt:  now,
				UpdatedAt:  now,
			}
			if err := putJSON(tx, userBucket(user.ID, subcategoriesBucket), subcategory.ID, subcategory); err != nil {
				return err
			}
		}
	}

	settings := domain.DefaultSettings(user.ID)
	settings.UpdatedAt = now
	return putJSON(tx, userBucket(user.ID, settingsBucket), settingsKey, settings)
}

// ensureMeta records the schema version and a stable instance identifier once.
// There is no migration code: the old model is removed in place and no data
// exists yet.
func ensureMeta() error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		bucket, err := tx.CreateBucketIfNotExists([]byte(sysMetaBucket))
		if err != nil {
			return fmt.Errorf("create meta bucket: %w", err)
		}
		if bucket.Get([]byte(schemaVersionKey)) == nil {
			if err := bucket.Put([]byte(schemaVersionKey), []byte(strconv.Itoa(schemaVersion))); err != nil {
				return err
			}
		}
		if bucket.Get([]byte(instanceIDKey)) == nil {
			if err := bucket.Put([]byte(instanceIDKey), []byte(domain.NewID())); err != nil {
				return err
			}
		}
		return nil
	})
}

// SchemaVersion returns the recorded schema version.
func (s *Store) SchemaVersion() (int, error) {
	return s.metaInt(schemaVersionKey)
}

// InstanceID returns the stable identifier of this database instance.
func (s *Store) InstanceID() (string, error) {
	var instanceID string
	err := platform.Database.BoltDb.View(func(tx *bbolt.Tx) error {
		bucket := tx.Bucket([]byte(sysMetaBucket))
		if bucket == nil {
			return ErrNotFound
		}
		raw := bucket.Get([]byte(instanceIDKey))
		if raw == nil {
			return ErrNotFound
		}
		instanceID = string(raw)
		return nil
	})
	return instanceID, err
}

func (s *Store) metaInt(key string) (int, error) {
	var value int
	err := platform.Database.BoltDb.View(func(tx *bbolt.Tx) error {
		bucket := tx.Bucket([]byte(sysMetaBucket))
		if bucket == nil {
			return ErrNotFound
		}
		raw := bucket.Get([]byte(key))
		if raw == nil {
			return ErrNotFound
		}
		parsed, err := strconv.Atoi(string(raw))
		if err != nil {
			return fmt.Errorf("parse %s: %w", key, err)
		}
		value = parsed
		return nil
	})
	return value, err
}

// ensureEntryIndexes rebuilds every user's entry indexes when the recorded
// index version differs from the current one.
func ensureEntryIndexes() error {
	rebuild := false
	err := platform.Database.BoltDb.View(func(tx *bbolt.Tx) error {
		bucket := tx.Bucket([]byte(sysMetaBucket))
		if bucket == nil {
			rebuild = true
			return nil
		}
		raw := bucket.Get([]byte(indexVersionKey))
		if raw == nil {
			rebuild = true
			return nil
		}
		parsed, err := strconv.Atoi(string(raw))
		rebuild = err != nil || parsed != indexVersion
		return nil
	})
	if err != nil {
		return err
	}
	if !rebuild {
		return nil
	}

	return rebuildEntryIndexes()
}

// rebuildEntryIndexes rebuilds every user's entry indexes unconditionally. A
// restore uses it even when the snapshot already records the current index
// version, because a snapshot may predate an index or have been written while
// an index was incomplete.
func rebuildEntryIndexes() error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		users := tx.Bucket([]byte(sysUsersBucket))
		if users != nil {
			cursor := users.Cursor()
			for key, _ := cursor.First(); key != nil; key, _ = cursor.Next() {
				if err := rebuildUserEntryIndexesTx(tx, string(key)); err != nil {
					return err
				}
			}
		}

		return tx.Bucket([]byte(sysMetaBucket)).Put([]byte(indexVersionKey), []byte(strconv.Itoa(indexVersion)))
	})
}

func rebuildUserEntryIndexesTx(tx *bbolt.Tx, userID string) error {
	for _, name := range []string{
		idxEntriesDayBucket,
		idxEntriesCategoryBucket,
		idxEntriesSubcategoryBucket,
		idxEntriesPersonBucket,
	} {
		bucket := userBucket(userID, name)
		if tx.Bucket([]byte(bucket)) == nil {
			continue
		}
		if err := tx.DeleteBucket([]byte(bucket)); err != nil {
			return fmt.Errorf("delete index bucket %s: %w", bucket, err)
		}
	}

	entries := tx.Bucket([]byte(userBucket(userID, entriesBucket)))
	if entries == nil {
		return nil
	}

	cursor := entries.Cursor()
	for key, value := cursor.First(); key != nil; key, value = cursor.Next() {
		var entry domain.WorkEntry
		if err := json.Unmarshal(value, &entry); err != nil {
			return fmt.Errorf("decode entry: %w", err)
		}
		if err := addEntryIndexes(tx, entry); err != nil {
			return err
		}
	}
	return nil
}
