package backup_test

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"go.etcd.io/bbolt"

	"github.com/Mallekoppie/wdid/internal/backup"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// fakeSnapshotter writes bytes that stand in for a database copy.
type fakeSnapshotter struct {
	data []byte
	err  error
}

func (f fakeSnapshotter) Snapshot(w io.Writer) error {
	if f.err != nil {
		return f.err
	}
	_, err := w.Write(f.data)
	return err
}

// validDatabaseBytes builds a real BoltDB file with the instance metadata
// bucket, so verification exercises the same code path as production.
func validDatabaseBytes(t *testing.T) []byte {
	t.Helper()

	path := filepath.Join(t.TempDir(), "valid.db")
	database, err := bbolt.Open(path, 0o600, nil)
	if err != nil {
		t.Fatalf("open valid database: %v", err)
	}
	if err := database.Update(func(tx *bbolt.Tx) error {
		bucket, err := tx.CreateBucketIfNotExists([]byte("sys:meta"))
		if err != nil {
			return err
		}
		return bucket.Put([]byte("schema_version"), []byte("1"))
	}); err != nil {
		t.Fatalf("seed valid database: %v", err)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close valid database: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read valid database: %v", err)
	}
	return data
}

type testClock struct {
	now time.Time
}

func (c *testClock) Now() time.Time { return c.now }

func (c *testClock) Advance(duration time.Duration) { c.now = c.now.Add(duration) }

func newManager(t *testing.T, dir string, retention int) (*backup.Manager, *testClock) {
	t.Helper()

	clock := &testClock{now: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)}
	manager := backup.New(
		fakeSnapshotter{data: validDatabaseBytes(t)},
		backup.Config{Dir: dir, Interval: 6 * time.Hour, Retention: retention},
		backup.WithClock(clock.Now),
	)
	return manager, clock
}

func TestCreateWritesSyncsVerifiesAndRenames(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager, clock := newManager(t, dir, 30)

	snapshot, err := manager.Create(backup.KindScheduled)
	if err != nil {
		t.Fatalf("create snapshot: %v", err)
	}
	if snapshot.Name != "wdid-20260101T000000Z.db" {
		t.Fatalf("name = %q, want the UTC timestamp name", snapshot.Name)
	}
	if snapshot.Manual() {
		t.Fatal("scheduled snapshot reported as manual")
	}
	if snapshot.Size <= 0 {
		t.Fatalf("size = %d, want the file size", snapshot.Size)
	}
	if !snapshot.CreatedAt.Equal(clock.now) {
		t.Fatalf("created at = %s, want %s", snapshot.CreatedAt, clock.now)
	}

	version, err := store.VerifySnapshot(snapshot.Path)
	if err != nil {
		t.Fatalf("verify installed snapshot: %v", err)
	}
	if version != 1 {
		t.Fatalf("schema version = %d, want 1", version)
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read backup directory: %v", err)
	}
	if len(entries) != 1 || entries[0].Name() != snapshot.Name {
		t.Fatalf("backup directory = %v, want only the installed snapshot", entries)
	}
}

func TestCreateRejectsUnverifiableSnapshot(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager := backup.New(
		fakeSnapshotter{data: []byte("this is not a bolt database")},
		backup.Config{Dir: dir},
	)

	if _, err := manager.Create(backup.KindScheduled); err == nil {
		t.Fatal("expected an unverifiable snapshot to fail")
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read backup directory: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("backup directory = %v, want no temp or snapshot files", entries)
	}
}

func TestCreateReportsWriterFailure(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager := backup.New(
		fakeSnapshotter{err: io.ErrClosedPipe},
		backup.Config{Dir: dir},
	)

	if _, err := manager.Create(backup.KindManual); err == nil {
		t.Fatal("expected a writer failure to fail the snapshot")
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read backup directory: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("backup directory = %v, want no temp files", entries)
	}
}

