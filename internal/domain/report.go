package domain

import (
	"sort"
	"strings"
	"time"
)

// PeriodReport is the authoritative aggregate for an inclusive range of local
// calendar dates. Every screen that shows a period total reads these values
// instead of composing its own.
type PeriodReport struct {
	FromDate      string
	ToDate        string
	TotalMinutes  int
	EntryCount    int
	Categories    []CategoryTotal
	Subcategories []SubcategoryTotal
	SupportPeople []SupportPersonTotal
	SupportModes  []SupportModeTotal
	Weeks         []WeekRhythm
	Notes         []Note
}

// CategoryTotal is the time attributed to one category in the period.
type CategoryTotal struct {
	CategoryID string
	Name       string
	Role       CategoryRole
	Minutes    int
	EntryCount int
}

// SubcategoryTotal is the time attributed to one subcategory in the period.
type SubcategoryTotal struct {
	SubcategoryID string
	CategoryID    string
	Name          string
	Minutes       int
	EntryCount    int
}

// SupportPersonTotal is the support time and interaction count for one person.
type SupportPersonTotal struct {
	Person       string
	Minutes      int
	Interactions int
}

// SupportModeTotal is the support time and interaction count for one mode,
// which is the entry's subcategory under a support-role category.
type SupportModeTotal struct {
	SubcategoryID string
	Name          string
	Minutes       int
	Interactions  int
}

// WeekRhythm is one local week's logged time and where most of it went.
type WeekRhythm struct {
	WeekStartDate   string
	Minutes         int
	TopCategoryID   string
	TopCategoryName string
}

// BuildPeriodReport aggregates the entries whose local dates fall inside the
// period. Local day and week boundaries are resolved in the supplied location
// using the user's configured week start. The report includes only categories
// and subcategories that carry time, so an empty period returns zero totals
// rather than rows of zeros.
func BuildPeriodReport(
	fromDate, toDate string,
	location *time.Location,
	weekStart int,
	entries []WorkEntry,
	categories []Category,
	subcategories []Subcategory,
	notes []Note,
) (PeriodReport, error) {
	if err := validateReportDate("fromDate", fromDate); err != nil {
		return PeriodReport{}, err
	}
	if err := validateReportDate("toDate", toDate); err != nil {
		return PeriodReport{}, err
	}
	if fromDate > toDate {
		return PeriodReport{}, invalid("toDate", "must not be before fromDate")
	}
	if location == nil {
		location = time.UTC
	}

	categoryByID := make(map[string]Category, len(categories))
	for _, category := range categories {
		categoryByID[category.ID] = category
	}
	subcategoryByID := make(map[string]Subcategory, len(subcategories))
	for _, subcategory := range subcategories {
		subcategoryByID[subcategory.ID] = subcategory
	}

	report := PeriodReport{
		FromDate: fromDate,
		ToDate:   toDate,
	}

	categoryTotals := make(map[string]*CategoryTotal)
	subcategoryTotals := make(map[string]*SubcategoryTotal)
	supportPeople := make(map[string]*SupportPersonTotal)
	supportModes := make(map[string]*SupportModeTotal)
	touchedSubcategories := make(map[string]struct{})

	weekBuckets := newWeekBuckets(fromDate, toDate, location, weekStart)

	for _, entry := range entries {
		// Group by the day stored when the entry was written. That day comes
		// from the timezone configured at write time, so changing the timezone
		// later must not move historical entries to another day.
		localDate := entry.LocalDate
		if localDate == "" {
			localDate = entry.StartedAt.In(location).Format(DateLayout)
		}
		// The report owns its own boundary so a caller cannot widen the
		// period by handing over extra entries.
		if localDate < fromDate || localDate > toDate {
			continue
		}

		minutes := entry.DurationMinutes()
		if minutes < 0 {
			continue
		}

		category := categoryByID[entry.CategoryID]
		report.TotalMinutes += minutes
		report.EntryCount++

		total := categoryTotals[entry.CategoryID]
		if total == nil {
			total = &CategoryTotal{
				CategoryID: entry.CategoryID,
				Name:       category.Name,
				Role:       category.Role,
			}
			if total.Name == "" {
				total.Name = entry.CategoryID
			}
			categoryTotals[entry.CategoryID] = total
		}
		total.Minutes += minutes
		total.EntryCount++

		if entry.SubcategoryID != "" {
			touchedSubcategories[entry.SubcategoryID] = struct{}{}
			subtotal := subcategoryTotals[entry.SubcategoryID]
			if subtotal == nil {
				subtotal = &SubcategoryTotal{
					SubcategoryID: entry.SubcategoryID,
					CategoryID:    entry.CategoryID,
					Name:          subcategoryByID[entry.SubcategoryID].Name,
				}
				if subtotal.Name == "" {
					subtotal.Name = entry.SubcategoryID
				}
				subcategoryTotals[entry.SubcategoryID] = subtotal
			}
			subtotal.Minutes += minutes
			subtotal.EntryCount++
		}

		if category.Role == CategoryRoleSupport {
			if person := strings.TrimSpace(entry.Person); person != "" {
				key := strings.ToLower(person)
				personTotal := supportPeople[key]
				if personTotal == nil {
					personTotal = &SupportPersonTotal{Person: person}
					supportPeople[key] = personTotal
				}
				// Keep the display spelling deterministic when entries differ
				// only by case.
				if person < personTotal.Person {
					personTotal.Person = person
				}
				personTotal.Minutes += minutes
				personTotal.Interactions++
			}
			if entry.SubcategoryID != "" {
				modeTotal := supportModes[entry.SubcategoryID]
				if modeTotal == nil {
					modeTotal = &SupportModeTotal{
						SubcategoryID: entry.SubcategoryID,
						Name:          subcategoryByID[entry.SubcategoryID].Name,
					}
					if modeTotal.Name == "" {
						modeTotal.Name = entry.SubcategoryID
					}
					supportModes[entry.SubcategoryID] = modeTotal
				}
				modeTotal.Minutes += minutes
				modeTotal.Interactions++
			}
		}

		weekBuckets.add(localDate, entry.CategoryID, minutes, category.Name, location, weekStart)
	}

	report.Categories = sortedCategoryTotals(categoryTotals)
	report.Subcategories = sortedSubcategoryTotals(subcategoryTotals)
	report.SupportPeople = sortedSupportPeople(supportPeople)
	report.SupportModes = sortedSupportModes(supportModes)
	report.Weeks = weekBuckets.rhythm()
	report.Notes = reportNotes(notes, fromDate, toDate, touchedSubcategories)

	return report, nil
}

