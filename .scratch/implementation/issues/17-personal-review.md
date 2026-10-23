# 17: Personal review

**What to build:** A user can review their own work for the last week, last month, this week, this month, since the last manager check-in, or a custom range. The review opens live; saving it creates a personal check-in that stays editable and can be deleted. Personal reviews never move the manager boundary. The configured cadence offers a non-blocking review prompt and never creates drafts automatically.

**Blocked by:** 05 (Settings preferences end-to-end), 16 (Manager check-in create and finalize)

**Status:** ready-for-agent

- [ ] The timeframe picker offers last 7 days, last 30 days, this week, this month, since last manager check-in, and a custom range.
- [ ] The review opens live with the same aggregates as a check-in.
- [ ] Saving creates a personal review; leaving without saving discards it.
- [ ] A saved personal review remains editable and can be deleted.
- [ ] Personal reviews never change the manager boundary.
- [ ] The weekly or monthly cadence produces a non-blocking prompt; no draft is created automatically.
- [ ] Loading, empty, error, and validation states are handled.
- [ ] Connect and gRPC-Web tests cover save, discard, edit, delete, and boundary independence.
