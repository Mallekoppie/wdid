package domain

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"
)

// ExportSchemaVersion identifies the shape of data.json. It changes only when
// a field is removed or its meaning changes, so tools can rely on a stable
// contract.
const ExportSchemaVersion = 2

// ExportFile is one file in a generated export bundle.
type ExportFile struct {
	Name    string
	Content string
}

// ExportBundle is the complete, self-describing export for a period. It is
// generated on demand and never persisted: the service returns the files to
// the caller, and the database directory never holds an export.
type ExportBundle struct {
	Directory string
	Files     []ExportFile
}

// ExportInput is everything needed to render a bundle. The report owns the
// authoritative period aggregates; the raw rows supply the flat CSV sheets and
// the structured data.json payload.
type ExportInput struct {
	Report        PeriodReport
	Entries       []WorkEntry
	Categories    []Category
	Subcategories []Subcategory
	Milestones    []Milestone
	CheckIns      []CheckIn
	Settings      Settings
	// FocusNotes is the scoped check-in's focus text, when the bundle belongs
	// to a check-in rather than a bare period.
	FocusNotes  string
	GeneratedAt time.Time
}

// ExportSummaryFileName and friends are the fixed bundle members. The order is
// part of the contract: summary.md first, then data.json, entries.csv and
// support.csv.
const (
	ExportSummaryFileName = "summary.md"
	ExportDataFileName    = "data.json"
	ExportEntriesFileName = "entries.csv"
	ExportSupportFileName = "support.csv"
)

// BuildExportBundle renders summary.md, data.json, entries.csv and support.csv
// for one period. Nothing is written to disk.
func BuildExportBundle(input ExportInput) (ExportBundle, error) {
	summary := BuildExportSummary(input)
	data, err := buildExportData(input)
	if err != nil {
		return ExportBundle{}, err
	}

	return ExportBundle{
		Directory: fmt.Sprintf("wdid-export-%s_%s", input.Report.FromDate, input.Report.ToDate),
		Files: []ExportFile{
			{Name: ExportSummaryFileName, Content: summary},
			{Name: ExportDataFileName, Content: data},
			{Name: ExportEntriesFileName, Content: buildEntriesCSV(input)},
			{Name: ExportSupportFileName, Content: buildSupportCSV(input)},
		},
	}, nil
}