// validateReportDate requires an explicit, canonical local calendar date.
func validateReportDate(field, value string) error {
	if value == "" {
		return invalid(field, "must be a date in YYYY-MM-DD form")
	}
	return validateLocalDate(field, value)
}

// weekBuckets accumulates per-week category time so the rhythm can name the
// week's top category. Every week touching the period is present, including
// weeks with no entries.
type weekBuckets struct {
	minutes    map[string]int
	categories map[string]map[string]int
	names      map[string]string
}

func newWeekBuckets(fromDate, toDate string, location *time.Location, weekStart int) *weekBuckets {
	buckets := &weekBuckets{
		minutes:    make(map[string]int),
		categories: make(map[string]map[string]int),
		names:      make(map[string]string),
	}

	from, _ := time.ParseInLocation(DateLayout, fromDate, location)
	to, _ := time.ParseInLocation(DateLayout, toDate, location)
	for week := StartOfWeek(from, weekStart); !week.After(StartOfWeek(to, weekStart)); week = week.AddDate(0, 0, 7) {
		key := week.Format(DateLayout)
		buckets.minutes[key] = 0
		buckets.categories[key] = make(map[string]int)
	}
	return buckets
}

func (b *weekBuckets) add(localDate, categoryID string, minutes int, categoryName string, location *time.Location, weekStart int) {
	day, err := time.ParseInLocation(DateLayout, localDate, location)
	if err != nil {
		return
	}
	key := StartOfWeek(day, weekStart).Format(DateLayout)
	if _, ok := b.minutes[key]; !ok {
		return
	}
	b.minutes[key] += minutes
	b.categories[key][categoryID] += minutes
	if categoryName == "" {
		categoryName = categoryID
	}
	b.names[categoryID] = categoryName
}

