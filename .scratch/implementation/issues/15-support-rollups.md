# 15: Support rollups

**What to build:** The Support screen shows how much support time went to each person and each mode over a period. The rollups come from the server period report and match the support section of a manager check-in.

**Blocked by:** 09 (Period report), 14 (Support logging)

**Status:** ready-for-agent

- [ ] Support time is rolled up by person for the selected period.
- [ ] Support time is rolled up by mode using subcategories.
- [ ] The screen shows the number of people and interactions.
- [ ] Rollups come from the period report, not client-side addition.
- [ ] An empty period returns an empty rollup, not an error.
- [ ] Connect and gRPC-Web tests cover person and mode totals and period boundaries.
