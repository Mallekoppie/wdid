# 21: Backup snapshots

**What to build:** The service can take consistent, point-in-time snapshots of the database on a schedule and on demand, verify each snapshot before reporting success, and retain the newest scheduled snapshots. Manual snapshots are never deleted automatically, and the CLI exposes a manual backup.

**Blocked by:** 03 (Category taxonomy data core)

**Status:** ready-for-agent

- [ ] A snapshot is written from a read transaction to a temp file, synced, and atomically renamed.
- [ ] A snapshot is verified by opening it read-only and reading the schema version before success is reported.
- [ ] Scheduled snapshots run at the configured interval, including once at startup when overdue.
- [ ] Retention keeps the newest configured number of scheduled snapshots and never deletes a manual one.
- [ ] The CLI can take a manual backup.
- [ ] Backup status reports the last backup time and size and whether it is overdue.
- [ ] Tests cover snapshot creation, verification, retention, and the manual/automatic split.