// rhythm returns weeks in ascending order with the top category resolved.
func (b *weekBuckets) rhythm() []WeekRhythm {
	keys := make([]string, 0, len(b.minutes))
	for key := range b.minutes {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	weeks := make([]WeekRhythm, 0, len(keys))
	for _, key := range keys {
		week := WeekRhythm{WeekStartDate: key, Minutes: b.minutes[key]}
		topMinutes := -1
		for categoryID, minutes := range b.categories[key] {
			name := b.names[categoryID]
			if minutes > topMinutes ||
				(minutes == topMinutes && week.TopCategoryID != "" && categoryID < week.TopCategoryID) {
				topMinutes = minutes
				week.TopCategoryID = categoryID
				week.TopCategoryName = name
			}
		}
		if topMinutes <= 0 {
			week.TopCategoryID = ""
			week.TopCategoryName = ""
		}
		weeks = append(weeks, week)
	}
	return weeks
}

// StartOfWeek returns the local midnight starting the week that contains
// value. weekStart is 1 for Monday through 7 for Sunday, matching Settings.
func StartOfWeek(value time.Time, weekStart int) time.Time {
	if weekStart < 1 || weekStart > 7 {
		weekStart = int(time.Monday)
	}
	day := time.Date(value.Year(), value.Month(), value.Day(), 0, 0, 0, 0, value.Location())
	offset := (int(day.Weekday()) - weekStart%7 + 7) % 7
	return day.AddDate(0, 0, -offset)
}

func sortedCategoryTotals(totals map[string]*CategoryTotal) []CategoryTotal {
	return sortedAllocations(totals,
		func(total *CategoryTotal) int { return total.Minutes },
		func(total *CategoryTotal) string { return total.Name },
		func(total *CategoryTotal) string { return total.CategoryID },
	)
}

func sortedSubcategoryTotals(totals map[string]*SubcategoryTotal) []SubcategoryTotal {
	return sortedAllocations(totals,
		func(total *SubcategoryTotal) int { return total.Minutes },
		func(total *SubcategoryTotal) string { return total.Name },
		func(total *SubcategoryTotal) string { return total.SubcategoryID },
	)
}

func sortedSupportPeople(totals map[string]*SupportPersonTotal) []SupportPersonTotal {
	return sortedAllocations(totals,
		func(total *SupportPersonTotal) int { return total.Minutes },
		func(total *SupportPersonTotal) string { return total.Person },
		func(total *SupportPersonTotal) string { return total.Person },
	)
}

func sortedSupportModes(totals map[string]*SupportModeTotal) []SupportModeTotal {
	return sortedAllocations(totals,
		func(total *SupportModeTotal) int { return total.Minutes },
		func(total *SupportModeTotal) string { return total.Name },
		func(total *SupportModeTotal) string { return total.SubcategoryID },
	)
}

// sortedAllocations orders biggest time first, then by label and id so ties
// are stable across reports.
func sortedAllocations[T any](
	totals map[string]*T,
	minutes func(*T) int,
	label func(*T) string,
	id func(*T) string,
) []T {
	result := make([]T, 0, len(totals))
	for _, total := range totals {
		result = append(result, *total)
	}
	sort.Slice(result, func(i, j int) bool {
		first, second := &result[i], &result[j]
		if minutes(first) != minutes(second) {
			return minutes(first) > minutes(second)
		}
		if label(first) != label(second) {
			return label(first) < label(second)
		}
		return id(first) < id(second)
	})
	return result
}

// reportNotes returns day notes that fall inside the period plus project notes
// on a subcategory the user worked on in the period. A note may carry a date, a
// subcategory, or both, so either match includes it.
func reportNotes(notes []Note, fromDate, toDate string, touchedSubcategories map[string]struct{}) []Note {
	result := make([]Note, 0)
	for _, note := range notes {
		dated := note.Date != "" && note.Date >= fromDate && note.Date <= toDate
		_, touched := touchedSubcategories[note.SubcategoryID]
		project := note.SubcategoryID != "" && touched
		if !dated && !project {
			continue
		}
		result = append(result, note)
	}

	sort.Slice(result, func(i, j int) bool {
		if !result[i].CreatedAt.Equal(result[j].CreatedAt) {
			return result[i].CreatedAt.After(result[j].CreatedAt)
		}
		return result[i].ID < result[j].ID
	})
	return result
}
