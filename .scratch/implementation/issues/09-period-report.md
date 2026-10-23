# 09: Period report

**What to build:** The service returns authoritative aggregates for any period: time by category, time by subcategory, support by person, weekly rhythm, and notes. Today uses it for the week bars. The client never composes authoritative totals.

**Blocked by:** 06 (Quick capture and today's list)

**Status:** ready-for-human

- [x] A period report returns totals by category and by subcategory.
- [x] It returns support time by person and by mode.
- [x] It returns the weekly rhythm and the notes that fall in the period.
- [x] Today's week bars are rendered from the report.
- [x] An empty period returns zero totals, not an error.
- [x] No screen recomputes authoritative totals locally.
- [x] Connect and gRPC-Web tests cover totals, empty periods, and period boundaries.

## Comments

- Today is wired to the report. Initiatives and check-in detail still read the
  demo adapter until tickets 10 and 16 land; they consume this same report when
  their slices are wired, so neither composes its own totals.