func TestRetentionKeepsNewestScheduledAndNeverDeletesManual(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager, clock := newManager(t, dir, 3)

	manual, err := manager.Create(backup.KindManual)
	if err != nil {
		t.Fatalf("create manual snapshot: %v", err)
	}

	for index := 0; index < 5; index++ {
		if index > 0 {
			clock.Advance(time.Hour)
		}
		if _, err := manager.Create(backup.KindScheduled); err != nil {
			t.Fatalf("create scheduled snapshot %d: %v", index, err)
		}
	}

	removed, err := manager.Prune()
	if err != nil {
		t.Fatalf("prune: %v", err)
	}
	if removed != 2 {
		t.Fatalf("removed = %d, want the two oldest scheduled snapshots", removed)
	}

	snapshots, err := manager.List()
	if err != nil {
		t.Fatalf("list: %v", err)
	}

	var scheduled, manuals []backup.Snapshot
	for _, snapshot := range snapshots {
		if snapshot.Manual() {
			manuals = append(manuals, snapshot)
			continue
		}
		scheduled = append(scheduled, snapshot)
	}

	if len(scheduled) != 3 {
		t.Fatalf("scheduled snapshots = %d, want the newest 3", len(scheduled))
	}
	if scheduled[0].CreatedAt.Hour() != 4 || scheduled[2].CreatedAt.Hour() != 2 {
		t.Fatalf("kept scheduled snapshots = %v, want hours 4, 3 and 2", scheduled)
	}
	if len(manuals) != 1 {
		t.Fatalf("manual snapshots = %d, want the manual snapshot kept", len(manuals))
	}
	if manuals[0].Name != manual.Name {
		t.Fatalf("manual snapshot = %q, want %q", manuals[0].Name, manual.Name)
	}
}

func TestPruneIgnoresForeignFiles(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager, clock := newManager(t, dir, 1)

	foreign := filepath.Join(dir, "notes.txt")
	if err := os.MkdirAll(dir, 0o750); err != nil {
		t.Fatalf("create backup directory: %v", err)
	}
	if err := os.WriteFile(foreign, []byte("keep me"), 0o600); err != nil {
		t.Fatalf("write foreign file: %v", err)
	}

	for index := 0; index < 2; index++ {
		if index > 0 {
			clock.Advance(time.Hour)
		}
		if _, err := manager.Create(backup.KindScheduled); err != nil {
			t.Fatalf("create scheduled snapshot: %v", err)
		}
	}

	if _, err := manager.Prune(); err != nil {
		t.Fatalf("prune: %v", err)
	}
	if _, err := os.Stat(foreign); err != nil {
		t.Fatalf("foreign file was removed: %v", err)
	}
}

func TestStatusReportsLastBackupSizeAndOverdue(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager, clock := newManager(t, dir, 30)

	status, err := manager.Status()
	if err != nil {
		t.Fatalf("status on empty directory: %v", err)
	}
	if !status.Overdue {
		t.Fatal("an empty backup directory must be overdue")
	}
	if !status.LastBackupAt.IsZero() {
		t.Fatalf("last backup = %s, want never", status.LastBackupAt)
	}

	snapshot, err := manager.Create(backup.KindScheduled)
	if err != nil {
		t.Fatalf("create snapshot: %v", err)
	}

	clock.Advance(time.Hour)
	status, err = manager.Status()
	if err != nil {
		t.Fatalf("status: %v", err)
	}
	if status.Overdue {
		t.Fatal("a one-hour-old snapshot with a six-hour interval is not overdue")
	}
	if !status.LastBackupAt.Equal(snapshot.CreatedAt) {
		t.Fatalf("last backup = %s, want %s", status.LastBackupAt, snapshot.CreatedAt)
	}
	if status.LastBackupSize != snapshot.Size || status.LastBackupSize <= 0 {
		t.Fatalf("last backup size = %d, want %d", status.LastBackupSize, snapshot.Size)
	}
	if !status.NextDueAt.Equal(snapshot.CreatedAt.Add(6 * time.Hour)) {
		t.Fatalf("next due = %s, want six hours after the snapshot", status.NextDueAt)
	}
	if status.ScheduledCount != 1 || status.ManualCount != 0 {
		t.Fatalf("counts = %d scheduled, %d manual", status.ScheduledCount, status.ManualCount)
	}

	// A manual backup is the latest backup but does not satisfy the schedule.
	if _, err := manager.Create(backup.KindManual); err != nil {
		t.Fatalf("create manual snapshot: %v", err)
	}
	clock.Advance(6 * time.Hour)
	status, err = manager.Status()
	if err != nil {
		t.Fatalf("status after the manual snapshot: %v", err)
	}
	if !status.Overdue {
		t.Fatal("a manual snapshot must not reset the scheduled overdue state")
	}
	if !status.LastBackupManual {
		t.Fatal("the most recent backup is the manual one")
	}
}

func TestRunScheduledCreatesAtStartupWhenOverdue(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager, clock := newManager(t, dir, 30)

	snapshot, created, err := manager.RunScheduled()
	if err != nil {
		t.Fatalf("run scheduled: %v", err)
	}
	if !created {
		t.Fatal("an empty backup directory must produce a startup snapshot")
	}
	if snapshot.Kind != backup.KindScheduled {
		t.Fatalf("kind = %q, want scheduled", snapshot.Kind)
	}

	clock.Advance(time.Hour)
	if _, created, err := manager.RunScheduled(); err != nil || created {
		t.Fatalf("fresh schedule created=%v err=%v, want no snapshot", created, err)
	}

	clock.Advance(6 * time.Hour)
	if _, created, err := manager.RunScheduled(); err != nil || !created {
		t.Fatalf("overdue schedule created=%v err=%v, want a snapshot", created, err)
	}
}

