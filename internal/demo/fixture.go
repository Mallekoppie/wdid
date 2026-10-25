package demo

import (
	"bytes"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

// The embedded fixture is split by domain so later tickets can add entries,
// notes, milestones and check-ins as new files. The seed command only ever
// passes a directory, so adding a domain never changes its interface.
//
//go:embed fixtures/*.json
var embeddedFixtures embed.FS

// TaxonomyFixture is the declarative category and subcategory dataset.
type TaxonomyFixture struct {
	Categories []CategoryFixture `json:"categories"`
}

// CategoryFixture is one category with its ordered subcategories. Under an
// initiative-role category a subcategory is a project; under a support-role
// category it is a support mode.
type CategoryFixture struct {
	Name          string               `json:"name"`
	Role          domain.CategoryRole  `json:"role"`
	Subcategories []SubcategoryFixture `json:"subcategories"`
}

// SubcategoryFixture is one project or mode. Status defaults to active when
// omitted, which suits support modes and other work that has no lifecycle.
type SubcategoryFixture struct {
	Name          string                   `json:"name"`
	Status        domain.SubcategoryStatus `json:"status,omitempty"`
	Progress      int                      `json:"progress,omitempty"`
	TargetOutcome string                   `json:"targetOutcome,omitempty"`
}

// PeopleFixture is the support-person roster.
type PeopleFixture struct {
	Roster []string `json:"roster"`
}

// SettingsFixture is the demo settings that differ from the account defaults.
// Everything else comes from domain.DefaultSettings.
type SettingsFixture struct {
	Timezone           string               `json:"timezone"`
	DailyTargetMinutes int                  `json:"dailyTargetMinutes"`
	ReviewCadence      domain.ReviewCadence `json:"reviewCadence"`
}

// Fixture is the decoded declarative demo dataset. Each domain is independent:
// a later ticket adds a field, an embedded file and one fixtureDomain entry.
type Fixture struct {
	Taxonomy TaxonomyFixture
	People   PeopleFixture
	Settings SettingsFixture
}

type fixtureDomain struct {
	file string
	dest any
}

// domains lists the per-domain fixture files and their destinations. Later
// tickets extend this list (entries.json, notes.json, milestones.json,
// check_ins.json) without touching cmd/wdid.
func (f *Fixture) domains() []fixtureDomain {
	return []fixtureDomain{
		{file: "taxonomy.json", dest: &f.Taxonomy},
		{file: "people.json", dest: &f.People},
		{file: "settings.json", dest: &f.Settings},
	}
}

// LoadFixture loads the declarative demo fixture. Each domain lives in its own
// JSON file. When dir is non-empty, a file with the same name in dir replaces
// that embedded domain; a missing file falls back to the embedded copy.
//
// Files in dir whose names are not known domains are ignored, as are dotfiles,
// so a directory may carry data for later tickets without breaking an older
// binary. An unknown directory (or a path that is not a directory) is an
// error.
func LoadFixture(dir string) (Fixture, error) {
	dir = strings.TrimSpace(dir)
	if dir != "" {
		info, err := os.Stat(dir)
		if err != nil {
			return Fixture{}, fmt.Errorf("read fixture directory %q: %w", dir, err)
		}
		if !info.IsDir() {
			return Fixture{}, fmt.Errorf("fixture path %q is not a directory", dir)
		}
	}

	var fixture Fixture
	for _, domain := range fixture.domains() {
		data, err := readFixtureDomain(dir, domain.file)
		if err != nil {
			return Fixture{}, err
		}
		if err := decodeFixtureDomain(domain.file, data, domain.dest); err != nil {
			return Fixture{}, err
		}
	}
	if err := fixture.validate(); err != nil {
		return Fixture{}, err
	}
	return fixture, nil
}

func readFixtureDomain(dir, name string) ([]byte, error) {
	if dir != "" {
		path := filepath.Join(dir, name)
		data, err := os.ReadFile(path)
		switch {
		case err == nil:
			return data, nil
		case errors.Is(err, os.ErrNotExist):
			// Fall back to the embedded file for this domain.
		default:
			return nil, fmt.Errorf("read fixture %s: %w", path, err)
		}
	}

	data, err := embeddedFixtures.ReadFile("fixtures/" + name)
	if err != nil {
		return nil, fmt.Errorf("read embedded fixture %s: %w", name, err)
	}
	return data, nil
}

func decodeFixtureDomain(name string, data []byte, dest any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dest); err != nil {
		return fmt.Errorf("decode fixture %s: %w", name, err)
	}
	return nil
}

// validate rejects a fixture that cannot produce deterministic, valid rows.
// Names are unique because they are part of the stable ID key.
func (f Fixture) validate() error {
	if len(f.Taxonomy.Categories) == 0 {
		return errors.New("fixture taxonomy must contain at least one category")
	}

	categories := make(map[string]struct{}, len(f.Taxonomy.Categories))
	for i, category := range f.Taxonomy.Categories {
		name := strings.TrimSpace(category.Name)
		if name == "" {
			return fmt.Errorf("fixture category %d: name is required", i)
		}
		if !category.Role.Valid() {
			return fmt.Errorf("fixture category %q: invalid role %q", name, category.Role)
		}
		if _, ok := categories[name]; ok {
			return fmt.Errorf("fixture category %q is duplicated", name)
		}
		categories[name] = struct{}{}

		subcategories := make(map[string]struct{}, len(category.Subcategories))
		for j, subcategory := range category.Subcategories {
			subName := strings.TrimSpace(subcategory.Name)
			if subName == "" {
				return fmt.Errorf("fixture category %q subcategory %d: name is required", name, j)
			}
			if _, ok := subcategories[subName]; ok {
				return fmt.Errorf("fixture category %q subcategory %q is duplicated", name, subName)
			}
			subcategories[subName] = struct{}{}
			if status := subcategory.Status; status != "" && !status.Valid() {
				return fmt.Errorf("fixture subcategory %q: invalid status %q", subName, status)
			}
			if subcategory.Progress < 0 || subcategory.Progress > 100 {
				return fmt.Errorf("fixture subcategory %q: progress must be between 0 and 100", subName)
			}
		}
	}

	if strings.TrimSpace(f.Settings.Timezone) == "" {
		return errors.New("fixture settings: timezone is required")
	}
	if err := ValidateTimezone(f.Settings.Timezone); err != nil {
		return fmt.Errorf("fixture settings: %w", err)
	}
	if f.Settings.DailyTargetMinutes < 0 || f.Settings.DailyTargetMinutes > 1440 {
		return errors.New("fixture settings: dailyTargetMinutes must be between 0 and 1440")
	}
	if !f.Settings.ReviewCadence.Valid() {
		return fmt.Errorf("fixture settings: invalid reviewCadence %q", f.Settings.ReviewCadence)
	}
	return nil
}

// ValidateTimezone checks an IANA timezone name. An empty name means "keep the
// fixture or account default" and is not an error.
func ValidateTimezone(name string) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil
	}
	if _, err := time.LoadLocation(name); err != nil {
		return fmt.Errorf("invalid timezone %q: %w", name, err)
	}
	return nil
}
