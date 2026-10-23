# 09: Period report

**What to build:** The service returns authoritative aggregates for any period: time by category, time by subcategory, support by person, weekly rhythm, and notes. Today uses it for the week bars. The client never composes authoritative totals.

**Blocked by:** 06 (Quick capture and today's list)

**Status:** ready-for-agent

- [ ] A period report returns totals by category and by subcategory.
- [ ] It returns support time by person and by mode.
- [ ] It returns the weekly rhythm and the notes that fall in the period.
- [ ] Today's week bars are rendered from the report.
- [ ] An empty period returns zero totals, not an error.
- [ ] No screen recomputes authoritative totals locally.
- [ ] Connect and gRPC-Web tests cover totals, empty periods, and period boundaries.
