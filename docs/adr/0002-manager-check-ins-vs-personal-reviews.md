# Manager check-ins and personal reviews are one record with a kind

**Status:** Accepted — 2026-10-23

A single check-in type conflated the manager-facing boundary ("everything since
we last spoke") with self-directed weekly and monthly review. Check-ins are one
record with a `kind` of `manager` or `personal`; only a final manager check-in
moves the next boundary, and personal reviews remain editable, are saved on
demand, and never affect it.

**Considered options:** two separate entities (rejected: duplicated period,
summary, and export logic); quarters as the boundary (rejected: the product's
period is since the last check-in, and a quarter is only a preset);
auto-creating weekly drafts (rejected: empty records and cleanup).

**Consequences:** one service and store bucket; the UI filters the list by kind;
the audience preset (`1:1`, `performance review`) applies only to manager
check-ins; a saved personal review may be deleted while a final manager check-in
may not.
