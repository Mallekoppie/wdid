package store_test

import (
	"errors"
	"testing"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

func testCategory(userID, name string, role domain.CategoryRole) domain.Category {
	now := time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)
	return domain.Category{
		ID:        domain.NewID(),
		UserID:    userID,
		Name:      name,
		Role:      role,
		SortOrder: 0,
		CreatedAt: now,
		UpdatedAt: now,
	}
}

func testSubcategory(userID, categoryID, name string) domain.Subcategory {
	now := time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)
	return domain.Subcategory{
		ID:         domain.NewID(),
		UserID:     userID,
		CategoryID: categoryID,
		Name:       name,
		Status:     domain.SubcategoryActive,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
}

func TestCategoryAndSubcategoryRoundTrip(t *testing.T) {
	database := newStore(t)
	userID := "user-taxonomy"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	category.SortOrder = 2
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}

	stored, err := database.Category(userID, category.ID)
	if err != nil {
		t.Fatalf("read category: %v", err)
	}
	if stored.Name != category.Name || stored.Role != category.Role || stored.SortOrder != category.SortOrder {
		t.Fatalf("stored category = %+v, want %+v", stored, category)
	}

	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	subcategory.Progress = 64
	subcategory.TargetDate = "2026-11-30"
	subcategory.Links = []domain.Link{{Label: "Epic", URL: "https://example.com/epic"}}
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}

	storedSub, err := database.Subcategory(userID, subcategory.ID)
	if err != nil {
		t.Fatalf("read subcategory: %v", err)
	}
	if storedSub.CategoryID != category.ID || storedSub.Progress != 64 || storedSub.TargetDate != "2026-11-30" {
		t.Fatalf("stored subcategory = %+v, want %+v", storedSub, subcategory)
	}
	if len(storedSub.Links) != 1 || storedSub.Links[0].Label != "Epic" {
		t.Fatalf("stored links = %+v, want the saved link", storedSub.Links)
	}

	// Sort order, not creation order, drives the category list.
	first := testCategory(userID, "Other", domain.CategoryRoleOther)
	first.SortOrder = 0
	if err := database.SaveCategory(first); err != nil {
		t.Fatalf("save second category: %v", err)
	}
	categories, err := database.Categories(userID)
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}
	if len(categories) != 2 || categories[0].ID != first.ID || categories[1].ID != category.ID {
		t.Fatalf("categories = %+v, want Other then Initiatives", categories)
	}

	subcategories, err := database.Subcategories(userID, category.ID)
	if err != nil {
		t.Fatalf("list subcategories: %v", err)
	}
	if len(subcategories) != 1 || subcategories[0].ID != subcategory.ID {
		t.Fatalf("subcategories = %+v, want the saved subcategory", subcategories)
	}

	// Another account cannot see either record.
	if _, err := database.Category("user-other", category.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("cross-user category error = %v, want ErrNotFound", err)
	}
	if _, err := database.Subcategory("user-other", subcategory.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("cross-user subcategory error = %v, want ErrNotFound", err)
	}
	otherCategories, err := database.Categories("user-other")
	if err != nil {
		t.Fatalf("list other user categories: %v", err)
	}
	if len(otherCategories) != 0 {
		t.Fatalf("other user categories = %+v, want none", otherCategories)
	}
}

func TestSubcategoryRequiresItsCategory(t *testing.T) {
	database := newStore(t)

	subcategory := testSubcategory("user-taxonomy", "missing-category", "Billing migration")
	if err := database.SaveSubcategory(subcategory); !errors.Is(err, store.ErrCategoryNotFound) {
		t.Fatalf("save subcategory error = %v, want ErrCategoryNotFound", err)
	}

	// A category belonging to another user is not a valid parent either.
	owner := "user-a"
	other := "user-b"
	category := testCategory(owner, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	crossUser := testSubcategory(other, category.ID, "Billing migration")
	if err := database.SaveSubcategory(crossUser); !errors.Is(err, store.ErrCategoryNotFound) {
		t.Fatalf("cross-user parent error = %v, want ErrCategoryNotFound", err)
	}
}

func TestCategoryRoleCannotChange(t *testing.T) {
	database := newStore(t)
	userID := "user-taxonomy"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}

	category.Name = "Projects"
	category.UpdatedAt = category.UpdatedAt.Add(time.Hour)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("rename category: %v", err)
	}
	stored, err := database.Category(userID, category.ID)
	if err != nil {
		t.Fatalf("read renamed category: %v", err)
	}
	if stored.Name != "Projects" || stored.Role != domain.CategoryRoleInitiative {
		t.Fatalf("renamed category = %+v, want Projects as initiative", stored)
	}

	category.Role = domain.CategoryRoleSupport
	if err := database.SaveCategory(category); !errors.Is(err, store.ErrCategoryRoleImmutable) {
		t.Fatalf("role change error = %v, want ErrCategoryRoleImmutable", err)
	}
	stored, err = database.Category(userID, category.ID)
	if err != nil {
		t.Fatalf("read category after rejected change: %v", err)
	}
	if stored.Role != domain.CategoryRoleInitiative {
		t.Fatalf("role = %q after rejected change, want initiative", stored.Role)
	}
}

