# 03: Category taxonomy data core

**What to build:** The service stores the new domain model: categories with immutable reporting roles, optional subcategories, work entries attributed to a category and optional subcategory, milestones, notes, manager and personal check-ins, and settings. Every account receives seeded categories and subcategories. The old fixed-kind model is gone, and all records are isolated per user.

**Blocked by:** 01 (Remove the legacy REST surface), 02 (Bootstrap admin and invite-gated registration)

**Status:** ready-for-human

- [x] Categories, subcategories, work entries, milestones, notes, check-ins, and settings round-trip through storage.
- [x] Each new account receives the seeded taxonomy.
- [x] A subcategory must belong to its category.
- [x] Entries in a support-role category require a person.
- [x] A category role cannot change after creation.
- [x] A referenced category or subcategory can be archived but not deleted; an unused one can be deleted.
- [x] Two accounts cannot read each other's records.
- [x] The old fixed-kind model and its storage shape are removed.
- [x] Tests cover every bucket, cross-user isolation, seeds, and the invariants above.

## Comments

- Implemented and committed in `42e9fea` ("add category taxonomy data core"); every box was ticked at implementation time.
- Bookkeeping reconciliation (2026-10-23): the issue file never received a Comments entry when the work landed, so it was added during a status sweep. No code changes were made during reconciliation.
