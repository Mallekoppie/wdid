package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"

	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/domain"
)

const (
	categoriesBucket    = "categories"
	subcategoriesBucket = "subcategories"
	entriesBucket       = "entries"
	milestonesBucket    = "milestones"
	notesBucket         = "notes"
	checkInsBucket      = "checkins"
	settingsBucket      = "settings"
)

// SaveCategory creates or replaces a category. A category's reporting role is
// immutable: saving a different role returns ErrCategoryRoleImmutable.
func (s *Store) SaveCategory(category domain.Category) error {
	category.Normalize()
	if err := domain.ValidateCategory(category); err != nil {
		return err
	}

	bucket := userBucket(category.UserID, categoriesBucket)
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		var existing domain.Category
		err := readTxObject(tx, bucket, category.ID, &existing)
		switch {
		case err == nil:
			if existing.Role != category.Role {
				return ErrCategoryRoleImmutable
			}
		case !errors.Is(err, ErrNotFound):
			return err
		}

		return putJSON(tx, bucket, category.ID, category)
	})
}

// Category returns one category owned by the user.
func (s *Store) Category(userID, id string) (domain.Category, error) {
	var category domain.Category
	if err := readObject(userBucket(userID, categoriesBucket), id, &category); err != nil {
		return domain.Category{}, err
	}
	return category, nil
}

// Categories returns the user's categories ordered by sort order, then name.
func (s *Store) Categories(userID string) ([]domain.Category, error) {
	raw, err := readAllRaw(userBucket(userID, categoriesBucket))
	if err != nil {
		return nil, err
	}

	categories := make([]domain.Category, 0, len(raw))
	for _, value := range raw {
		var category domain.Category
		if err := json.Unmarshal([]byte(value), &category); err != nil {
			return nil, fmt.Errorf("decode category: %w", err)
		}
		categories = append(categories, category)
	}

	sortCategories(categories)

	return categories, nil
}

func sortCategories(categories []domain.Category) {
	sort.Slice(categories, func(i, j int) bool {
		if categories[i].SortOrder != categories[j].SortOrder {
			return categories[i].SortOrder < categories[j].SortOrder
		}
		if categories[i].Name != categories[j].Name {
			return categories[i].Name < categories[j].Name
		}
		return categories[i].CreatedAt.Before(categories[j].CreatedAt)
	})
}

// DeleteCategory removes a category that no entry references. Its unused
// subcategories are removed with it; if any child is still referenced by an
// entry, milestone or note, the category must be archived instead.
func (s *Store) DeleteCategory(userID, id string) error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		bucket := userBucket(userID, categoriesBucket)
		var category domain.Category
		if err := readTxObject(tx, bucket, id, &category); err != nil {
			return err
		}

		inUse, err := entryReferencesCategoryTx(tx, userID, id)
		if err != nil {
			return err
		}
		if inUse {
			return ErrCategoryInUse
		}

		children, err := subcategoriesInCategoryTx(tx, userID, id)
		if err != nil {
			return err
		}
		for _, child := range children {
			referenced, err := subcategoryReferencedTx(tx, userID, child.ID)
			if err != nil {
				return err
			}
			if referenced {
				return ErrCategoryInUse
			}
		}

		if subcategories := tx.Bucket([]byte(userBucket(userID, subcategoriesBucket))); subcategories != nil {
			for _, child := range children {
				if err := subcategories.Delete([]byte(child.ID)); err != nil {
					return err
				}
			}
		}

		return tx.Bucket([]byte(bucket)).Delete([]byte(id))
	})
}

func subcategoriesInCategoryTx(tx *bbolt.Tx, userID, categoryID string) ([]domain.Subcategory, error) {
	bucket := tx.Bucket([]byte(userBucket(userID, subcategoriesBucket)))
	if bucket == nil {
		return nil, nil
	}

	var children []domain.Subcategory
	cursor := bucket.Cursor()
	for key, value := cursor.First(); key != nil; key, value = cursor.Next() {
		var subcategory domain.Subcategory
		if err := json.Unmarshal(value, &subcategory); err != nil {
			return nil, fmt.Errorf("decode subcategory: %w", err)
		}
		if subcategory.CategoryID == categoryID {
			children = append(children, subcategory)
		}
	}
	return children, nil
}

// SaveSubcategory creates or replaces a subcategory. Its parent category must
// exist and belong to the same user.
func (s *Store) SaveSubcategory(subcategory domain.Subcategory) error {
	subcategory.Normalize()
	bucket := userBucket(subcategory.UserID, subcategoriesBucket)
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		var category domain.Category
		err := readTxObject(tx, userBucket(subcategory.UserID, categoriesBucket), subcategory.CategoryID, &category)
		if errors.Is(err, ErrNotFound) {
			return ErrCategoryNotFound
		}
		if err != nil {
			return err
		}

		if err := domain.ValidateSubcategory(subcategory, category); err != nil {
			return err
		}

		// A subcategory that entries, milestones or notes already point at can
		// be renamed and archived, but moving it to another category would
		// break their attribution.
		var existing domain.Subcategory
		err = readTxObject(tx, bucket, subcategory.ID, &existing)
		switch {
		case err == nil && existing.CategoryID != subcategory.CategoryID:
			referenced, err := subcategoryReferencedTx(tx, subcategory.UserID, subcategory.ID)
			if err != nil {
				return err
			}
			if referenced {
				return ErrSubcategoryReparent
			}
		case err != nil && !errors.Is(err, ErrNotFound):
			return err
		}

		return putJSON(tx, bucket, subcategory.ID, subcategory)
	})
}

