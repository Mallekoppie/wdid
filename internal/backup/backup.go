// Package backup writes, verifies and prunes point-in-time snapshots of the
// wdid BoltDB database.
package backup

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"go.uber.org/zap"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

const (
	// DefaultInterval is how often a scheduled snapshot runs.
	DefaultInterval = 6 * time.Hour
	// DefaultRetention is how many scheduled snapshots are kept.
	DefaultRetention = 30
	// DefaultDirName is the backup directory used when none is configured.
	DefaultDirName = "backups"

	tempPattern = ".wdid-snapshot-*.tmp"
	timeLayout  = "20060102T150405Z"
)

// Snapshot files are named wdid-<UTC timestamp>Z[-<n>][-manual].db. Only files
// matching this pattern are considered snapshots; every other file in the
// backup directory is left alone by retention.
var snapshotPattern = regexp.MustCompile(`^wdid-(\d{8}T\d{6}Z)(?:-(\d+))?(-manual)?\.db$`)

// Kind distinguishes an automatic snapshot from a manual one. Manual snapshots
// are never deleted by retention.
type Kind string

const (
	// KindScheduled is an automatic snapshot created by the scheduler.
	KindScheduled Kind = "scheduled"
	// KindManual is a snapshot the user asked for.
	KindManual Kind = "manual"
)

// Config is the instance-wide snapshot configuration.
type Config struct {
	Dir       string
	Interval  time.Duration
	Retention int
}

// Normalize fills defaults for missing or non-positive fields.
func (c Config) Normalize() Config {
	c.Dir = strings.TrimSpace(c.Dir)
	if c.Dir == "" {
		c.Dir = DefaultDirName
	}
	if c.Interval <= 0 {
		c.Interval = DefaultInterval
	}
	if c.Retention <= 0 {
		c.Retention = DefaultRetention
	}
	return c
}

// FromSettings overlays an account's persisted backup preferences on fallback.
// Empty or non-positive preferences keep the fallback value, so the service
// defaults apply until the user configures something else.
func FromSettings(settings domain.Settings, fallback Config) Config {
	config := fallback
	if trimmed := strings.TrimSpace(settings.BackupDirectory); trimmed != "" {
		config.Dir = trimmed
	}
	if settings.BackupIntervalHours > 0 {
		config.Interval = time.Duration(settings.BackupIntervalHours) * time.Hour
	}
	if settings.BackupRetention > 0 {
		config.Retention = settings.BackupRetention
	}
	return config.Normalize()
}

// EnsureDirectory creates dir when it is missing and verifies the service can
// write a file there. A relative or unusable path is reported as a
// backupDirectory field error so an administrator's typo fails at save time
// instead of at the next snapshot. The write probe is removed again.
func EnsureDirectory(dir string) error {
	dir = strings.TrimSpace(dir)
	if !filepath.IsAbs(dir) {
		return domain.ValidationError{Field: "backupDirectory", Message: "must be an absolute path"}
	}
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return domain.ValidationError{Field: "backupDirectory", Message: fmt.Sprintf("cannot create the directory: %v", err)}
	}

	probe, err := os.CreateTemp(dir, ".wdid-write-check-*")
	if err != nil {
		return domain.ValidationError{Field: "backupDirectory", Message: fmt.Sprintf("is not writable: %v", err)}
	}
	probePath := probe.Name()
	if err := probe.Close(); err != nil {
		_ = os.Remove(probePath)
		return domain.ValidationError{Field: "backupDirectory", Message: fmt.Sprintf("is not writable: %v", err)}
	}
	if err := os.Remove(probePath); err != nil {
		return domain.ValidationError{Field: "backupDirectory", Message: fmt.Sprintf("is not writable: %v", err)}
	}
	return nil
}

// Snapshot describes one snapshot file on disk.
type Snapshot struct {
	Name      string
	Path      string
	CreatedAt time.Time
	Size      int64
	Kind      Kind
	counter   int
}

// Manual reports whether the snapshot was taken on demand.
func (s Snapshot) Manual() bool { return s.Kind == KindManual }

// Status is the backup state shown in Settings and by the CLI.
type Status struct {
	Directory        string
	Interval         time.Duration
	Retention        int
	LastBackupAt     time.Time
	LastBackupSize   int64
	LastBackupName   string
	LastBackupManual bool
	Overdue          bool
	NextDueAt        time.Time
	ScheduledCount   int
	ManualCount      int
}

// Snapshotter writes a consistent database copy to w. *store.Store implements
// it through a read transaction.
type Snapshotter interface {
	Snapshot(w io.Writer) error
}