// BuildExportSummary renders the fixed-heading Markdown contract from plan
// §9.2. Headings, ISO dates and units are stable so a pasted prompt and a
// spreadsheet see the same numbers.
func BuildExportSummary(input ExportInput) string {
	report := input.Report
	subcategoryByID := indexSubcategories(input.Subcategories)
	initiativeSubcategories := initiativeSubcategoryTotals(report)

	days := periodDays(report.FromDate, report.ToDate)
	total := formatExportDuration(report.TotalMinutes)
	projects := len(initiativeSubcategories)
	supportInteractions := supportInteractionCount(report)

	var builder strings.Builder
	fmt.Fprintf(&builder, "# wdid work report — %s to %s\n\n", report.FromDate, report.ToDate)

	builder.WriteString("## Context\n")
	// The plan's optional `Role:` line has no product setting yet, so the
	// context opens with the computed period line.
	fmt.Fprintf(&builder, "Period: %d days · %s logged · %d projects · %d support interactions\n\n",
		days, total, projects, supportInteractions)

	builder.WriteString("## Time allocation\n")
	builder.WriteString("| Category | Hours | Share |\n")
	builder.WriteString("| --- | --- | --- |\n")
	for _, category := range report.Categories {
		fmt.Fprintf(&builder, "| %s | %s | %d%% |\n",
			markdownCell(category.Name), formatExportDuration(category.Minutes), share(category.Minutes, report.TotalMinutes))
	}
	for _, category := range sortedInitiativeCategories(report.Categories) {
		rows := subcategoriesInCategory(report.Subcategories, category.CategoryID)
		if len(rows) == 0 {
			continue
		}
		fmt.Fprintf(&builder, "\n### %s\n", markdownCell(category.Name))
		builder.WriteString("| Project | Hours | Share |\n")
		builder.WriteString("| --- | --- | --- |\n")
		for _, row := range rows {
			fmt.Fprintf(&builder, "| %s | %s | %d%% |\n",
				markdownCell(row.Name), formatExportDuration(row.Minutes), share(row.Minutes, report.TotalMinutes))
		}
	}
	builder.WriteString("\n")

	builder.WriteString("## Initiative progress\n")
	if len(initiativeSubcategories) == 0 {
		builder.WriteString("_No initiative work recorded in this period._\n\n")
	}
	for _, total := range initiativeSubcategories {
		subcategory := subcategoryByID[total.SubcategoryID]
		progress := subcategory.Name
		if progress == "" {
			progress = total.Name
		}
		status := titleCase(string(subcategory.Status))
		if status == "" {
			status = "Unknown"
		}
		fmt.Fprintf(&builder, "### %s — %s, %d%%\n", progress, status, subcategory.Progress)

		target := strings.TrimSpace(subcategory.TargetOutcome)
		if target == "" {
			target = "not recorded"
		}
		fmt.Fprintf(&builder, "- Target outcome: %s\n", target)
		fmt.Fprintf(&builder, "- This period: %s, %d entries\n",
			formatExportDuration(total.Minutes), total.EntryCount)

		done, count := milestoneCounts(input.Milestones, total.SubcategoryID)
		fmt.Fprintf(&builder, "- Milestones: %d of %d complete\n", done, count)

		outcomes := projectOutcomes(input.Entries, total.SubcategoryID)
		if len(outcomes) == 0 {
			builder.WriteString("- Key outcomes: none recorded\n")
		} else {
			builder.WriteString("- Key outcomes:\n")
			for _, outcome := range outcomes {
				fmt.Fprintf(&builder, "  - %s\n", outcome)
			}
		}
		builder.WriteString("- Risks: none recorded\n\n")
	}

	builder.WriteString("## Support and collaboration\n")
	if len(report.SupportPeople) == 0 {
		builder.WriteString("_No support interactions recorded in this period._\n\n")
	}
	for _, person := range report.SupportPeople {
		header := markdownCell(person.Person)
		if team := supportTeam(input.Entries, person.Person); team != "" {
			header += " (" + markdownCell(team) + ")"
		}
		fmt.Fprintf(&builder, "### %s — %s, %d interactions\n",
			header, formatExportDuration(person.Minutes), person.Interactions)
		details := supportDetails(input, person.Person, subcategoryByID)
		if len(details) == 0 {
			builder.WriteString("- No detail recorded.\n")
		}
		for _, detail := range details {
			fmt.Fprintf(&builder, "- %s\n", detail)
		}
		builder.WriteString("\n")
	}

	builder.WriteString("## Weekly rhythm\n")
	builder.WriteString("| Week starting | Hours | Top category |\n")
	builder.WriteString("| --- | --- | --- |\n")
	for _, week := range report.Weeks {
		top := week.TopCategoryName
		if top == "" {
			top = "—"
		}
		fmt.Fprintf(&builder, "| %s | %s | %s |\n",
			week.WeekStartDate, formatExportDuration(week.Minutes), markdownCell(top))
	}
	builder.WriteString("\n")

	builder.WriteString("## Notes and context\n")
	notesWritten := false
	if focus := oneLine(input.FocusNotes); focus != "" {
		fmt.Fprintf(&builder, "- Focus notes: %s\n", focus)
		notesWritten = true
	}
	for _, note := range report.Notes {
		label := ""
		if note.Date != "" {
			label = note.Date + ": "
		}
		fmt.Fprintf(&builder, "- %s%s\n", label, oneLine(note.Text))
		notesWritten = true
	}
	if !notesWritten {
		builder.WriteString("- No notes recorded in this period.\n")
	}

	builder.WriteString("\n## Source data\n")
	builder.WriteString("Structured data: data.json · Flat entries: entries.csv · Support: support.csv\n")
	return builder.String()
}