// Subcategory returns one subcategory owned by the user.
func (s *Store) Subcategory(userID, id string) (domain.Subcategory, error) {
	var subcategory domain.Subcategory
	if err := readObject(userBucket(userID, subcategoriesBucket), id, &subcategory); err != nil {
		return domain.Subcategory{}, err
	}
	return subcategory, nil
}

// Subcategories returns the user's subcategories, optionally narrowed to one
// category, ordered by sort order then name.
func (s *Store) Subcategories(userID, categoryID string) ([]domain.Subcategory, error) {
	raw, err := readAllRaw(userBucket(userID, subcategoriesBucket))
	if err != nil {
		return nil, err
	}

	subcategories := make([]domain.Subcategory, 0, len(raw))
	for _, value := range raw {
		var subcategory domain.Subcategory
		if err := json.Unmarshal([]byte(value), &subcategory); err != nil {
			return nil, fmt.Errorf("decode subcategory: %w", err)
		}
		if categoryID != "" && subcategory.CategoryID != categoryID {
			continue
		}
		subcategories = append(subcategories, subcategory)
	}

	sortSubcategories(subcategories)

	return subcategories, nil
}

func sortSubcategories(subcategories []domain.Subcategory) {
	sort.Slice(subcategories, func(i, j int) bool {
		if subcategories[i].SortOrder != subcategories[j].SortOrder {
			return subcategories[i].SortOrder < subcategories[j].SortOrder
		}
		if subcategories[i].Name != subcategories[j].Name {
			return subcategories[i].Name < subcategories[j].Name
		}
		return subcategories[i].CreatedAt.Before(subcategories[j].CreatedAt)
	})
}

// DeleteSubcategory removes a subcategory that no entry, milestone or note
// references. Referenced subcategories must be archived instead.
func (s *Store) DeleteSubcategory(userID, id string) error {
	return platform.Database.BoltDb.Update(func(tx *bbolt.Tx) error {
		var subcategory domain.Subcategory
		if err := readTxObject(tx, userBucket(userID, subcategoriesBucket), id, &subcategory); err != nil {
			return err
		}

		inUse, err := subcategoryReferencedTx(tx, userID, id)
		if err != nil {
			return err
		}
		if inUse {
			return ErrSubcategoryInUse
		}

		return tx.Bucket([]byte(userBucket(userID, subcategoriesBucket))).Delete([]byte(id))
	})
}

func entryReferencesCategoryTx(tx *bbolt.Tx, userID, categoryID string) (bool, error) {
	referenced, err := scanTxBucket(tx, userBucket(userID, entriesBucket), func(raw []byte) (bool, error) {
		var entry domain.WorkEntry
		if err := json.Unmarshal(raw, &entry); err != nil {
			return false, fmt.Errorf("decode entry: %w", err)
		}
		return entry.CategoryID == categoryID, nil
	})
	if err != nil || referenced {
		return referenced, err
	}

	// An active timer is not an entry yet, but deleting its attribution would
	// leave it pointing at a category that no longer exists.
	return scanTxBucket(tx, userBucket(userID, timerBucket), func(raw []byte) (bool, error) {
		var timer domain.ActiveTimer
		if err := json.Unmarshal(raw, &timer); err != nil {
			return false, fmt.Errorf("decode timer: %w", err)
		}
		return timer.CategoryID == categoryID, nil
	})
}

func subcategoryReferencedTx(tx *bbolt.Tx, userID, subcategoryID string) (bool, error) {
	referenced, err := scanTxBucket(tx, userBucket(userID, entriesBucket), func(raw []byte) (bool, error) {
		var entry domain.WorkEntry
		if err := json.Unmarshal(raw, &entry); err != nil {
			return false, fmt.Errorf("decode entry: %w", err)
		}
		return entry.SubcategoryID == subcategoryID, nil
	})
	if err != nil || referenced {
		return referenced, err
	}

	referenced, err = scanTxBucket(tx, userBucket(userID, timerBucket), func(raw []byte) (bool, error) {
		var timer domain.ActiveTimer
		if err := json.Unmarshal(raw, &timer); err != nil {
			return false, fmt.Errorf("decode timer: %w", err)
		}
		return timer.SubcategoryID == subcategoryID, nil
	})
	if err != nil || referenced {
		return referenced, err
	}

	referenced, err = scanTxBucket(tx, userBucket(userID, milestonesBucket), func(raw []byte) (bool, error) {
		var milestone domain.Milestone
		if err := json.Unmarshal(raw, &milestone); err != nil {
			return false, fmt.Errorf("decode milestone: %w", err)
		}
		return milestone.SubcategoryID == subcategoryID, nil
	})
	if err != nil || referenced {
		return referenced, err
	}

	return scanTxBucket(tx, userBucket(userID, notesBucket), func(raw []byte) (bool, error) {
		var note domain.Note
		if err := json.Unmarshal(raw, &note); err != nil {
			return false, fmt.Errorf("decode note: %w", err)
		}
		return note.SubcategoryID == subcategoryID, nil
	})
}
