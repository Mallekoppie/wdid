# 22: Restore and backup status UI

**What to build:** A user can restore a chosen backup. Restoring verifies the backup, copies the current database aside, replaces it, reopens the store, and rebuilds indexes. Settings shows the backup status, the snapshot list, manual backup, restore, and an overdue warning.

**Blocked by:** 05 (Settings preferences end-to-end), 21 (Backup snapshots)

**Status:** ready-for-agent

- [ ] Restore verifies the selected backup before changing anything.
- [ ] The current database is copied to a pre-restore file before replacement.
- [ ] The store reopens and indexes are rebuilt after a restore.
- [ ] The CLI can restore a named backup.
- [ ] Settings → Data & backups lists snapshots, runs a manual backup, and restores a selection.
- [ ] Settings shows the last backup time and size and warns when the backup is overdue.
- [ ] Tests cover a restore round-trip, the pre-restore copy, and index rebuild.
