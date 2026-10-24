package store

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Mallekoppie/goslow/platform"
)

const (
	preRestorePrefix   = "wdid-before-restore-"
	restoreTimeLayout  = "20060102T150405Z"
	restoreTempPattern = ".wdid-restore-*.tmp"
)

// RestoreResult describes a completed restore.
type RestoreResult struct {
	// PreRestorePath is the file that holds the database exactly as it was
	// before the restore.
	PreRestorePath string
	// SchemaVersion is the schema version read from the snapshot.
	SchemaVersion int
}

// Restore replaces the live database with the snapshot at snapshotPath. The
// snapshot is verified before anything changes; the current database is copied
// to a pre-restore file next to it; the verified snapshot is renamed into place
// atomically; the database is reopened; and every user's entry indexes are
// rebuilt. If any step after the swap fails, the pre-restore copy is put back.
func (s *Store) Restore(snapshotPath string) (RestoreResult, error) {
	if strings.TrimSpace(s.dbPath) == "" {
		return RestoreResult{}, errors.New("store has no database path")
	}

	snapshotPath = strings.TrimSpace(snapshotPath)
	if snapshotPath == "" {
		return RestoreResult{}, errors.New("snapshot path is required")
	}
	if filepath.Clean(snapshotPath) == filepath.Clean(s.dbPath) {
		return RestoreResult{}, errors.New("cannot restore the live database over itself")
	}

	// Verification happens before the live handle is touched. An unusable file
	// is refused and the running database keeps serving.
	version, err := VerifySnapshot(snapshotPath)
	if err != nil {
		return RestoreResult{}, fmt.Errorf("verify snapshot: %w", err)
	}

	// Stage the snapshot next to the live database. The rename below is then
	// atomic because both paths live on the same filesystem.
	stagedPath, err := stageFile(snapshotPath, filepath.Dir(s.dbPath))
	if err != nil {
		return RestoreResult{}, fmt.Errorf("stage snapshot: %w", err)
	}
	defer os.Remove(stagedPath)

	result := RestoreResult{SchemaVersion: version}

	// Stop writes before copying or replacing the live file.
	if err := platform.Database.BoltDb.Close(); err != nil {
		return result, fmt.Errorf("close database: %w", err)
	}

	preRestorePath, err := s.copyCurrentDatabase()
	if err != nil {
		return reopenAfterFailure(
			result, fmt.Errorf("copy current database: %w", err))
	}
	result.PreRestorePath = preRestorePath

	if err := os.Rename(stagedPath, s.dbPath); err != nil {
		return reopenAfterFailure(
			result, fmt.Errorf("replace database: %w", err))
	}
	syncDir(filepath.Dir(s.dbPath))

	// Reopen the restored file and rebuild derived data before reporting
	// success. A concurrent request may have reopened the replaced file while
	// the handle was closed, so close whatever handle exists first; otherwise
	// the process could keep serving the old inode after a successful restore.
	if err := platform.Database.BoltDb.Close(); err != nil {
		return s.rollback(result, fmt.Errorf("close replaced database: %w", err))
	}
	if err := platform.SetupBoltDB(); err != nil {
		return s.rollback(result, fmt.Errorf("reopen restored database: %w", err))
	}
	if err := ensureMeta(); err != nil {
		return s.rollback(result, fmt.Errorf("record instance metadata: %w", err))
	}
	if err := rebuildEntryIndexes(); err != nil {
		return s.rollback(result, fmt.Errorf("rebuild entry indexes: %w", err))
	}

	return result, nil
}

// reopenAfterFailure puts the still-intact original database back in service
// after a failure that happened before it was replaced.
func reopenAfterFailure(result RestoreResult, cause error) (RestoreResult, error) {
	if err := platform.SetupBoltDB(); err != nil {
		return result, fmt.Errorf("%v; reopen database: %w", cause, err)
	}
	return result, cause
}

