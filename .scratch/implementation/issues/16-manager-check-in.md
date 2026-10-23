# 16: Manager check-in create and finalize

**What to build:** A user can create a manager check-in that covers everything since the last final manager check-in. The detail view shows time by category and project, support, and progress. Marking it final makes it read-only and moves the boundary for the next manager check-in. The list can be filtered by kind, and an audience of 1:1 or performance review can be chosen.

**Blocked by:** 03 (Category taxonomy data core), 04 (Category management end-to-end), 09 (Period report)

**Status:** ready-for-agent

- [ ] The period is prefilled from the last final manager check-in, or the journal start date, to today, and is editable.
- [ ] Focus notes can be added when creating the check-in.
- [ ] The check-in list shows manager and personal check-ins and can filter by kind.
- [ ] The detail shows totals by category, by project, support by person, and weekly rhythm.
- [ ] Marking final makes the check-in read-only and moves the next boundary.
- [ ] A manager check-in can choose the 1:1 or performance-review audience.
- [ ] Loading, empty, error, and validation states are handled.
- [ ] Connect and gRPC-Web tests cover creation, boundary calculation, finalization, and audience.
