# 04: Category management end-to-end

**What to build:** A user can see their taxonomy, create categories and subcategories, rename them, archive them, and choose a reporting role when a category is created. Roles are fixed after creation, and archived categories stay visible in historical reporting.

**Blocked by:** 03 (Category taxonomy data core)

**Status:** ready-for-human

- [x] Settings → Categories lists categories with their role, archived state, and subcategories.
- [x] A user can create, rename, and archive a category and a subcategory.
- [x] A reporting role is chosen at category creation and cannot be changed afterwards.
- [x] A category or subcategory referenced by a work entry can be archived but not deleted.
- [x] A newly created or renamed category appears in the entry selectors.
- [x] Connect and gRPC-Web tests cover the operations.
- [x] The screen handles loading, empty, error, and validation states.

## Comments

- Implemented and committed in `2ebd5f8` ("implement category management and settings preferences"); every box was ticked at implementation time.
- Bookkeeping reconciliation (2026-10-23): the issue file never received a Comments entry or the post-implementation status when the work landed, so both were added during a status sweep. No code changes were made during reconciliation.
