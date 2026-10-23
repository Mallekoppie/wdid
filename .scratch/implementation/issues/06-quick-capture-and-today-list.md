# 06: Quick capture and today's list

**What to build:** A work entry can be captured in one line from Today: description, category, optional subcategory, and duration. Pressing Enter saves it. Today's list shows the day's entries with their attribution and outcome, and the category selector remembers the last used pair.

**Blocked by:** 03 (Category taxonomy data core), 04 (Category management end-to-end), 05 (Settings preferences end-to-end)

**Status:** ready-for-agent

- [x] An entry can be created from one line with a category, optional subcategory, description, and duration.
- [x] The default duration comes from settings.
- [x] Today's list shows the day's entries with category, subcategory, description, and outcome.
- [x] An entry's outcome can be added after capture.
- [x] The selector remembers the last used category and subcategory.
- [x] Validation errors appear on the right fields.
- [x] The screen handles loading, empty, error, and success states.
- [x] Connect and gRPC-Web tests cover create, list, and validation.