// Restorer replaces the live database with a verified snapshot. *store.Store
// implements it by copying the current database aside, swapping the snapshot
// in, reopening and rebuilding indexes.
type Restorer interface {
	Restore(snapshotPath string) (store.RestoreResult, error)
}

var (
	// ErrSnapshotNotFound is returned when a restore names a file that is not
	// a snapshot in the backup directory.
	ErrSnapshotNotFound = errors.New("backup snapshot not found")
	// ErrRestoreUnsupported is returned when the manager was built with a
	// snapshotter that cannot restore (for example a test double).
	ErrRestoreUnsupported = errors.New("this backup manager cannot restore the database")
)

// Option customises a Manager.
type Option func(*Manager)

// WithClock replaces the clock used for names and due calculations.
func WithClock(now func() time.Time) Option {
	return func(manager *Manager) {
		if now != nil {
			manager.now = now
		}
	}
}

// WithLogger sets the logger used by the background scheduler.
func WithLogger(logger *zap.Logger) Option {
	return func(manager *Manager) {
		if logger != nil {
			manager.logger = logger
		}
	}
}

// Manager creates, verifies, lists and prunes snapshots. The configuration is
// mutable because Settings can change it at runtime; the scheduler re-reads it
// at every interval.
type Manager struct {
	snapshotter Snapshotter
	restorer    Restorer
	now         func() time.Time
	logger      *zap.Logger

	mu  sync.Mutex
	cfg Config
	// wake lets Configure reschedule a running scheduler immediately instead of
	// waiting out the interval that was already sleeping.
	wake chan struct{}
}

// New builds a Manager. The directory is created on the first snapshot. When
// the snapshotter can also restore, the same manager exposes restore; fakes and
// embedders that only implement Snapshotter report ErrRestoreUnsupported.
func New(snapshotter Snapshotter, config Config, options ...Option) *Manager {
	manager := &Manager{
		snapshotter: snapshotter,
		now:         time.Now,
		logger:      zap.NewNop(),
		cfg:         config.Normalize(),
		wake:        make(chan struct{}, 1),
	}
	if restorer, ok := snapshotter.(Restorer); ok {
		manager.restorer = restorer
	}
	for _, option := range options {
		option(manager)
	}
	return manager
}

// Config returns the current snapshot configuration.
func (m *Manager) Config() Config {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.cfg
}

// Configure replaces the snapshot configuration and wakes the scheduler so a
// changed interval or directory applies to the next snapshot without a restart.
func (m *Manager) Configure(config Config) {
	m.mu.Lock()
	m.cfg = config.Normalize()
	m.mu.Unlock()

	select {
	case m.wake <- struct{}{}:
	default:
		// A wake-up is already pending; the scheduler re-reads the config when
		// it handles that one.
	}
}

