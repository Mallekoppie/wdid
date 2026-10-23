# 03: Category taxonomy data core

**What to build:** The service stores the new domain model: categories with immutable reporting roles, optional subcategories, work entries attributed to a category and optional subcategory, milestones, notes, manager and personal check-ins, and settings. Every account receives seeded categories and subcategories. The old fixed-kind model is gone, and all records are isolated per user.

**Blocked by:** 01 (Remove the legacy REST surface), 02 (Bootstrap admin and invite-gated registration)

**Status:** ready-for-agent

- [ ] Categories, subcategories, work entries, milestones, notes, check-ins, and settings round-trip through storage.
- [ ] Each new account receives the seeded taxonomy.
- [ ] A subcategory must belong to its category.
- [ ] Entries in a support-role category require a person.
- [ ] A category role cannot change after creation.
- [ ] A referenced category or subcategory can be archived but not deleted; an unused one can be deleted.
- [ ] Two accounts cannot read each other's records.
- [ ] The old fixed-kind model and its storage shape are removed.
- [ ] Tests cover every bucket, cross-user isolation, seeds, and the invariants above.
