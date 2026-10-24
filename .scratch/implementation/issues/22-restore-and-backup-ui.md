# 22: Restore and backup status UI

**What to build:** A user can restore a chosen backup. Restoring verifies the backup, copies the current database aside, replaces it, reopens the store, and rebuilds indexes. Settings shows the backup status, the snapshot list, manual backup, restore, and an overdue warning.

**Blocked by:** 05 (Settings preferences end-to-end), 21 (Backup snapshots)

**Status:** ready-for-human

- [x] Restore verifies the selected backup before changing anything.
- [x] The current database is copied to a pre-restore file before replacement.
- [x] The store reopens and indexes are rebuilt after a restore.
- [x] The CLI can restore a named backup.
- [x] Settings → Data & backups lists snapshots, runs a manual backup, and restores a selection.
- [x] Settings shows the last backup time and size and warns when the backup is overdue.
- [x] Tests cover a restore round-trip, the pre-restore copy, and index rebuild.

## Comments

Implemented restore end to end: store/backup layer, admin-gated
`RestoreBackup` RPC, `wdid restore <name>` CLI, and the Settings → Data &
backups panel. Stubs were regenerated with `make proto`.

**Restore verifies before changing anything**

- `internal/store/restore.go` (`Store.Restore`) calls `VerifySnapshot` first and
  stages the file next to the database; every failure path before the swap
  leaves the live handle serving the original data.
- `internal/store/snapshot.go` now wraps verification failures in
  `store.ErrInvalidSnapshot`; `internal/rpc/errors.go` maps it to
  `FAILED_PRECONDITION`, while an unknown name (`backup.ErrSnapshotNotFound`)
  maps to `NOT_FOUND`.
- `internal/backup/backup.go` adds `Manager.Restore(name)` (basename or path),
  which resolves only files matching the snapshot pattern and verifies again
  under the manager lock.
- Tests: `TestRestoreRefusesInvalidSnapshotBeforeChangingAnything`
  (`internal/store/restore_test.go`) and
  `TestRestoreBackupRejectsInvalidSelection` (`internal/rpc/backup_service_test.go`,
  empty name → `INVALID_ARGUMENT`, missing name → `NOT_FOUND`, corrupt file →
  `FAILED_PRECONDITION`, database still readable and no pre-restore file).

**Pre-restore copy**

- `Store.Restore` closes writes, copies the current database to
  `wdid-before-restore-<UTC timestamp>.db` next to it (counter suffix on a
  same-second collision), fsyncs it, then renames the staged snapshot into
  place. The path is returned to the RPC/CLI.
- Tests: `TestRestoreRoundTripPreservesPreRestoreDatabase` opens the pre-restore
  file read-only and asserts it contains the account created after the
  snapshot; `TestRestoreBackupRoundTrip` asserts the RPC returns the path and
  the file exists next to `WDID_DB_PATH`; `TestRestoreCommandRestoresNamedSnapshot`
  asserts the CLI prints it.

**Reopen and index rebuild**

- After the swap the store force-closes any handle that a concurrent request may
  have reopened, calls `platform.SetupBoltDB`, runs `ensureMeta`, and calls the
  new unconditional `rebuildEntryIndexes` (`internal/store/seed.go`) rather than
  the version-gated `ensureEntryIndexes`. `Store` now records its `dbPath`
  (`internal/store/store.go`) so it can replace and reopen the file goslow owns.
- Tests: `TestRestoreRebuildsEntryIndexes` deletes the day index from the
  snapshot, restores, and asserts a `LocalDate`-filtered listing returns the
  entry (proves the index was rebuilt, not reused); the round-trip tests also
  read the live store after restore.

**CLI**

- `cmd/wdid/main.go` dispatches `restore`; `runRestore` in `cmd/wdid/backup.go`
  opens the storage-only store, restores by name, and reports the snapshot,
  schema version and pre-restore path. Tests:
  `TestRestoreCommandRestoresNamedSnapshot`, `TestRestoreCommandRequiresName`.

**Settings → Data & backups UI**

- `web/lib/widgets/settings/backups_panel.dart` replaces the old Data card in
  `web/lib/screens/settings_screen.dart`: database/data/backup paths, interval
  and retention, last backup time/size, an overdue warning, the snapshot list
  (manual/scheduled, relative day, size), selection, a confirmation dialog,
  `Restore selected`, `Backup now`, and `Export all data`, with loading, empty,
  error+retry and busy states.
- `SettingsApi`/`SettingsRpc` (`web/lib/data/settings_api.dart`) gain
  `getBackupStatus`, `listBackups`, `backupNow` and `restoreBackup`, mapping the
  generated messages and translating `NOT_FOUND`/`FAILED_PRECONDITION`.
  `AppState` (`web/lib/state/app_state.dart`) owns the list/status, takes a
  manual backup, and after a restore reloads every server-owned view because
  the data may have rolled back.
- Admin gating: `WdidApp`/`AppState` resolve the account role from the auth
  session (`roleCheck`, injectable for tests). A non-admin never calls the
  backup RPCs and sees a lock notice explaining that backups are managed by an
  administrator, while keeping their paths and export. Tests:
  `web/test/settings_backups_test.dart` (admin list/backup/restore and
  confirmation, non-admin read-only state with zero backup calls, overdue
  warning, empty and error/retry states), `web/test/settings_api_test.dart`
  (proto mapping and `pre_restore_path`), `web/test/fake_preferences_api.dart`
  (fake backup surface), `web/test/screens_smoke_test.dart` (updated card title).

**Server protocol coverage**

- `internal/rpc/backup_service_test.go` adds `RestoreBackup` to the
  unauthenticated, non-admin and gRPC-Web denial checks, and to the gRPC-Web
  admin success path, plus the Connect round-trip and invalid-selection tests.
  `internal/backup/backup_test.go` covers restoring a named snapshot through
  the manager and `ErrRestoreUnsupported` for a snapshot-only double.

**Note**

Restore closes the store handle before copying and swapping the file. A
concurrent request in that window either reopens the old file (its write lands
in the replaced inode and is discarded by the restore) or opens the restored
file; the post-swap force-close and reopen guarantees the process serves the
restored file afterwards, even if another request reopened the old inode.
Fully serialising in-flight RPCs during a restore would require a platform-level
hook that does not exist today.

**Gate**

`make check` from `/workspaces/wdid`: exit 0 (proto-check, `go vet`,
`flutter analyze`, `go test ./...`, `flutter test`).