// Create writes a snapshot inside a read transaction, fsyncs it, verifies it
// read-only and only then renames it to its final name. The temporary file
// lives in the backup directory, so the rename is atomic.
func (m *Manager) Create(kind Kind) (Snapshot, error) {
	if kind != KindScheduled && kind != KindManual {
		return Snapshot{}, fmt.Errorf("unknown snapshot kind %q", kind)
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	config := m.cfg
	if err := os.MkdirAll(config.Dir, 0o750); err != nil {
		return Snapshot{}, fmt.Errorf("create backup directory: %w", err)
	}

	temp, err := os.CreateTemp(config.Dir, tempPattern)
	if err != nil {
		return Snapshot{}, fmt.Errorf("create snapshot temp file: %w", err)
	}
	tempPath := temp.Name()
	cleanup := func() {
		temp.Close()
		os.Remove(tempPath)
	}

	if err := m.snapshotter.Snapshot(temp); err != nil {
		cleanup()
		return Snapshot{}, fmt.Errorf("write snapshot: %w", err)
	}
	if err := temp.Sync(); err != nil {
		cleanup()
		return Snapshot{}, fmt.Errorf("sync snapshot: %w", err)
	}
	if err := temp.Close(); err != nil {
		os.Remove(tempPath)
		return Snapshot{}, fmt.Errorf("close snapshot: %w", err)
	}

	// Verify before reporting success. The file is opened read-only and its
	// schema version is read, so a truncated or foreign file never becomes a
	// visible backup.
	if _, err := store.VerifySnapshot(tempPath); err != nil {
		os.Remove(tempPath)
		return Snapshot{}, fmt.Errorf("verify snapshot: %w", err)
	}

	now := m.now().UTC()
	destination, err := uniquePath(config.Dir, now, kind)
	if err != nil {
		os.Remove(tempPath)
		return Snapshot{}, err
	}
	if err := os.Rename(tempPath, destination); err != nil {
		os.Remove(tempPath)
		return Snapshot{}, fmt.Errorf("install snapshot: %w", err)
	}
	syncDirectory(config.Dir)

	info, err := os.Stat(destination)
	if err != nil {
		return Snapshot{}, fmt.Errorf("stat snapshot: %w", err)
	}

	snapshot, ok := parseSnapshot(filepath.Base(destination))
	if !ok {
		return Snapshot{}, fmt.Errorf("snapshot name %q is not recognised", filepath.Base(destination))
	}
	snapshot.Path = destination
	snapshot.Size = info.Size()
	return snapshot, nil
}

// List returns every snapshot in the configured directory, newest first.
func (m *Manager) List() ([]Snapshot, error) {
	return listSnapshots(m.Config())
}

// Restore replaces the live database with the named snapshot. The name is a
// snapshot basename from List or a path to one. The snapshot is verified before
// the live database changes, and the current database is preserved as a
// pre-restore file.
func (m *Manager) Restore(name string) (Snapshot, store.RestoreResult, error) {
	snapshot, err := m.resolveSnapshot(name)
	if err != nil {
		return Snapshot{}, store.RestoreResult{}, err
	}

	// Serialise against Create so a snapshot cannot be written while the
	// database is being replaced.
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.restorer == nil {
		return Snapshot{}, store.RestoreResult{}, ErrRestoreUnsupported
	}

	// Verify again under the lock: the file swapped in must be the one that was
	// just checked. store.Restore verifies too, so an invalid file never
	// reaches the database even when this call is bypassed.
	if _, err := store.VerifySnapshot(snapshot.Path); err != nil {
		return Snapshot{}, store.RestoreResult{}, fmt.Errorf("verify snapshot: %w", err)
	}

	result, err := m.restorer.Restore(snapshot.Path)
	if err != nil {
		return Snapshot{}, store.RestoreResult{}, err
	}
	return snapshot, result, nil
}

// resolveSnapshot accepts a snapshot basename or an explicit path and returns
// the parsed snapshot. Files that are not wdid snapshots are refused.
func (m *Manager) resolveSnapshot(name string) (Snapshot, error) {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return Snapshot{}, fmt.Errorf("%w: a snapshot name is required", ErrSnapshotNotFound)
	}

	path := trimmed
	if !filepath.IsAbs(path) && !strings.ContainsRune(path, filepath.Separator) {
		path = filepath.Join(m.Config().Dir, trimmed)
	}

	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) {
		return Snapshot{}, fmt.Errorf("%w: %s", ErrSnapshotNotFound, trimmed)
	}
	if err != nil {
		return Snapshot{}, fmt.Errorf("inspect snapshot %s: %w", trimmed, err)
	}
	if info.IsDir() {
		return Snapshot{}, fmt.Errorf("%w: %s is a directory", ErrSnapshotNotFound, trimmed)
	}

	snapshot, ok := parseSnapshot(filepath.Base(path))
	if !ok {
		return Snapshot{}, fmt.Errorf("%w: %s is not a wdid snapshot", ErrSnapshotNotFound, trimmed)
	}
	snapshot.Path = path
	snapshot.Size = info.Size()
	return snapshot, nil
}

// Status reports the latest backup, the size, and whether the schedule is
// overdue. A workspace that has never had a scheduled snapshot is overdue.
func (m *Manager) Status() (Status, error) {
	config := m.Config()
	snapshots, err := listSnapshots(config)
	if err != nil {
		return Status{}, err
	}

	status := Status{
		Directory: config.Dir,
		Interval:  config.Interval,
		Retention: config.Retention,
		Overdue:   true,
	}

	var latestScheduled *Snapshot
	for index := range snapshots {
		snapshot := snapshots[index]
		if snapshot.Kind == KindManual {
			status.ManualCount++
		} else {
			status.ScheduledCount++
			if latestScheduled == nil {
				latestScheduled = &snapshot
			}
		}
	}

	if len(snapshots) > 0 {
		latest := snapshots[0]
		status.LastBackupAt = latest.CreatedAt
		status.LastBackupSize = latest.Size
		status.LastBackupName = latest.Name
		status.LastBackupManual = latest.Manual()
	}

	if latestScheduled != nil {
		status.NextDueAt = latestScheduled.CreatedAt.Add(config.Interval)
		status.Overdue = m.now().UTC().After(status.NextDueAt)
	}

	return status, nil
}