// buildExportData renders data.json with the stable field names from plan
// §9.2. Every list is non-nil so an empty period encodes as [] rather than
// null.
func buildExportData(input ExportInput) (string, error) {
	report := input.Report
	categoryByID := indexCategories(input.Categories)
	subcategoryByID := indexSubcategories(input.Subcategories)

	categories := make([]exportCategory, 0, len(report.Categories))
	for _, category := range report.Categories {
		categories = append(categories, exportCategory{
			ID:         category.CategoryID,
			Name:       category.Name,
			Role:       string(category.Role),
			Minutes:    category.Minutes,
			EntryCount: category.EntryCount,
		})
	}

	subcategories := make([]exportSubcategory, 0, len(report.Subcategories))
	for _, total := range report.Subcategories {
		model := subcategoryByID[total.SubcategoryID]
		links := make([]exportLink, 0, len(model.Links))
		for _, link := range model.Links {
			links = append(links, exportLink{Label: link.Label, URL: link.URL})
		}
		milestones := make([]exportMilestone, 0)
		for _, milestone := range sortedMilestones(input.Milestones, total.SubcategoryID) {
			milestones = append(milestones, exportMilestone{
				ID:      milestone.ID,
				Title:   milestone.Title,
				DueDate: milestone.DueDate,
				Done:    milestone.Done,
			})
		}
		subcategories = append(subcategories, exportSubcategory{
			ID:            total.SubcategoryID,
			CategoryID:    total.CategoryID,
			Name:          total.Name,
			Minutes:       total.Minutes,
			EntryCount:    total.EntryCount,
			Status:        string(model.Status),
			Progress:      model.Progress,
			TargetOutcome: model.TargetOutcome,
			TargetDate:    model.TargetDate,
			Links:         links,
			Milestones:    milestones,
		})
	}

	entries := make([]exportEntry, 0, len(input.Entries))
	support := make([]exportEntry, 0)
	for _, entry := range sortedEntries(input.Entries) {
		row := toExportEntry(entry, categoryByID, subcategoryByID)
		entries = append(entries, row)
		if categoryByID[entry.CategoryID].Role == CategoryRoleSupport {
			support = append(support, row)
		}
	}

	checkIns := make([]exportCheckIn, 0, len(input.CheckIns))
	for _, checkIn := range input.CheckIns {
		checkIns = append(checkIns, exportCheckIn{
			ID:              checkIn.ID,
			Kind:            string(checkIn.Kind),
			PeriodStart:     checkIn.PeriodStart,
			PeriodEnd:       checkIn.PeriodEnd,
			State:           string(checkIn.State),
			Audience:        string(checkIn.Audience),
			FocusNotes:      checkIn.FocusNotes,
			SummaryMarkdown: checkIn.SummaryMarkdown,
			PromptVersion:   checkIn.PromptVersion,
			CreatedAt:       formatInstant(checkIn.CreatedAt),
		})
	}

	notes := make([]exportNote, 0, len(report.Notes))
	for _, note := range report.Notes {
		notes = append(notes, exportNote{
			ID:            note.ID,
			Date:          note.Date,
			SubcategoryID: note.SubcategoryID,
			Text:          note.Text,
			CreatedAt:     formatInstant(note.CreatedAt),
		})
	}

	generatedAt := input.GeneratedAt
	if generatedAt.IsZero() {
		generatedAt = time.Now()
	}

	payload := exportData{
		SchemaVersion: ExportSchemaVersion,
		GeneratedAt:   formatInstant(generatedAt),
		Period: exportPeriod{
			Start: report.FromDate,
			End:   report.ToDate,
			Days:  periodDays(report.FromDate, report.ToDate),
		},
		SettingsSummary: exportSettings{
			Timezone:           input.Settings.Timezone,
			WeekStart:          input.Settings.WeekStart,
			DailyTargetMinutes: input.Settings.DailyTargetMinutes,
		},
		Categories:    categories,
		Subcategories: subcategories,
		Entries:       entries,
		Support:       support,
		CheckIns:      checkIns,
		Notes:         notes,
		Totals: exportTotals{
			Minutes:             report.TotalMinutes,
			EntryCount:          report.EntryCount,
			SupportMinutes:      supportMinutes(report),
			SupportInteractions: supportInteractionCount(report),
			Projects:            len(initiativeSubcategoryTotals(report)),
			Days:                periodDays(report.FromDate, report.ToDate),
		},
	}

	encoded, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return "", fmt.Errorf("encode export data: %w", err)
	}
	return string(encoded) + "\n", nil
}

// buildEntriesCSV renders the flat work-entry sheet. Every entry in the period
// appears, including support work; support.csv is the person-and-mode view.
func buildEntriesCSV(input ExportInput) string {
	categoryByID := indexCategories(input.Categories)
	subcategoryByID := indexSubcategories(input.Subcategories)

	var builder strings.Builder
	writer := csv.NewWriter(&builder)
	_ = writer.Write([]string{
		"date", "start", "end", "minutes", "category", "subcategory",
		"description", "outcome", "people", "team", "tags", "source",
	})
	for _, entry := range sortedEntries(input.Entries) {
		_ = writer.Write([]string{
			entry.LocalDate,
			formatInstant(entry.StartedAt),
			formatInstant(entry.EndedAt),
			fmt.Sprintf("%d", entry.DurationMinutes()),
			categoryByID[entry.CategoryID].Name,
			subcategoryByID[entry.SubcategoryID].Name,
			entry.Description,
			entry.Outcome,
			strings.Join(entry.People, ";"),
			entry.Team,
			strings.Join(entry.Tags, ";"),
			string(entry.Source),
		})
	}
	writer.Flush()
	return builder.String()
}