func TestRunSnapshotsAtTheConfiguredInterval(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager := backup.New(
		fakeSnapshotter{data: validDatabaseBytes(t)},
		backup.Config{Dir: dir, Interval: 20 * time.Millisecond, Retention: 100},
	)

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		manager.Run(ctx)
		close(done)
	}()
	defer func() {
		cancel()
		<-done
	}()

	deadline := time.Now().Add(5 * time.Second)
	for {
		snapshots, err := manager.List()
		if err != nil {
			t.Fatalf("list snapshots: %v", err)
		}
		if len(snapshots) >= 2 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("scheduled snapshots = %d, want the startup snapshot and an interval snapshot", len(snapshots))
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func TestManagerRestoresNamedSnapshot(t *testing.T) {
	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid.db"),
		AuthMode:             config.AuthModeServer,
		BootstrapSecret:      "test-registration-secret",
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}
	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		_ = database.Close()
	})

	first := domain.User{
		ID:          domain.NewID(),
		Email:       "before@example.com",
		DisplayName: "Before",
		Role:        domain.RoleAdmin,
		CreatedAt:   time.Now().UTC(),
	}
	first.Normalize()
	if err := database.CreateUser(first); err != nil {
		t.Fatalf("create first user: %v", err)
	}

	manager := backup.New(database, backup.Config{Dir: filepath.Join(t.TempDir(), "backups")})
	snapshot, err := manager.Create(backup.KindManual)
	if err != nil {
		t.Fatalf("create snapshot: %v", err)
	}

	second := domain.User{
		ID:          domain.NewID(),
		Email:       "after@example.com",
		DisplayName: "After",
		Role:        domain.RoleUser,
		CreatedAt:   time.Now().UTC(),
	}
	second.Normalize()
	if err := database.CreateUser(second); err != nil {
		t.Fatalf("create second user: %v", err)
	}

	restored, result, err := manager.Restore(snapshot.Name)
	if err != nil {
		t.Fatalf("restore by name: %v", err)
	}
	if restored.Name != snapshot.Name {
		t.Fatalf("restored name = %q, want %q", restored.Name, snapshot.Name)
	}
	if result.PreRestorePath == "" {
		t.Fatal("restore did not report a pre-restore copy")
	}
	if _, err := os.Stat(result.PreRestorePath); err != nil {
		t.Fatalf("pre-restore copy missing: %v", err)
	}
	if _, err := database.UserByID(second.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("post-snapshot user after restore error = %v, want ErrNotFound", err)
	}
	if _, err := database.UserByID(first.ID); err != nil {
		t.Fatalf("pre-snapshot user after restore: %v", err)
	}

	if _, _, err := manager.Restore("wdid-29990101T000000Z.db"); !errors.Is(err, backup.ErrSnapshotNotFound) {
		t.Fatalf("missing snapshot error = %v, want ErrSnapshotNotFound", err)
	}
	if _, _, err := manager.Restore("notes.txt"); !errors.Is(err, backup.ErrSnapshotNotFound) {
		t.Fatalf("foreign file error = %v, want ErrSnapshotNotFound", err)
	}
}

func TestManagerRestoreRequiresRestorer(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "backups")
	manager, _ := newManager(t, dir, 30)

	snapshot, err := manager.Create(backup.KindManual)
	if err != nil {
		t.Fatalf("create snapshot: %v", err)
	}
	if _, _, err := manager.Restore(snapshot.Name); !errors.Is(err, backup.ErrRestoreUnsupported) {
		t.Fatalf("restore error = %v, want ErrRestoreUnsupported", err)
	}
}

func TestManagerSnapshotsTheLiveStore(t *testing.T) {
	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid.db"),
		AuthMode:             config.AuthModeServer,
		BootstrapSecret:      "test-registration-secret",
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}
	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer database.Close()

	manager := backup.New(database, backup.Config{Dir: filepath.Join(t.TempDir(), "backups")})
	snapshot, err := manager.Create(backup.KindScheduled)
	if err != nil {
		t.Fatalf("create snapshot: %v", err)
	}

	version, err := store.VerifySnapshot(snapshot.Path)
	if err != nil {
		t.Fatalf("verify snapshot: %v", err)
	}
	if version != 1 {
		t.Fatalf("schema version = %d, want 1", version)
	}
}
