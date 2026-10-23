# Two-level category taxonomy with immutable reporting roles

**Status:** Accepted — 2026-10-23

Attribution started as a fixed three-way kind (`initiative`, `support`, `other`),
but users need to define their own categories. Every category is per user, the
taxonomy has exactly two levels (category → optional subcategory), and each
category carries one immutable reporting role; reports and validation use the
role, never the category name, so `Initiatives` can be renamed without breaking
anything.

**Considered options:** keeping fixed kinds (rejected: not configurable);
arbitrary nesting (deferred: recursive reporting and a tree UI for no product
need); special-casing category names (rejected: renaming breaks reports);
modelling support as a separate entity (rejected: it would create a second
attribution).

**Consequences:** support is a role with a required person and mode
subcategories; initiative subcategories carry project fields and milestones; a
category's role cannot change after creation; a third level remains out of scope.
