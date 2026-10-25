package demo

import "strings"

// stableCategoryID derives the deterministic category ID for a scenario. Names
// are trimmed here so the built-in taxonomy, the declarative fixture and
// fixture references cannot disagree about the stable key.
func stableCategoryID(scenario, name string) string {
	return stableID(scenario, "category", strings.TrimSpace(name))
}

// stableSubcategoryID derives the deterministic subcategory ID beneath one
// category. The "/" separator is part of the stable key; changing it would
// change every seeded category and subcategory ID.
func stableSubcategoryID(scenario, category, subcategory string) string {
	return stableID(scenario, "subcategory", fixtureProjectRef(category, subcategory))
}

// fixtureProjectRef is the stable "category/subcategory" label used by IDs and
// by the notes/milestones fixture validators. Both halves are trimmed exactly
// as the seeder trims them.
func fixtureProjectRef(category, subcategory string) string {
	return strings.TrimSpace(category) + "/" + strings.TrimSpace(subcategory)
}