func TestSavedTimestampsAreStoredInUTC(t *testing.T) {
	database := newStore(t)
	userID := "user-utc"

	zone := time.FixedZone("CEST", 2*60*60)
	local := time.Date(2026, 10, 23, 10, 0, 0, 0, zone)

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	category.CreatedAt = local
	category.UpdatedAt = local
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}

	stored, err := database.Category(userID, category.ID)
	if err != nil {
		t.Fatalf("read category: %v", err)
	}
	if stored.CreatedAt.Location() != time.UTC || !stored.CreatedAt.Equal(local) {
		t.Fatalf("createdAt = %v, want the same instant in UTC", stored.CreatedAt)
	}
}

func TestReferencedSubcategoryCannotChangeCategory(t *testing.T) {
	database := newStore(t)
	userID := "user-reparent"

	first := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	second := testCategory(userID, "Projects", domain.CategoryRoleInitiative)
	for _, category := range []domain.Category{first, second} {
		if err := database.SaveCategory(category); err != nil {
			t.Fatalf("save category: %v", err)
		}
	}

	subcategory := testSubcategory(userID, first.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}
	entry := testWorkEntry(userID, first, subcategory.ID, time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC), "Backfill")
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save entry: %v", err)
	}

	subcategory.CategoryID = second.ID
	if err := database.SaveSubcategory(subcategory); !errors.Is(err, store.ErrSubcategoryReparent) {
		t.Fatalf("reparent error = %v, want ErrSubcategoryReparent", err)
	}
	stored, err := database.Subcategory(userID, subcategory.ID)
	if err != nil {
		t.Fatalf("read subcategory: %v", err)
	}
	if stored.CategoryID != first.ID {
		t.Fatalf("categoryId = %q, want the original parent", stored.CategoryID)
	}

	// An unreferenced subcategory may move.
	unused := testSubcategory(userID, first.ID, "Unused project")
	if err := database.SaveSubcategory(unused); err != nil {
		t.Fatalf("save unused subcategory: %v", err)
	}
	unused.CategoryID = second.ID
	if err := database.SaveSubcategory(unused); err != nil {
		t.Fatalf("move unused subcategory: %v", err)
	}
}

func TestUnusedCategoryWithChildrenCanBeDeleted(t *testing.T) {
	database := newStore(t)
	userID := "user-cascade"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	first := testSubcategory(userID, category.ID, "Billing migration")
	second := testSubcategory(userID, category.ID, "Onboarding")
	for _, subcategory := range []domain.Subcategory{first, second} {
		if err := database.SaveSubcategory(subcategory); err != nil {
			t.Fatalf("save subcategory: %v", err)
		}
	}

	if err := database.DeleteCategory(userID, category.ID); err != nil {
		t.Fatalf("delete unused category: %v", err)
	}
	if _, err := database.Category(userID, category.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("deleted category read error = %v, want ErrNotFound", err)
	}
	for _, subcategory := range []domain.Subcategory{first, second} {
		if _, err := database.Subcategory(userID, subcategory.ID); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("child subcategory read error = %v, want ErrNotFound", err)
		}
	}
}

func TestCategoryWithReferencedChildCannotBeDeleted(t *testing.T) {
	database := newStore(t)
	userID := "user-cascade-ref"

	category := testCategory(userID, "Initiatives", domain.CategoryRoleInitiative)
	if err := database.SaveCategory(category); err != nil {
		t.Fatalf("save category: %v", err)
	}
	subcategory := testSubcategory(userID, category.ID, "Billing migration")
	if err := database.SaveSubcategory(subcategory); err != nil {
		t.Fatalf("save subcategory: %v", err)
	}
	now := time.Date(2026, 10, 23, 8, 0, 0, 0, time.UTC)
	milestone := domain.Milestone{
		ID: domain.NewID(), UserID: userID, SubcategoryID: subcategory.ID,
		Title: "Ship backfill", DueDate: "2026-10-31", CreatedAt: now, UpdatedAt: now,
	}
	if err := database.SaveMilestone(milestone); err != nil {
		t.Fatalf("save milestone: %v", err)
	}

	if err := database.DeleteCategory(userID, category.ID); !errors.Is(err, store.ErrCategoryInUse) {
		t.Fatalf("delete category with referenced child error = %v, want ErrCategoryInUse", err)
	}
	if _, err := database.Subcategory(userID, subcategory.ID); err != nil {
		t.Fatalf("referenced child must survive: %v", err)
	}
}
