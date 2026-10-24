package store

import (
	"errors"
	"fmt"
	"io"
	"strconv"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"go.etcd.io/bbolt"
)

const snapshotOpenTimeout = 2 * time.Second

// ErrInvalidSnapshot marks a file that cannot be used as a wdid backup. Restore
// refuses it before the live database is touched.
var ErrInvalidSnapshot = errors.New("not a usable wdid snapshot")

// Snapshot writes a consistent, point-in-time copy of the database to w. The
// copy is taken inside a read transaction, so writes that are committed while
// the copy runs are either fully present or fully absent.
func (s *Store) Snapshot(w io.Writer) error {
	if w == nil {
		return errors.New("snapshot writer is nil")
	}
	return platform.Database.BoltDb.Snapshot(w)
}

// VerifySnapshot opens the database file at path read-only, reads the recorded
// schema version and closes it again. A file that cannot be opened as a BoltDB
// database, or that has no positive schema version, is not a usable backup.
func VerifySnapshot(path string) (int, error) {
	database, err := bbolt.Open(path, 0o600, &bbolt.Options{
		ReadOnly: true,
		Timeout:  snapshotOpenTimeout,
	})
	if err != nil {
		return 0, fmt.Errorf("%w: open read-only: %w", ErrInvalidSnapshot, err)
	}
	defer database.Close()

	version := 0
	err = database.View(func(tx *bbolt.Tx) error {
		bucket := tx.Bucket([]byte(sysMetaBucket))
		if bucket == nil {
			return fmt.Errorf("%w: no instance metadata", ErrInvalidSnapshot)
		}
		raw := bucket.Get([]byte(schemaVersionKey))
		if raw == nil {
			return fmt.Errorf("%w: no schema version", ErrInvalidSnapshot)
		}
		parsed, err := strconv.Atoi(string(raw))
		if err != nil {
			return fmt.Errorf("%w: parse schema version: %w", ErrInvalidSnapshot, err)
		}
		if parsed <= 0 {
			return fmt.Errorf("%w: invalid schema version %d", ErrInvalidSnapshot, parsed)
		}
		version = parsed
		return nil
	})
	if err != nil {
		return 0, fmt.Errorf("read snapshot schema version: %w", err)
	}

	return version, nil
}
