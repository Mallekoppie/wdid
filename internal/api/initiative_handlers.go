package api

import (
	"net/http"
	"time"

	"github.com/Mallekoppie/wdid/internal/domain"
)

type initiativeRequest struct {
	Name          string                  `json:"name"`
	Status        domain.InitiativeStatus `json:"status"`
	TargetOutcome string                  `json:"targetOutcome"`
	Progress      int                     `json:"progress"`
	Links         []string                `json:"links"`
}

type initiativePatch struct {
	Name          *string                  `json:"name"`
	Status        *domain.InitiativeStatus `json:"status"`
	TargetOutcome *string                  `json:"targetOutcome"`
	Progress      *int                     `json:"progress"`
	Links         *[]string                `json:"links"`
}

func (a *API) listInitiatives(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	initiatives, err := a.store.Initiatives(identity.UserID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	if initiatives == nil {
		initiatives = []domain.Initiative{}
	}

	writeJSON(w, http.StatusOK, initiatives)
}

func (a *API) createInitiative(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	var request initiativeRequest
	if err := decodeJSON(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}

	now := time.Now().UTC()
	initiative := domain.Initiative{
		ID:            domain.NewID(),
		UserID:        identity.UserID,
		Name:          request.Name,
		Status:        request.Status,
		TargetOutcome: request.TargetOutcome,
		Progress:      request.Progress,
		Links:         request.Links,
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	if initiative.Status == "" {
		initiative.Status = domain.InitiativePlanned
	}

	initiative.Normalize()
	if err := domain.ValidateInitiative(initiative); err != nil {
		writeServiceError(w, err)
		return
	}

	if err := a.store.SaveInitiative(initiative); err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, initiative)
}

func (a *API) getInitiative(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	initiative, err := a.store.Initiative(identity.UserID, pathID(r, "id"))
	if err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, initiative)
}

func (a *API) patchInitiative(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	var patch initiativePatch
	if err := decodeJSON(r, &patch); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}

	initiative, err := a.store.Initiative(identity.UserID, pathID(r, "id"))
	if err != nil {
		writeServiceError(w, err)
		return
	}

	if patch.Name != nil {
		initiative.Name = *patch.Name
	}
	if patch.Status != nil {
		initiative.Status = *patch.Status
	}
	if patch.TargetOutcome != nil {
		initiative.TargetOutcome = *patch.TargetOutcome
	}
	if patch.Progress != nil {
		initiative.Progress = *patch.Progress
	}
	if patch.Links != nil {
		initiative.Links = *patch.Links
	}

	initiative.Normalize()
	if err := domain.ValidateInitiative(initiative); err != nil {
		writeServiceError(w, err)
		return
	}

	initiative.UpdatedAt = time.Now().UTC()
	if err := a.store.SaveInitiative(initiative); err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, initiative)
}

func (a *API) deleteInitiative(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	if err := a.store.DeleteInitiative(identity.UserID, pathID(r, "id")); err != nil {
		writeServiceError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
