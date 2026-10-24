# 21: Backup snapshots

**What to build:** The service can take consistent, point-in-time snapshots of the database on a schedule and on demand, verify each snapshot before reporting success, and retain the newest scheduled snapshots. Manual snapshots are never deleted automatically, and the CLI exposes a manual backup.

**Blocked by:** 03 (Category taxonomy data core)

**Status:** ready-for-human

- [x] A snapshot is written from a read transaction to a temp file, synced, and atomically renamed.
- [x] A snapshot is verified by opening it read-only and reading the schema version before success is reported.
- [x] Scheduled snapshots run at the configured interval, including once at startup when overdue.
- [x] Retention keeps the newest configured number of scheduled snapshots and never deletes a manual one.
- [x] The CLI can take a manual backup.
- [x] Backup status reports the last backup time and size and whether it is overdue.
- [x] Tests cover snapshot creation, verification, retention, and the manual/automatic split.

## Comments

Implemented the server-side backup slice end to end: snapshot creation/verification,
scheduling, retention, CLI, and the Connect surface issue 22 will consume.

**Design**

- `internal/backup` owns snapshot files and scheduling. `Manager.Create` runs
  `store.Store.Snapshot` (goslow's `BoltDb.Snapshot`, i.e. `db.View` +
  `tx.WriteTo`) into `os.CreateTemp` in the configured backup directory,
  calls `Sync`, closes, verifies read-only, then `os.Rename`s into place and
  best-effort fsyncs the directory. Temporary files never live outside the
  backup directory and are removed on every failure path.
- `internal/store/snapshot.go` adds `Store.Snapshot` and `VerifySnapshot`.
  Verification opens the file with `bbolt.Options{ReadOnly: true}`, reads
  `sys:meta.schema_version`, rejects a missing/non-positive version, and is
  called before the snapshot is renamed or reported.
- Names follow the plan: `wdid-YYYYMMDDTHHMMSSZ.db` for scheduled snapshots,
  with `-manual` appended for manual ones and a numeric suffix on same-second
  collisions. Retention only matches that pattern, so foreign files and
  manual snapshots are never removed.
- `Manager.Run` checks the schedule once at startup (overdue when there is no
  scheduled snapshot or the newest is older than the interval), then wakes at
  each interval. The interval is re-read every tick, so a settings change takes
  effect without a restart. `main` starts it on the service context.
- Backups are instance-wide. Defaults come from config (`WDID_BACKUP_DIR`,
  `WDID_BACKUP_INTERVAL`, `WDID_BACKUP_RETENTION`; dir defaults to
  `<db dir>/backups`, interval 6h, retention 30). `cmd/wdid.newBackupManager`
  overlays the primary account's persisted backup settings at startup, and
  `UpdateSettings` applies the saved values to the live manager.
- CLI: `wdid backup` takes a manual snapshot; `wdid backup status` and
  `wdid backup list` expose the status/list surface. `wdid restore` remains
  out of scope for this issue.
- RPC surface for issue 22: `SettingsService.BackupNow`, `GetBackupStatus`, and
  `ListBackups` (with `Backup` and `BackupStatus` messages). Status includes the
  last backup time/size/manual flag, overdue, next due time, directory,
  interval, retention and scheduled/manual counts. No Flutter UI was added.

**Per-checkbox evidence**

1. Read transaction, temp file, fsync, atomic rename:
   `internal/backup/backup.go` (`Manager.Create`), `internal/store/snapshot.go`
   (`Store.Snapshot`); `internal/backup/backup_test.go`
   `TestCreateWritesSyncsVerifiesAndRenames`, `TestCreateReportsWriterFailure`;
   `internal/store/snapshot_test.go` `TestSnapshotCopiesCommittedDataAndVerifies`;
   `internal/backup/backup_test.go` `TestManagerSnapshotsTheLiveStore`.
2. Read-only verification before success: `internal/store/snapshot.go`
   (`VerifySnapshot`), called in `Manager.Create` before `os.Rename`;
   `TestCreateRejectsUnverifiableSnapshot`,
   `TestVerifySnapshotRejectsNonDatabase`,
   `TestVerifySnapshotRejectsMissingSchemaVersion`.
3. Scheduled interval and startup catch-up: `Manager.Run`, `Manager.RunScheduled`,
   `Manager.Status`; wired in `cmd/wdid/main.go`. Tests
   `TestRunScheduledCreatesAtStartupWhenOverdue`,
   `TestRunSnapshotsAtTheConfiguredInterval`, plus
   `TestBackupStatusReportsConfiguredDirectoryAndOverdue`.