// Prune deletes the oldest scheduled snapshots beyond the retention count. It
// never deletes a manual snapshot, and it ignores files it did not create.
func (m *Manager) Prune() (int, error) {
	config := m.Config()
	snapshots, err := listSnapshots(config)
	if err != nil {
		return 0, err
	}

	scheduled := make([]Snapshot, 0, len(snapshots))
	for _, snapshot := range snapshots {
		if snapshot.Kind == KindScheduled {
			scheduled = append(scheduled, snapshot)
		}
	}
	if len(scheduled) <= config.Retention {
		return 0, nil
	}

	removed := 0
	for _, snapshot := range scheduled[config.Retention:] {
		if err := os.Remove(snapshot.Path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return removed, fmt.Errorf("remove snapshot %s: %w", snapshot.Name, err)
		}
		removed++
	}
	return removed, nil
}

// RunScheduled takes a snapshot when the schedule is overdue and prunes old
// scheduled snapshots. It reports whether a snapshot was written, so startup
// can make one immediately when the last backup is too old.
func (m *Manager) RunScheduled() (Snapshot, bool, error) {
	status, err := m.Status()
	if err != nil {
		return Snapshot{}, false, err
	}
	if !status.Overdue {
		return Snapshot{}, false, nil
	}

	snapshot, err := m.Create(KindScheduled)
	if err != nil {
		return Snapshot{}, false, err
	}
	if _, err := m.Prune(); err != nil {
		return snapshot, true, err
	}
	return snapshot, true, nil
}

// Run checks the schedule once at startup and then at every interval until the
// context is cancelled. The interval is re-read after every tick and whenever
// Configure wakes it, so a settings change takes effect without restarting the
// service and without waiting out the previous interval.
func (m *Manager) Run(ctx context.Context) {
	m.runOnce()
	for {
		interval := m.Config().Interval
		timer := time.NewTimer(interval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
			m.runOnce()
		case <-m.wake:
			timer.Stop()
		}
	}
}

func (m *Manager) runOnce() {
	snapshot, created, err := m.RunScheduled()
	if err != nil {
		m.logger.Error("scheduled backup failed", zap.Error(err))
		return
	}
	if created {
		m.logger.Info("scheduled backup created",
			zap.String("path", snapshot.Path),
			zap.Int64("bytes", snapshot.Size))
	}
}

func listSnapshots(config Config) ([]Snapshot, error) {
	entries, err := os.ReadDir(config.Dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read backup directory: %w", err)
	}

	snapshots := make([]Snapshot, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		snapshot, ok := parseSnapshot(entry.Name())
		if !ok {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			return nil, fmt.Errorf("inspect snapshot %s: %w", entry.Name(), err)
		}
		snapshot.Path = filepath.Join(config.Dir, entry.Name())
		snapshot.Size = info.Size()
		snapshots = append(snapshots, snapshot)
	}

	sort.Slice(snapshots, func(i, j int) bool {
		if !snapshots[i].CreatedAt.Equal(snapshots[j].CreatedAt) {
			return snapshots[i].CreatedAt.After(snapshots[j].CreatedAt)
		}
		if snapshots[i].counter != snapshots[j].counter {
			return snapshots[i].counter > snapshots[j].counter
		}
		return snapshots[i].Name > snapshots[j].Name
	})

	return snapshots, nil
}

func parseSnapshot(name string) (Snapshot, bool) {
	matches := snapshotPattern.FindStringSubmatch(name)
	if matches == nil {
		return Snapshot{}, false
	}

	createdAt, err := time.Parse(timeLayout, matches[1])
	if err != nil {
		return Snapshot{}, false
	}

	counter := 0
	if matches[2] != "" {
		counter, err = strconv.Atoi(matches[2])
		if err != nil {
			return Snapshot{}, false
		}
	}

	kind := KindScheduled
	if matches[3] != "" {
		kind = KindManual
	}

	return Snapshot{
		Name:      name,
		CreatedAt: createdAt,
		Kind:      kind,
		counter:   counter,
	}, true
}

func uniquePath(dir string, now time.Time, kind Kind) (string, error) {
	for counter := 1; counter <= 1000; counter++ {
		path := filepath.Join(dir, snapshotName(now, kind, counter))
		_, err := os.Stat(path)
		switch {
		case errors.Is(err, os.ErrNotExist):
			return path, nil
		case err != nil:
			return "", fmt.Errorf("inspect snapshot destination: %w", err)
		}
	}
	return "", errors.New("could not find a free snapshot name")
}

func snapshotName(now time.Time, kind Kind, counter int) string {
	name := "wdid-" + now.UTC().Format(timeLayout)
	if counter > 1 {
		name += "-" + strconv.Itoa(counter)
	}
	if kind == KindManual {
		name += "-manual"
	}
	return name + ".db"
}

// syncDirectory persists the rename itself. It is best-effort: the file is
// already durable, and some filesystems reject directory fsync.
func syncDirectory(dir string) {
	handle, err := os.Open(dir)
	if err != nil {
		return
	}
	defer handle.Close()
	_ = handle.Sync()
}
