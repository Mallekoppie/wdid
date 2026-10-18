package export

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

// InitiativeTotal is the time attributed to one initiative.
type InitiativeTotal struct {
	InitiativeID string `json:"initiativeId"`
	Name         string `json:"name"`
	Minutes      int    `json:"minutes"`
	EntryCount   int    `json:"entryCount"`
}

// SupportTotal is the time spent supporting one person in one mode.
type SupportTotal struct {
	Person  string `json:"person"`
	Mode    string `json:"mode"`
	Minutes int    `json:"minutes"`
	Count   int    `json:"count"`
}

// Summary is a review-ready period rollup.
type Summary struct {
	From          time.Time         `json:"from"`
	To            time.Time         `json:"to"`
	TotalMinutes  int               `json:"totalMinutes"`
	EntryCount    int               `json:"entryCount"`
	ByKind        map[string]int    `json:"byKind"`
	ByInitiative  []InitiativeTotal `json:"byInitiative"`
	Support       []SupportTotal    `json:"support"`
	Outcomes      []string          `json:"outcomes"`
	InitiativeCnt int               `json:"initiativeCount"`
	SupportPeople int               `json:"supportPeople"`
}

// Summarize rolls up the entries that fall inside the period.
func Summarize(entries []domain.Entry, initiatives []domain.Initiative, from, to time.Time) Summary {
	names := make(map[string]string, len(initiatives))
	for _, initiative := range initiatives {
		names[initiative.ID] = initiative.Name
	}

	byInitiative := map[string]*InitiativeTotal{}
	bySupport := map[string]*SupportTotal{}
	people := map[string]struct{}{}
	byKind := map[string]int{}
	outcomes := make([]string, 0)
	seenOutcomes := map[string]struct{}{}

	summary := Summary{
		From:         from,
		To:           to,
		ByKind:       byKind,
		ByInitiative: []InitiativeTotal{},
		Support:      []SupportTotal{},
		Outcomes:     []string{},
	}

	for _, entry := range entries {
		if entry.StartedAt.Before(from) || !entry.StartedAt.Before(to) {
			continue
		}

		minutes := entry.DurationMinutes()
		summary.EntryCount++
		summary.TotalMinutes += minutes
		byKind[string(entry.Kind)] += minutes

		if entry.Kind == domain.EntryInitiative && entry.InitiativeID != "" {
			total, ok := byInitiative[entry.InitiativeID]
			if !ok {
				name := names[entry.InitiativeID]
				if name == "" {
					name = entry.InitiativeID
				}
				total = &InitiativeTotal{InitiativeID: entry.InitiativeID, Name: name}
				byInitiative[entry.InitiativeID] = total
			}
			total.Minutes += minutes
			total.EntryCount++
		}

		if entry.Kind == domain.EntrySupport && entry.Support != nil {
			key := strings.ToLower(entry.Support.Person) + "|" + string(entry.Support.Mode)
			total, ok := bySupport[key]
			if !ok {
				total = &SupportTotal{Person: entry.Support.Person, Mode: string(entry.Support.Mode)}
				bySupport[key] = total
			}
			total.Minutes += minutes
			total.Count++
			people[entry.Support.Person] = struct{}{}
		}

		if outcome := strings.TrimSpace(entry.Outcome); outcome != "" {
			key := strings.ToLower(outcome)
			if _, ok := seenOutcomes[key]; !ok {
				seenOutcomes[key] = struct{}{}
				outcomes = append(outcomes, outcome)
			}
		}
	}

	for _, total := range byInitiative {
		summary.ByInitiative = append(summary.ByInitiative, *total)
	}
	sort.Slice(summary.ByInitiative, func(i, j int) bool {
		if summary.ByInitiative[i].Minutes == summary.ByInitiative[j].Minutes {
			return summary.ByInitiative[i].Name < summary.ByInitiative[j].Name
		}
		return summary.ByInitiative[i].Minutes > summary.ByInitiative[j].Minutes
	})

	for _, total := range bySupport {
		summary.Support = append(summary.Support, *total)
	}
	sort.Slice(summary.Support, func(i, j int) bool {
		if summary.Support[i].Minutes == summary.Support[j].Minutes {
			return summary.Support[i].Person < summary.Support[j].Person
		}
		return summary.Support[i].Minutes > summary.Support[j].Minutes
	})

	sort.Strings(outcomes)
	summary.Outcomes = outcomes
	summary.InitiativeCnt = len(summary.ByInitiative)
	summary.SupportPeople = len(people)

	return summary
}

// Markdown renders the summary as a review-ready journal section.
func Markdown(summary Summary) string {
	var builder strings.Builder

	builder.WriteString("# wdid period summary\n\n")
	builder.WriteString(fmt.Sprintf("**Period:** %s -> %s\n",
		summary.From.Format("2006-01-02"), summary.To.Format("2006-01-02")))
	builder.WriteString(fmt.Sprintf("**Total:** %s across %d entries\n\n",
		FormatMinutes(summary.TotalMinutes), summary.EntryCount))

	builder.WriteString("## Time by type\n\n")
	for _, kind := range []string{"initiative", "support", "other"} {
		if minutes, ok := summary.ByKind[kind]; ok && minutes > 0 {
			builder.WriteString(fmt.Sprintf("- %s: %s\n", kind, FormatMinutes(minutes)))
		}
	}
	builder.WriteString("\n")

	builder.WriteString("## Time by initiative\n\n")
	if len(summary.ByInitiative) == 0 {
		builder.WriteString("_No initiative time in this period._\n\n")
	} else {
		for _, total := range summary.ByInitiative {
			builder.WriteString(fmt.Sprintf("- %s: %s across %d entries\n",
				total.Name, FormatMinutes(total.Minutes), total.EntryCount))
		}
		builder.WriteString("\n")
	}

	builder.WriteString("## Support\n\n")
	if len(summary.Support) == 0 {
		builder.WriteString("_No support entries in this period._\n\n")
	} else {
		for _, total := range summary.Support {
			builder.WriteString(fmt.Sprintf("- %s (%s): %s across %d interactions\n",
				total.Person, total.Mode, FormatMinutes(total.Minutes), total.Count))
		}
		builder.WriteString("\n")
	}

	builder.WriteString("## Outcomes\n\n")
	if len(summary.Outcomes) == 0 {
		builder.WriteString("_No outcomes recorded in this period._\n")
	} else {
		for _, outcome := range summary.Outcomes {
			builder.WriteString(fmt.Sprintf("- %s\n", outcome))
		}
	}

	return builder.String()
}

// FormatMinutes renders minutes as "4h 05m" or "42m".
func FormatMinutes(minutes int) string {
	if minutes < 0 {
		minutes = 0
	}
	hours := minutes / 60
	remainder := minutes % 60
	if hours == 0 {
		return fmt.Sprintf("%dm", remainder)
	}
	return fmt.Sprintf("%dh %02dm", hours, remainder)
}