// buildSupportCSV renders one row per support entry with every person and the
// mode columns the plan requires. Names on one entry are joined by `;`, so the
// sheet never repeats an entry or inflates the support time. Mode is the
// entry's subcategory.
func buildSupportCSV(input ExportInput) string {
	categoryByID := indexCategories(input.Categories)
	subcategoryByID := indexSubcategories(input.Subcategories)

	var builder strings.Builder
	writer := csv.NewWriter(&builder)
	_ = writer.Write([]string{
		"date", "start", "end", "minutes", "people", "mode",
		"team", "description", "outcome",
	})
	for _, entry := range sortedEntries(input.Entries) {
		if categoryByID[entry.CategoryID].Role != CategoryRoleSupport {
			continue
		}
		_ = writer.Write([]string{
			entry.LocalDate,
			formatInstant(entry.StartedAt),
			formatInstant(entry.EndedAt),
			fmt.Sprintf("%d", entry.DurationMinutes()),
			strings.Join(entry.People, ";"),
			subcategoryByID[entry.SubcategoryID].Name,
			entry.Team,
			entry.Description,
			entry.Outcome,
		})
	}
	writer.Flush()
	return builder.String()
}

// --- data.json types -------------------------------------------------------

type exportData struct {
	SchemaVersion   int                 `json:"schemaVersion"`
	GeneratedAt     string              `json:"generatedAt"`
	Period          exportPeriod        `json:"period"`
	SettingsSummary exportSettings      `json:"settingsSummary"`
	Categories      []exportCategory    `json:"categories"`
	Subcategories   []exportSubcategory `json:"subcategories"`
	Entries         []exportEntry       `json:"entries"`
	Support         []exportEntry       `json:"support"`
	CheckIns        []exportCheckIn     `json:"checkIns"`
	Notes           []exportNote        `json:"notes"`
	Totals          exportTotals        `json:"totals"`
}

type exportPeriod struct {
	Start string `json:"start"`
	End   string `json:"end"`
	Days  int    `json:"days"`
}

type exportSettings struct {
	Timezone           string `json:"timezone"`
	WeekStart          int    `json:"weekStart"`
	DailyTargetMinutes int    `json:"dailyTargetMinutes"`
}

type exportCategory struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Role       string `json:"role"`
	Minutes    int    `json:"minutes"`
	EntryCount int    `json:"entryCount"`
}

type exportSubcategory struct {
	ID            string            `json:"id"`
	CategoryID    string            `json:"categoryId"`
	Name          string            `json:"name"`
	Minutes       int               `json:"minutes"`
	EntryCount    int               `json:"entryCount"`
	Status        string            `json:"status"`
	Progress      int               `json:"progress"`
	TargetOutcome string            `json:"targetOutcome"`
	TargetDate    string            `json:"targetDate"`
	Links         []exportLink      `json:"links"`
	Milestones    []exportMilestone `json:"milestones"`
}

type exportLink struct {
	Label string `json:"label"`
	URL   string `json:"url"`
}

type exportMilestone struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	DueDate string `json:"dueDate"`
	Done    bool   `json:"done"`
}

type exportEntry struct {
	ID            string       `json:"id"`
	Date          string       `json:"date"`
	StartedAt     string       `json:"startedAt"`
	EndedAt       string       `json:"endedAt"`
	Minutes       int          `json:"minutes"`
	CategoryID    string       `json:"categoryId"`
	Category      string       `json:"category"`
	SubcategoryID string       `json:"subcategoryId"`
	Subcategory   string       `json:"subcategory"`
	Description   string       `json:"description"`
	Outcome       string       `json:"outcome"`
	People        []string     `json:"people"`
	Team          string       `json:"team"`
	Tags          []string     `json:"tags"`
	Source        string       `json:"source"`
	Links         []exportLink `json:"links"`
}

