package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/demo"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// seedScenario is a variable so tests can inject a failure and prove that the
// target database is only replaced after a successful seed.
var seedScenario = demo.Seed

// runSeed implements `wdid seed [--reset] [--anchor YYYY-MM-DD] <scenario>`.
//
// It seeds a temporary database beside the target and renames it into place
// only after the whole seed succeeds. Every failure before the rename leaves
// the previous target byte-identical.
func runSeed(args []string, out io.Writer) error {
	flags := flag.NewFlagSet("seed", flag.ContinueOnError)
	flags.SetOutput(out)
	flags.Usage = func() {
		fmt.Fprintln(out, "usage: wdid seed [--reset] [--anchor YYYY-MM-DD] <scenario>")
		fmt.Fprintf(out, "scenarios: %s\n", strings.Join(demo.ScenarioNames(), ", "))
	}
	reset := flags.Bool("reset", false, "replace an existing database")
	anchorValue := flags.String("anchor", "", "seed date in YYYY-MM-DD (default: today in UTC)")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 1 {
		return errors.New("usage: wdid seed [--reset] [--anchor YYYY-MM-DD] <scenario>")
	}
	scenario := flags.Arg(0)

	cfg := config.LoadStorage()
	if !cfg.DevMode {
		return errors.New("demo seeding is development-only; set WDID_DEV_MODE=true")
	}
	if err := demo.ValidateScenario(scenario); err != nil {
		return err
	}

	anchor, err := parseSeedAnchor(*anchorValue)
	if err != nil {
		return err
	}

	target := strings.TrimSpace(cfg.DBPath)
	if target == "" {
		return errors.New("WDID_DB_PATH must not be empty")
	}
	if _, err := os.Stat(target); err == nil {
		if !*reset {
			return fmt.Errorf("refusing to overwrite existing demo data at %s; pass --reset", target)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect database path %s: %w", target, err)
	}

	dir := filepath.Dir(target)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return fmt.Errorf("create data directory: %w", err)
	}

	// The temp file lives in the target's directory, so the final rename is a
	// same-filesystem, atomic replacement.
	temp, err := os.CreateTemp(dir, ".wdid-seed-*.db")
	if err != nil {
		return fmt.Errorf("create temporary seed database: %w", err)
	}
	tempPath := temp.Name()
	if err := temp.Close(); err != nil {
		_ = os.Remove(tempPath)
		return fmt.Errorf("close temporary seed file: %w", err)
	}
	replaced := false
	defer func() {
		if !replaced {
			_ = os.Remove(tempPath)
		}
	}()

	seedCfg := cfg
	seedCfg.DBPath = tempPath
	database, err := store.Open(seedCfg)
	if err != nil {
		return fmt.Errorf("open temporary seed database: %w", err)
	}

	summary, seedErr := seedScenario(database, demo.Options{Scenario: scenario, Anchor: anchor})
	closeErr := database.Close()
	if seedErr != nil {
		return fmt.Errorf("seed %s scenario: %w", scenario, seedErr)
	}
	if closeErr != nil {
		return fmt.Errorf("close temporary seed database: %w", closeErr)
	}

	if err := os.Rename(tempPath, target); err != nil {
		return fmt.Errorf("replace demo database: %w", err)
	}
	replaced = true
	syncDir(dir)

	fmt.Fprintf(out, "Seeded scenario: %s\n", scenario)
	fmt.Fprintf(out, "Database: %s\n", target)
	fmt.Fprintf(out, "Anchor: %s\n", anchor.Format(domain.DateLayout))
	fmt.Fprintf(out, "Email: %s\n", demo.DemoEmail)
	fmt.Fprintf(out, "Password: %s\n", demo.DemoPassword)
	fmt.Fprintf(out, "Users: %d\n", summary.Users)
	fmt.Fprintf(out, "Categories: %d\n", summary.Categories)
	fmt.Fprintf(out, "Subcategories: %d\n", summary.Subcategories)
	fmt.Fprintf(out, "Entries: %d\n", summary.Entries)
	fmt.Fprintf(out, "Notes: %d\n", summary.Notes)
	fmt.Fprintf(out, "Milestones: %d\n", summary.Milestones)
	fmt.Fprintf(out, "Check-ins: %d\n", summary.CheckIns)
	activeTimer := "none"
	if summary.ActiveTimer {
		activeTimer = "running"
	}
	fmt.Fprintf(out, "Active timer: %s\n", activeTimer)
	return nil
}

// parseSeedAnchor reads --anchor. An empty value means today in UTC; an
// explicit value must be a canonical YYYY-MM-DD date.
func parseSeedAnchor(value string) (time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		now := time.Now().UTC()
		return time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC), nil
	}

	parsed, err := time.Parse(domain.DateLayout, value)
	if err != nil || parsed.Format(domain.DateLayout) != value {
		return time.Time{}, fmt.Errorf("invalid --anchor %q: want YYYY-MM-DD", value)
	}
	return parsed, nil
}

// syncDir persists a rename. It is best-effort: the file itself is already
// synced and some filesystems reject directory fsync. This mirrors
// internal/store's restore helper, which is unexported.
func syncDir(dir string) {
	handle, err := os.Open(dir)
	if err != nil {
		return
	}
	defer handle.Close()
	_ = handle.Sync()
}
