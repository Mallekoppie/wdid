package domain

import (
	"regexp"
	"slices"
)

// redactedURL replaces a URL in a generation payload. The marker makes the
// redaction visible to the user and to the model, without leaking the target.
const redactedURL = "[link removed]"

// urlPattern matches any URL scheme (http, https, ftp, file, ssh, …) plus a
// mailto: address, up to whitespace or the punctuation that commonly closes a
// Markdown link. Matching only http(s) would leave credentials or local paths
// in the payload sent to a provider.
var urlPattern = regexp.MustCompile(`(?i)(?:[a-z][a-z0-9+.-]*://|mailto:)[^\s)>\]]+`)

// RedactExportInput strips URLs and notes from a bundle before it is sent to an
// AI provider. It is a copy-on-write transformation: the stored export input is
// never mutated, so an export still contains the user's complete data.
//
// Notes are removed entirely (day and project notes, focus notes and a
// check-in's own summary). URLs are cleared from every link list and replaced
// with a marker wherever they appear in free text.
func RedactExportInput(input ExportInput) ExportInput {
	// Clone every slice before changing an element so the caller's input (and
	// therefore an export built from it) stays complete.
	input.Report.Categories = slices.Clone(input.Report.Categories)
	input.Report.Subcategories = slices.Clone(input.Report.Subcategories)
	input.Report.SupportPeople = slices.Clone(input.Report.SupportPeople)
	input.Report.SupportModes = slices.Clone(input.Report.SupportModes)
	input.Report.Weeks = slices.Clone(input.Report.Weeks)
	input.Report.Notes = nil
	input.Entries = slices.Clone(input.Entries)
	input.Categories = slices.Clone(input.Categories)
	input.Subcategories = slices.Clone(input.Subcategories)
	input.Milestones = slices.Clone(input.Milestones)
	input.CheckIns = slices.Clone(input.CheckIns)
	input.FocusNotes = ""

	for index := range input.Report.Categories {
		input.Report.Categories[index].Name = redactText(input.Report.Categories[index].Name)
	}
	for index := range input.Report.Subcategories {
		subcategory := &input.Report.Subcategories[index]
		subcategory.Name = redactText(subcategory.Name)
		subcategory.LastActivityDescription = redactText(subcategory.LastActivityDescription)
	}
	for index := range input.Report.SupportPeople {
		input.Report.SupportPeople[index].Person = redactText(input.Report.SupportPeople[index].Person)
	}
	for index := range input.Report.SupportModes {
		input.Report.SupportModes[index].Name = redactText(input.Report.SupportModes[index].Name)
	}
	for index := range input.Report.Weeks {
		input.Report.Weeks[index].TopCategoryName = redactText(input.Report.Weeks[index].TopCategoryName)
	}

	for index := range input.Entries {
		entry := &input.Entries[index]
		entry.Description = redactText(entry.Description)
		entry.Outcome = redactText(entry.Outcome)
		entry.People = redactStrings(entry.People)
		entry.Team = redactText(entry.Team)
		entry.Tags = redactStrings(entry.Tags)
		entry.Links = nil
	}

	for index := range input.Categories {
		input.Categories[index].Name = redactText(input.Categories[index].Name)
	}
	for index := range input.Subcategories {
		subcategory := &input.Subcategories[index]
		subcategory.Name = redactText(subcategory.Name)
		subcategory.TargetOutcome = redactText(subcategory.TargetOutcome)
		subcategory.Links = nil
	}
	for index := range input.Milestones {
		input.Milestones[index].Title = redactText(input.Milestones[index].Title)
	}

	// A prompt never contains a check-in's stored summary, but redact the
	// copies too so no caller can accidentally forward one.
	for index := range input.CheckIns {
		input.CheckIns[index].FocusNotes = ""
		input.CheckIns[index].SummaryMarkdown = ""
	}

	return input
}

func redactText(value string) string {
	if value == "" {
		return value
	}
	return urlPattern.ReplaceAllString(value, redactedURL)
}

func redactStrings(values []string) []string {
	if values == nil {
		return nil
	}
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = redactText(value)
	}
	return result
}