4. Retention: `Manager.Prune` (scheduled only, pattern-matched files);
   `TestRetentionKeepsNewestScheduledAndNeverDeletesManual`,
   `TestPruneIgnoresForeignFiles`.
5. Manual CLI backup: `cmd/wdid/backup.go`, dispatch in `cmd/wdid/main.go`;
   `cmd/wdid/backup_test.go` `TestBackupCommandCreatesManualSnapshot`.
6. Backup status: `Manager.Status`, `SettingsService.GetBackupStatus`, CLI
   `wdid backup status`; `TestStatusReportsLastBackupSizeAndOverdue`,
   `internal/rpc/backup_service_test.go`
   `TestBackupStatusReportsConfiguredDirectoryAndOverdue`.
7. Test coverage for creation/verification/retention/manual-automatic split:
   the tests above plus `internal/rpc/backup_service_test.go`
   (`TestBackupNowCreatesManualSnapshotAndReportsStatus`,
   `TestBackupRPCsRequireAuthentication`) and
   `TestUpdateSettingsReconfiguresBackups`.

**Gate**

`make check` from `/workspaces/wdid`: exit 0 (proto-check, `go vet`, Go tests,
`flutter analyze`, Flutter tests all pass).

**Follow-up: backups are admin-only (human decision)**

Decision: backups are admin-only for all access. This resolves the question
raised in the previous revision of this issue.

- `internal/rpc/identity.go` adds `backupAdminFromContext`. It resolves the
  caller from the verified token and requires `domain.RoleAdmin`; the role comes
  from the account record, so local JWTs and OIDC-provisioned accounts behave
  alike.
- `internal/rpc/errors.go` adds `ErrBackupsAdminOnly`, mapped to
  `connect.CodePermissionDenied`, with the explanatory message "backups are
  managed by an administrator; only an administrator can view or change them".
- `BackupNow`, `GetBackupStatus` and `ListBackups` now require the admin role.
  An authenticated non-admin gets `permission_denied` instead of instance-wide
  backup data. There is no `RestoreBackup` RPC in this codebase; the future
  restore surface must use the same helper. The rule is recorded on the service
  in `internal/contracts/settings.proto`.
- `UpdateSettings` keeps ordinary preferences editable for every account. For a
  non-admin it compares the submitted backup directory, interval and retention
  with the account's current values; any change is denied with the same
  `permission_denied` error. An omitted backup block (empty directory, zero
  interval or retention) is treated as "not supplied", so a member can still
  save timezone, AI, theme and density preferences. The member's stored backup
  values are preserved and are never applied to the live manager; only an
  admin's update calls `backup.Configure`.
- `internal/contracts/settings.proto` documents the admin-only rule. Stubs were
  regenerated with `make proto`; no wire fields changed.
- No Flutter change was needed: the current client has no backup RPC UI (it runs
  on the demo repository). The permission error is the explanatory read-only
  state the future Settings backup panel must surface.

**Gating evidence**

- `internal/rpc/backup_service_test.go`
  `TestBackupRPCsRequireAdmin`: a non-admin is denied `BackupNow`,
  `GetBackupStatus` and `ListBackups` with `permission_denied` and an
  administrator explanation; the denied `BackupNow` writes no snapshot; the
  admin keeps all three calls.
- `TestNonAdminCannotChangeBackupSettings`: the admin configures a custom
  directory, interval and retention; a non-admin is denied changing each field
  and the live admin configuration is unchanged; the member can still call
  `GetSettings`.
- `TestNonAdminCanUpdateNormalSettings`: a member saves normal preferences both
  by round-tripping `GetSettings` and by omitting the backup block; backup
  defaults are preserved and the live configuration stays admin-owned.
- `TestBackupAdminGatingServesGRPCWeb`: the same denials and admin access over
  gRPC-Web.
- `TestBackupNowCreatesManualSnapshotAndReportsStatus`,
  `TestUpdateSettingsReconfiguresBackups` and
  `TestBackupStatusReportsConfiguredDirectoryAndOverdue` still cover the admin
  path unchanged.

**Gate**

`make check` from `/workspaces/wdid`: exit 0 (proto-check, `go vet`, Go tests,
`flutter analyze`, Flutter tests).
