# 08: Log editing and filters

**What to build:** A user can find and correct work entries. Log supports date presets and custom ranges, category and subcategory filters, and text search. Entries are grouped by local day with totals, and can be edited inline, split, and deleted. Overlapping manual entries are allowed and visibly flagged.

**Blocked by:** 06 (Quick capture and today's list)

**Status:** ready-for-agent

- [x] Date filters: today, this week, last 7 days, this month, since last manager check-in, and custom range.
- [x] Category, subcategory, and text filters combine.
- [x] Entries are grouped by local day with day and period totals.
- [x] An entry's description, category, subcategory, times, and outcome can be edited inline.
- [x] An entry can be split and deleted.
- [x] Overlapping manual entries are allowed and marked as overlapping.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover filters, update, split, delete, and overlap detection.