type exportCheckIn struct {
	ID              string `json:"id"`
	Kind            string `json:"kind"`
	PeriodStart     string `json:"periodStart"`
	PeriodEnd       string `json:"periodEnd"`
	State           string `json:"state"`
	Audience        string `json:"audience"`
	FocusNotes      string `json:"focusNotes"`
	SummaryMarkdown string `json:"summaryMarkdown"`
	PromptVersion   string `json:"promptVersion"`
	CreatedAt       string `json:"createdAt"`
}

type exportNote struct {
	ID            string `json:"id"`
	Date          string `json:"date"`
	SubcategoryID string `json:"subcategoryId"`
	Text          string `json:"text"`
	CreatedAt     string `json:"createdAt"`
}

type exportTotals struct {
	Minutes             int `json:"minutes"`
	EntryCount          int `json:"entryCount"`
	SupportMinutes      int `json:"supportMinutes"`
	SupportInteractions int `json:"supportInteractions"`
	Projects            int `json:"projects"`
	Days                int `json:"days"`
}

// --- helpers ---------------------------------------------------------------

func toExportEntry(entry WorkEntry, categories map[string]Category, subcategories map[string]Subcategory) exportEntry {
	links := make([]exportLink, 0, len(entry.Links))
	for _, link := range entry.Links {
		links = append(links, exportLink{Label: link.Label, URL: link.URL})
	}
	tags := entry.Tags
	if tags == nil {
		tags = []string{}
	}
	people := entry.People
	if people == nil {
		people = []string{}
	}
	return exportEntry{
		ID:            entry.ID,
		Date:          entry.LocalDate,
		StartedAt:     formatInstant(entry.StartedAt),
		EndedAt:       formatInstant(entry.EndedAt),
		Minutes:       entry.DurationMinutes(),
		CategoryID:    entry.CategoryID,
		Category:      categories[entry.CategoryID].Name,
		SubcategoryID: entry.SubcategoryID,
		Subcategory:   subcategories[entry.SubcategoryID].Name,
		Description:   entry.Description,
		Outcome:       entry.Outcome,
		People:        people,
		Team:          entry.Team,
		Tags:          tags,
		Source:        string(entry.Source),
		Links:         links,
	}
}

func indexCategories(categories []Category) map[string]Category {
	index := make(map[string]Category, len(categories))
	for _, category := range categories {
		index[category.ID] = category
	}
	return index
}

func indexSubcategories(subcategories []Subcategory) map[string]Subcategory {
	index := make(map[string]Subcategory, len(subcategories))
	for _, subcategory := range subcategories {
		index[subcategory.ID] = subcategory
	}
	return index
}

func sortedInitiativeCategories(categories []CategoryTotal) []CategoryTotal {
	result := make([]CategoryTotal, 0)
	for _, category := range categories {
		if category.Role == CategoryRoleInitiative {
			result = append(result, category)
		}
	}
	return result
}

func initiativeSubcategoryTotals(report PeriodReport) []SubcategoryTotal {
	byID := make(map[string]CategoryTotal, len(report.Categories))
	for _, category := range report.Categories {
		byID[category.CategoryID] = category
	}
	result := make([]SubcategoryTotal, 0)
	for _, subcategory := range report.Subcategories {
		if byID[subcategory.CategoryID].Role == CategoryRoleInitiative {
			result = append(result, subcategory)
		}
	}
	return result
}

func subcategoriesInCategory(subcategories []SubcategoryTotal, categoryID string) []SubcategoryTotal {
	result := make([]SubcategoryTotal, 0)
	for _, subcategory := range subcategories {
		if subcategory.CategoryID == categoryID {
			result = append(result, subcategory)
		}
	}
	return result
}

func milestoneCounts(milestones []Milestone, subcategoryID string) (done, total int) {
	for _, milestone := range milestones {
		if milestone.SubcategoryID != subcategoryID {
			continue
		}
		total++
		if milestone.Done {
			done++
		}
	}
	return done, total
}

func sortedMilestones(milestones []Milestone, subcategoryID string) []Milestone {
	result := make([]Milestone, 0)
	for _, milestone := range milestones {
		if milestone.SubcategoryID == subcategoryID {
			result = append(result, milestone)
		}
	}
	sort.Slice(result, func(i, j int) bool {
		if (result[i].DueDate == "") != (result[j].DueDate == "") {
			return result[j].DueDate == ""
		}
		if result[i].DueDate != result[j].DueDate {
			return result[i].DueDate < result[j].DueDate
		}
		return result[i].CreatedAt.Before(result[j].CreatedAt)
	})
	return result
}