// rollback returns to the pre-restore database after the replacement could not
// be opened or prepared. It is best-effort: the caller always receives the
// original failure, and the pre-restore path stays on disk either way.
func (s *Store) rollback(result RestoreResult, cause error) (RestoreResult, error) {
	if result.PreRestorePath != "" {
		stagedPath, err := stageFile(result.PreRestorePath, filepath.Dir(s.dbPath))
		if err == nil {
			defer os.Remove(stagedPath)
			_ = platform.Database.BoltDb.Close()
			if renameErr := os.Rename(stagedPath, s.dbPath); renameErr == nil {
				syncDir(filepath.Dir(s.dbPath))
				_ = platform.SetupBoltDB()
			}
		}
	}
	return result, cause
}

// copyCurrentDatabase writes the closed live database to a timestamped
// pre-restore file next to it.
func (s *Store) copyCurrentDatabase() (string, error) {
	destination, err := nextPreRestorePath(s.dbPath, time.Now())
	if err != nil {
		return "", err
	}
	if err := copyFile(s.dbPath, destination); err != nil {
		_ = os.Remove(destination)
		return "", err
	}
	syncDir(filepath.Dir(s.dbPath))
	return destination, nil
}

// nextPreRestorePath picks wdid-before-restore-<timestamp>.db, adding a
// counter when two restores happen within the same second.
func nextPreRestorePath(dbPath string, now time.Time) (string, error) {
	dir := filepath.Dir(dbPath)
	base := preRestorePrefix + now.UTC().Format(restoreTimeLayout)
	candidate := filepath.Join(dir, base+".db")
	for counter := 1; counter <= 1000; counter++ {
		_, err := os.Stat(candidate)
		switch {
		case errors.Is(err, os.ErrNotExist):
			return candidate, nil
		case err != nil:
			return "", fmt.Errorf("inspect pre-restore destination: %w", err)
		}
		candidate = filepath.Join(dir, fmt.Sprintf("%s-%d.db", base, counter))
	}
	return "", errors.New("could not find a free pre-restore name")
}

// stageFile copies sourcePath into a temporary file in dir and returns its
// path. The caller owns the file and must remove or rename it.
func stageFile(sourcePath, dir string) (string, error) {
	source, err := os.Open(sourcePath)
	if err != nil {
		return "", fmt.Errorf("open %s: %w", sourcePath, err)
	}
	defer source.Close()

	temp, err := os.CreateTemp(dir, restoreTempPattern)
	if err != nil {
		return "", fmt.Errorf("create temporary file: %w", err)
	}
	tempPath := temp.Name()
	cleanup := func() {
		temp.Close()
		os.Remove(tempPath)
	}

	if _, err := io.Copy(temp, source); err != nil {
		cleanup()
		return "", fmt.Errorf("copy %s: %w", sourcePath, err)
	}
	if err := temp.Sync(); err != nil {
		cleanup()
		return "", fmt.Errorf("sync temporary file: %w", err)
	}
	if err := temp.Close(); err != nil {
		os.Remove(tempPath)
		return "", fmt.Errorf("close temporary file: %w", err)
	}
	return tempPath, nil
}

// copyFile writes a new file at destinationPath. It refuses to overwrite an
// existing file, which keeps an old pre-restore copy from being lost.
func copyFile(sourcePath, destinationPath string) error {
	source, err := os.Open(sourcePath)
	if err != nil {
		return fmt.Errorf("open %s: %w", sourcePath, err)
	}
	defer source.Close()

	destination, err := os.OpenFile(destinationPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("create %s: %w", destinationPath, err)
	}
	cleanup := func() {
		destination.Close()
		os.Remove(destinationPath)
	}

	if _, err := io.Copy(destination, source); err != nil {
		cleanup()
		return fmt.Errorf("copy to %s: %w", destinationPath, err)
	}
	if err := destination.Sync(); err != nil {
		cleanup()
		return fmt.Errorf("sync %s: %w", destinationPath, err)
	}
	if err := destination.Close(); err != nil {
		os.Remove(destinationPath)
		return fmt.Errorf("close %s: %w", destinationPath, err)
	}
	return nil
}

// syncDir persists a rename. It is best-effort: the file itself is already
// synced and some filesystems reject directory fsync.
func syncDir(dir string) {
	handle, err := os.Open(dir)
	if err != nil {
		return
	}
	defer handle.Close()
	_ = handle.Sync()
}
