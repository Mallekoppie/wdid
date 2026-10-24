package main

import (
	"errors"
	"fmt"
	"io"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/Mallekoppie/wdid/internal/backup"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/store"
)

// newBackupManager builds the instance-wide snapshot manager. The service
// config supplies the defaults; the primary account's persisted settings take
// precedence so a configured directory, interval or retention survives a
// restart.
func newBackupManager(database *store.Store, cfg config.Config) *backup.Manager {
	manager := backup.New(database, backup.Config{
		Dir:       cfg.EffectiveBackupDir(),
		Interval:  cfg.EffectiveBackupInterval(),
		Retention: cfg.EffectiveBackupRetention(),
	})
	if settings, ok, err := database.PrimarySettings(); err == nil && ok {
		manager.Configure(backup.FromSettings(settings, manager.Config()))
	}
	return manager
}

// runBackup dispatches `wdid backup` and its read-only subcommands. With no
// arguments it takes a manual snapshot; manual snapshots are never removed by
// retention.
func runBackup(args []string, out io.Writer) error {
	if len(args) > 0 {
		switch args[0] {
		case "status":
			return runBackupStatus(args[1:], out)
		case "list":
			return runBackupList(args[1:], out)
		default:
			return fmt.Errorf("unknown backup command %q", args[0])
		}
	}

	database, err := openCLIStore()
	if err != nil {
		return err
	}
	defer database.Close()

	manager := newBackupManager(database, config.LoadStorage())
	snapshot, err := manager.Create(backup.KindManual)
	if err != nil {
		return err
	}

	fmt.Fprintf(out, "Created backup %s (%d bytes)\n", snapshot.Path, snapshot.Size)
	return nil
}

func runBackupStatus(args []string, out io.Writer) error {
	if len(args) > 0 {
		return fmt.Errorf("usage: wdid backup status")
	}

	database, err := openCLIStore()
	if err != nil {
		return err
	}
	defer database.Close()

	status, err := newBackupManager(database, config.LoadStorage()).Status()
	if err != nil {
		return err
	}

	fmt.Fprintf(out, "Directory: %s\n", status.Directory)
	fmt.Fprintf(out, "Interval: %s\n", status.Interval)
	fmt.Fprintf(out, "Retention: %d scheduled\n", status.Retention)
	if status.LastBackupAt.IsZero() {
		fmt.Fprintln(out, "Last backup: never")
	} else {
		kind := "scheduled"
		if status.LastBackupManual {
			kind = "manual"
		}
		fmt.Fprintf(out, "Last backup: %s (%s, %d bytes)\n",
			status.LastBackupAt.Format(time.RFC3339), kind, status.LastBackupSize)
	}
	fmt.Fprintf(out, "Snapshots: %d scheduled, %d manual\n", status.ScheduledCount, status.ManualCount)
	fmt.Fprintf(out, "Overdue: %t\n", status.Overdue)
	return nil
}

func runBackupList(args []string, out io.Writer) error {
	if len(args) > 0 {
		return fmt.Errorf("usage: wdid backup list")
	}

	database, err := openCLIStore()
	if err != nil {
		return err
	}
	defer database.Close()

	snapshots, err := newBackupManager(database, config.LoadStorage()).List()
	if err != nil {
		return err
	}
	if len(snapshots) == 0 {
		fmt.Fprintln(out, "No backups.")
		return nil
	}

	table := tabwriter.NewWriter(out, 0, 4, 2, ' ', 0)
	fmt.Fprintln(table, "NAME\tKIND\tCREATED\tSIZE")
	for _, snapshot := range snapshots {
		kind := "scheduled"
		if snapshot.Manual() {
			kind = "manual"
		}
		fmt.Fprintf(table, "%s\t%s\t%s\t%d bytes\n",
			snapshot.Name, kind, snapshot.CreatedAt.Format(time.RFC3339), snapshot.Size)
	}
	return table.Flush()
}

// runRestore dispatches `wdid restore <name>`. The service must be stopped:
// restore closes the database, saves the current file, swaps the snapshot in,
// reopens the database and rebuilds its indexes.
func runRestore(args []string, out io.Writer) error {
	if len(args) != 1 || strings.TrimSpace(args[0]) == "" {
		return errors.New("usage: wdid restore <name>")
	}

	database, err := openCLIStore()
	if err != nil {
		return err
	}
	defer database.Close()

	snapshot, result, err := newBackupManager(database, config.LoadStorage()).Restore(args[0])
	if err != nil {
		return err
	}

	fmt.Fprintf(out, "Restored %s (schema version %d)\n", snapshot.Name, result.SchemaVersion)
	if result.PreRestorePath != "" {
		fmt.Fprintf(out, "Previous database saved as %s\n", result.PreRestorePath)
	}
	return nil
}