// projectOutcomes returns up to five distinct outcomes, newest first, for one
// project. Only recorded outcomes are listed; the builder never invents one.
func projectOutcomes(entries []WorkEntry, subcategoryID string) []string {
	sorted := sortedEntries(entries)
	seen := make(map[string]struct{})
	result := make([]string, 0)
	for _, entry := range sorted {
		if entry.SubcategoryID != subcategoryID {
			continue
		}
		outcome := oneLine(entry.Outcome)
		if outcome == "" {
			continue
		}
		key := strings.ToLower(outcome)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, outcome)
		if len(result) == 5 {
			break
		}
	}
	return result
}

func supportTeam(entries []WorkEntry, person string) string {
	for _, entry := range entries {
		if entrySupportsPerson(entry, person) && strings.TrimSpace(entry.Team) != "" {
			return strings.TrimSpace(entry.Team)
		}
	}
	return ""
}

// entrySupportsPerson reports whether any name on the entry matches, using the
// same case-insensitive comparison as the person filter.
func entrySupportsPerson(entry WorkEntry, person string) bool {
	target := strings.TrimSpace(person)
	for _, name := range entry.People {
		if strings.EqualFold(strings.TrimSpace(name), target) {
			return true
		}
	}
	return false
}

func supportDetails(input ExportInput, person string, subcategories map[string]Subcategory) []string {
	sorted := sortedEntries(input.Entries)
	result := make([]string, 0)
	for _, entry := range sorted {
		if !entrySupportsPerson(entry, person) {
			continue
		}
		mode := subcategories[entry.SubcategoryID].Name
		if mode == "" {
			mode = valueOrDash(entry.SubcategoryID)
		}
		detail := mode
		if description := oneLine(entry.Description); description != "" {
			detail += ": " + description
		}
		if outcome := oneLine(entry.Outcome); outcome != "" {
			detail += " — " + outcome
		}
		result = append(result, detail)
		if len(result) == 5 {
			break
		}
	}
	return result
}

func sortedEntries(entries []WorkEntry) []WorkEntry {
	result := make([]WorkEntry, len(entries))
	copy(result, entries)
	sort.Slice(result, func(i, j int) bool {
		if !result[i].StartedAt.Equal(result[j].StartedAt) {
			return result[i].StartedAt.Before(result[j].StartedAt)
		}
		return result[i].ID < result[j].ID
	})
	return result
}

// supportMinutes returns the authoritative support total. Adding up the
// per-person rows would double-count a two-person entry, because each name is
// credited the entry's full minutes.
func supportMinutes(report PeriodReport) int {
	return report.SupportMinutes
}

// supportInteractionCount returns the authoritative number of support entries.
func supportInteractionCount(report PeriodReport) int {
	return report.SupportInteractions
}

func periodDays(fromDate, toDate string) int {
	from, fromErr := time.Parse(DateLayout, fromDate)
	to, toErr := time.Parse(DateLayout, toDate)
	if fromErr != nil || toErr != nil {
		return 0
	}
	days := int(to.Sub(from).Hours()/24) + 1
	if days < 0 {
		return 0
	}
	return days
}

// formatExportDuration renders explicit hours and minutes, e.g. `213h 00m`.
func formatExportDuration(minutes int) string {
	if minutes < 0 {
		minutes = 0
	}
	return fmt.Sprintf("%dh %02dm", minutes/60, minutes%60)
}

func share(minutes, total int) int {
	if total <= 0 || minutes <= 0 {
		return 0
	}
	return int(float64(minutes)*100/float64(total) + 0.5)
}

func formatInstant(value time.Time) string {
	if value.IsZero() {
		return ""
	}
	return value.UTC().Format(time.RFC3339)
}

// markdownCell keeps a table row on one line and neutralises a literal pipe.
func markdownCell(value string) string {
	value = oneLine(value)
	if value == "" {
		return "—"
	}
	return strings.ReplaceAll(value, "|", "\\|")
}

func oneLine(value string) string {
	return strings.Join(strings.Fields(value), " ")
}

func valueOrDash(value string) string {
	if strings.TrimSpace(value) == "" {
		return "—"
	}
	return oneLine(value)
}

func titleCase(value string) string {
	if value == "" {
		return ""
	}
	return strings.ToUpper(value[:1]) + value[1:]
}
