package domain

import (
	"sort"
	"time"
)

// OverlappingEntryIDs returns the ids of entries whose half-open time spans
// intersect another entry's span. Manual entries may overlap, so the Log marks
// the affected rows instead of blocking the capture. Adjacent blocks do not
// overlap, and zero-length entries never do.
func OverlappingEntryIDs(entries []WorkEntry) []string {
	flagged := make(map[string]struct{})
	for i := range entries {
		first := entries[i]
		firstEnd := first.StartedAt.Add(time.Duration(first.DurationMinutes()) * time.Minute)
		if !firstEnd.After(first.StartedAt) {
			continue
		}
		for j := i + 1; j < len(entries); j++ {
			second := entries[j]
			secondEnd := second.StartedAt.Add(time.Duration(second.DurationMinutes()) * time.Minute)
			if !secondEnd.After(second.StartedAt) {
				continue
			}
			if first.StartedAt.Before(secondEnd) && second.StartedAt.Before(firstEnd) {
				flagged[first.ID] = struct{}{}
				flagged[second.ID] = struct{}{}
			}
		}
	}

	ids := make([]string, 0, len(flagged))
	for id := range flagged {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}
