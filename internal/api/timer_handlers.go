package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

type timerView struct {
	Active          bool       `json:"active"`
	InitiativeID    string     `json:"initiativeId,omitempty"`
	Description     string     `json:"description,omitempty"`
	StartedAt       *time.Time `json:"startedAt,omitempty"`
	Paused          bool       `json:"paused"`
	ElapsedSeconds  int64      `json:"elapsedSeconds"`
	MaxBlockMinutes int        `json:"maxBlockMinutes"`
}

func (a *API) timerResponse(w http.ResponseWriter, status int, timer domain.ActiveTimer, now time.Time) {
	started := timer.StartedAt
	writeJSON(w, status, timerView{
		Active:          true,
		InitiativeID:    timer.InitiativeID,
		Description:     timer.Description,
		StartedAt:       &started,
		Paused:          timer.Paused(),
		ElapsedSeconds:  int64(timer.Elapsed(now).Seconds()),
		MaxBlockMinutes: a.cfg.MaxBlockMinutes,
	})
}

func (a *API) getTimer(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	now := time.Now().UTC()
	timer, active, err := a.store.ActiveTimer(identity.UserID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	if !active {
		writeJSON(w, http.StatusOK, timerView{
			Active:          false,
			MaxBlockMinutes: a.cfg.MaxBlockMinutes,
		})
		return
	}

	a.timerResponse(w, http.StatusOK, timer, now)
}

func (a *API) startTimer(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	var request struct {
		InitiativeID string `json:"initiativeId"`
		Description  string `json:"description"`
	}
	if err := decodeJSON(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}

	if err := domain.ValidateTimerStart(request.Description); err != nil {
		writeServiceError(w, err)
		return
	}

	if _, active, err := a.store.ActiveTimer(identity.UserID); err != nil {
		writeServiceError(w, err)
		return
	} else if active {
		writeError(w, http.StatusConflict, "timer_running", "a timer is already running")
		return
	}

	request.InitiativeID = strings.TrimSpace(request.InitiativeID)
	if request.InitiativeID != "" {
		if err := a.ensureInitiativeOwned(domain.Entry{
			UserID:       identity.UserID,
			Kind:         domain.EntryInitiative,
			InitiativeID: request.InitiativeID,
		}); err != nil {
			writeServiceError(w, err)
			return
		}
	}

	now := time.Now().UTC()
	timer := domain.ActiveTimer{
		UserID:           identity.UserID,
		InitiativeID:     request.InitiativeID,
		Description:      strings.TrimSpace(request.Description),
		StartedAt:        now,
		SegmentStartedAt: now,
	}

	if err := a.store.SaveTimer(timer); err != nil {
		writeServiceError(w, err)
		return
	}

	a.timerResponse(w, http.StatusCreated, timer, now)
}

func (a *API) pauseTimer(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	timer, active, err := a.store.ActiveTimer(identity.UserID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	if !active {
		writeError(w, http.StatusConflict, "timer_not_running", "no timer is running")
		return
	}
	if timer.Paused() {
		writeError(w, http.StatusConflict, "timer_paused", "the timer is already paused")
		return
	}

	now := time.Now().UTC()
	if segment := now.Sub(timer.SegmentStartedAt); segment > 0 {
		timer.AccumulatedSeconds += int64(segment.Seconds())
	}
	timer.PausedAt = &now
	timer.SegmentStartedAt = now

	if err := a.store.SaveTimer(timer); err != nil {
		writeServiceError(w, err)
		return
	}

	a.timerResponse(w, http.StatusOK, timer, now)
}

func (a *API) resumeTimer(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	timer, active, err := a.store.ActiveTimer(identity.UserID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	if !active {
		writeError(w, http.StatusConflict, "timer_not_running", "no timer is running")
		return
	}
	if !timer.Paused() {
		writeError(w, http.StatusConflict, "timer_not_paused", "the timer is not paused")
		return
	}

	now := time.Now().UTC()
	timer.PausedAt = nil
	timer.SegmentStartedAt = now

	if err := a.store.SaveTimer(timer); err != nil {
		writeServiceError(w, err)
		return
	}

	a.timerResponse(w, http.StatusOK, timer, now)
}

func (a *API) stopTimer(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	var request struct {
		Action      string   `json:"action"`
		Description string   `json:"description"`
		Outcome     string   `json:"outcome"`
		Tags        []string `json:"tags"`
		Links       []string `json:"links"`
	}
	if err := decodeJSON(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}

	action := strings.ToLower(strings.TrimSpace(request.Action))
	switch action {
	case "", "keep", "trim", "discard":
	default:
		writeError(w, http.StatusBadRequest, "invalid_action", "action must be keep, trim or discard")
		return
	}

	timer, active, err := a.store.ActiveTimer(identity.UserID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	if !active {
		writeError(w, http.StatusConflict, "timer_not_running", "no timer is running")
		return
	}

	now := time.Now().UTC()
	elapsed := timer.Elapsed(now)

	if action == "discard" {
		if err := a.store.ClearTimer(identity.UserID); err != nil {
			writeServiceError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]interface{}{"discarded": true})
		return
	}

	if elapsed < time.Minute {
		writeErrorWithDetails(w, http.StatusConflict, "timer_too_short",
			"the timer has run for less than a minute",
			map[string]interface{}{"elapsedSeconds": int64(elapsed.Seconds())})
		return
	}

	minutes := int(elapsed.Minutes())
	if minutes > a.cfg.MaxBlockMinutes && action == "" {
		writeErrorWithDetails(w, http.StatusConflict, "block_limit_exceeded",
			"the timer exceeded the maximum block length; choose keep, trim or discard",
			map[string]interface{}{
				"elapsedMinutes":  minutes,
				"maxBlockMinutes": a.cfg.MaxBlockMinutes,
			})
		return
	}
	if action == "trim" && minutes > a.cfg.MaxBlockMinutes {
		minutes = a.cfg.MaxBlockMinutes
	}

	description := strings.TrimSpace(request.Description)
	if description == "" {
		description = timer.Description
	}

	kind := domain.EntryOther
	if timer.InitiativeID != "" {
		kind = domain.EntryInitiative
	}

	entry := domain.Entry{
		ID:           domain.NewID(),
		UserID:       identity.UserID,
		Kind:         kind,
		InitiativeID: timer.InitiativeID,
		Description:  description,
		Outcome:      request.Outcome,
		StartedAt:    timer.StartedAt,
		EndedAt:      now,
		Minutes:      minutes,
		Tags:         request.Tags,
		Links:        request.Links,
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	entry.Normalize()
	if err := domain.ValidateEntry(entry, 0); err != nil {
		writeServiceError(w, err)
		return
	}
	if timer.InitiativeID != "" {
		if _, err := a.store.Initiative(identity.UserID, timer.InitiativeID); err != nil {
			if errors.Is(err, store.ErrNotFound) {
				writeServiceError(w, domain.ValidationError{Field: "initiativeId", Message: "initiative not found"})
				return
			}
			writeServiceError(w, err)
			return
		}
	}

	if err := a.store.SaveEntry(entry); err != nil {
		writeServiceError(w, err)
		return
	}
	if err := a.store.ClearTimer(identity.UserID); err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, entry)
}
