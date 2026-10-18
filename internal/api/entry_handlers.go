package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

type entryRequest struct {
	Kind            domain.EntryKind      `json:"kind"`
	InitiativeID    string                `json:"initiativeId"`
	Description     string                `json:"description"`
	Outcome         string                `json:"outcome"`
	StartedAt       time.Time             `json:"startedAt"`
	EndedAt         time.Time             `json:"endedAt"`
	DurationMinutes int                   `json:"durationMinutes"`
	Support         *domain.SupportDetail `json:"support"`
	Tags            []string              `json:"tags"`
	Links           []string              `json:"links"`
}

type entryPatch struct {
	Kind         *domain.EntryKind     `json:"kind"`
	InitiativeID *string               `json:"initiativeId"`
	Description  *string               `json:"description"`
	Outcome      *string               `json:"outcome"`
	StartedAt    *time.Time            `json:"startedAt"`
	EndedAt      *time.Time            `json:"endedAt"`
	Minutes      *int                  `json:"minutes"`
	Support      *domain.SupportDetail `json:"support"`
	Tags         *[]string             `json:"tags"`
	Links        *[]string             `json:"links"`
}

func (a *API) listEntries(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	query := r.URL.Query()
	filter := store.EntryFilter{
		InitiativeID: strings.TrimSpace(query.Get("initiativeId")),
		Query:        query.Get("q"),
		Limit:        parseLimit(query.Get("limit"), 200, 1000),
	}

	if rawKind := strings.TrimSpace(query.Get("kind")); rawKind != "" {
		filter.Kind = domain.EntryKind(rawKind)
		if !filter.Kind.Valid() {
			writeError(w, http.StatusBadRequest, "invalid_kind", "kind must be initiative, support or other")
			return
		}
	}

	from, err := parseOptionalTime(query.Get("from"), time.Time{})
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_range", err.Error())
		return
	}
	to, err := parseOptionalTime(query.Get("to"), time.Time{})
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_range", err.Error())
		return
	}
	if !from.IsZero() && !to.IsZero() {
		if err := domain.ValidateTimeRange(from, to); err != nil {
			writeServiceError(w, err)
			return
		}
	}
	filter.From = from
	filter.To = to

	entries, err := a.store.Entries(identity.UserID, filter)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	if entries == nil {
		entries = []domain.Entry{}
	}

	writeJSON(w, http.StatusOK, entries)
}

func (a *API) createEntry(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	var request entryRequest
	if err := decodeJSON(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}

	now := time.Now().UTC()
	entry := domain.Entry{
		ID:           domain.NewID(),
		UserID:       identity.UserID,
		Kind:         request.Kind,
		InitiativeID: request.InitiativeID,
		Description:  request.Description,
		Outcome:      request.Outcome,
		StartedAt:    request.StartedAt,
		EndedAt:      request.EndedAt,
		Minutes:      request.DurationMinutes,
		Support:      request.Support,
		Tags:         request.Tags,
		Links:        request.Links,
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	if entry.Kind == "" {
		entry.Kind = inferKind(entry)
	}
	if entry.StartedAt.IsZero() {
		entry.StartedAt = now
	}
	if entry.Minutes > 0 && entry.EndedAt.IsZero() {
		entry.EndedAt = entry.StartedAt.Add(time.Duration(entry.Minutes) * time.Minute)
	}
	if entry.Minutes == 0 && entry.EndedAt.After(entry.StartedAt) {
		entry.Minutes = int(entry.EndedAt.Sub(entry.StartedAt).Minutes())
	}

	entry.Normalize()
	if err := domain.ValidateEntry(entry, a.cfg.MaxBlockMinutes); err != nil {
		writeServiceError(w, err)
		return
	}
	if err := a.ensureInitiativeOwned(entry); err != nil {
		writeServiceError(w, err)
		return
	}
	if err := a.store.SaveEntry(entry); err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, entry)
}

func (a *API) getEntry(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	entry, err := a.store.Entry(identity.UserID, pathID(r, "id"))
	if err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, entry)
}

func (a *API) patchEntry(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	var patch entryPatch
	if err := decodeJSON(r, &patch); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}

	entry, err := a.store.Entry(identity.UserID, pathID(r, "id"))
	if err != nil {
		writeServiceError(w, err)
		return
	}

	if patch.Kind != nil {
		entry.Kind = *patch.Kind
	}
	if patch.InitiativeID != nil {
		entry.InitiativeID = *patch.InitiativeID
	}
	if patch.Description != nil {
		entry.Description = *patch.Description
	}
	if patch.Outcome != nil {
		entry.Outcome = *patch.Outcome
	}
	if patch.StartedAt != nil {
		entry.StartedAt = *patch.StartedAt
	}
	if patch.EndedAt != nil {
		entry.EndedAt = *patch.EndedAt
	}
	if patch.Support != nil {
		entry.Support = patch.Support
	}
	if patch.Tags != nil {
		entry.Tags = *patch.Tags
	}
	if patch.Links != nil {
		entry.Links = *patch.Links
	}

	if patch.Minutes != nil {
		entry.Minutes = *patch.Minutes
	} else if patch.StartedAt != nil || patch.EndedAt != nil {
		// Recompute from the edited timestamps.
		entry.Minutes = 0
	}

	entry.Normalize()
	if err := domain.ValidateEntry(entry, a.cfg.MaxBlockMinutes); err != nil {
		writeServiceError(w, err)
		return
	}
	if err := a.ensureInitiativeOwned(entry); err != nil {
		writeServiceError(w, err)
		return
	}

	entry.UpdatedAt = time.Now().UTC()
	if err := a.store.SaveEntry(entry); err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, entry)
}

func (a *API) deleteEntry(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	if err := a.store.DeleteEntry(identity.UserID, pathID(r, "id")); err != nil {
		writeServiceError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func inferKind(entry domain.Entry) domain.EntryKind {
	switch {
	case entry.Support != nil:
		return domain.EntrySupport
	case strings.TrimSpace(entry.InitiativeID) != "":
		return domain.EntryInitiative
	default:
		return domain.EntryOther
	}
}

func (a *API) ensureInitiativeOwned(entry domain.Entry) error {
	if entry.Kind != domain.EntryInitiative {
		return nil
	}

	if _, err := a.store.Initiative(entry.UserID, entry.InitiativeID); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return domain.ValidationError{Field: "initiativeId", Message: "initiative not found"}
		}
		return err
	}

	return nil
}
