package api

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/Mallekoppie/goslow/platform"
	"github.com/gorilla/mux"
	"go.uber.org/zap"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/store"
)

// API wires HTTP handlers to the service layer.
type API struct {
	store *store.Store
	auth  *auth.Service
	cfg   config.Config
}

// New builds the HTTP API.
func New(database *store.Store, authService *auth.Service, cfg config.Config) *API {
	return &API{store: database, auth: authService, cfg: cfg}
}

// Routes returns the goslow route table.
//
// Protected handlers wrap themselves with the auth middleware instead of using
// goslow's AuthRequired flag: the service accepts either a local token or a
// Zitadel ID token, and goslow's router applies its configured auth middlewares
// exclusively rather than as alternatives.
func (a *API) Routes() platform.Routes {
	return platform.Routes{
		{Path: "/healthz", Method: http.MethodGet, HandlerFunc: a.health, SlaMs: 50},

		{Path: "/api/v1/auth/register", Method: http.MethodPost, HandlerFunc: a.register, SlaMs: 500},
		{Path: "/api/v1/auth/login", Method: http.MethodPost, HandlerFunc: a.login, SlaMs: 500},
		{Path: "/api/v1/auth/config", Method: http.MethodGet, HandlerFunc: a.authConfig, SlaMs: 50},
		{Path: "/api/v1/auth/me", Method: http.MethodGet, HandlerFunc: a.protected(a.me), SlaMs: 100},

		{Path: "/api/v1/initiatives", Method: http.MethodGet, HandlerFunc: a.protected(a.listInitiatives)},
		{Path: "/api/v1/initiatives", Method: http.MethodPost, HandlerFunc: a.protected(a.createInitiative)},
		{Path: "/api/v1/initiatives/{id}", Method: http.MethodGet, HandlerFunc: a.protected(a.getInitiative)},
		{Path: "/api/v1/initiatives/{id}", Method: http.MethodPatch, HandlerFunc: a.protected(a.patchInitiative)},
		{Path: "/api/v1/initiatives/{id}", Method: http.MethodDelete, HandlerFunc: a.protected(a.deleteInitiative)},

		{Path: "/api/v1/entries", Method: http.MethodGet, HandlerFunc: a.protected(a.listEntries)},
		{Path: "/api/v1/entries", Method: http.MethodPost, HandlerFunc: a.protected(a.createEntry)},
		{Path: "/api/v1/entries/{id}", Method: http.MethodGet, HandlerFunc: a.protected(a.getEntry)},
		{Path: "/api/v1/entries/{id}", Method: http.MethodPatch, HandlerFunc: a.protected(a.patchEntry)},
		{Path: "/api/v1/entries/{id}", Method: http.MethodDelete, HandlerFunc: a.protected(a.deleteEntry)},

		{Path: "/api/v1/timer", Method: http.MethodGet, HandlerFunc: a.protected(a.getTimer)},
		{Path: "/api/v1/timer/start", Method: http.MethodPost, HandlerFunc: a.protected(a.startTimer)},
		{Path: "/api/v1/timer/pause", Method: http.MethodPost, HandlerFunc: a.protected(a.pauseTimer)},
		{Path: "/api/v1/timer/resume", Method: http.MethodPost, HandlerFunc: a.protected(a.resumeTimer)},
		{Path: "/api/v1/timer/stop", Method: http.MethodPost, HandlerFunc: a.protected(a.stopTimer)},

		{Path: "/api/v1/summary", Method: http.MethodGet, HandlerFunc: a.protected(a.periodSummary), SlaMs: 500},
		{Path: "/api/v1/export", Method: http.MethodGet, HandlerFunc: a.protected(a.exportPeriod), SlaMs: 1000},
	}
}

func (a *API) protected(handler http.HandlerFunc) http.HandlerFunc {
	wrapped := a.auth.Middleware(handler)
	return wrapped.ServeHTTP
}

// --- responses -----------------------------------------------------------

type apiError struct {
	Code    string      `json:"code"`
	Message string      `json:"message"`
	Details interface{} `json:"details,omitempty"`
}

type errorResponse struct {
	Error apiError `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	platform.JsonMarshaller.WriteJsonResponse(w, status, payload)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, errorResponse{Error: apiError{Code: code, Message: message}})
}

func writeErrorWithDetails(w http.ResponseWriter, status int, code, message string, details interface{}) {
	writeJSON(w, status, errorResponse{Error: apiError{Code: code, Message: message, Details: details}})
}

// writeServiceError maps domain and store errors onto API responses.
func writeServiceError(w http.ResponseWriter, err error) {
	var validation domain.ValidationError
	switch {
	case errors.As(err, &validation):
		writeErrorWithDetails(w, http.StatusUnprocessableEntity, "validation_failed", validation.Error(), validation)
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found", "record not found")
	case errors.Is(err, store.ErrEmailExists):
		writeError(w, http.StatusConflict, "email_exists", "an account already uses this email address")
	default:
		platform.Log.Error("Request failed", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "internal_error", "the request could not be completed")
	}
}

func decodeJSON(r *http.Request, out interface{}) error {
	if r.Body == nil {
		return errors.New("request body is required")
	}
	if err := platform.JsonMarshaller.ReadJsonRequest(r.Body, out); err != nil {
		return fmt.Errorf("invalid JSON body: %w", err)
	}
	return nil
}

func caller(r *http.Request) (auth.Identity, bool) {
	return auth.IdentityFromContext(r.Context())
}

// muxVars isolates the gorilla dependency to one helper.
func muxVars(r *http.Request) map[string]string {
	return mux.Vars(r)
}

func pathID(r *http.Request, name string) string {
	value := r.PathValue(name)
	if value != "" {
		return value
	}
	// gorilla/mux populates path variables through its own context key, so fall
	// back to its helper when net/http does not provide the value.
	return muxVars(r)[name]
}

// --- request parsing -----------------------------------------------------

func parseOptionalTime(value string, fallback time.Time) (time.Time, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return fallback, nil
	}
	if parsed, err := time.Parse(time.RFC3339, trimmed); err == nil {
		return parsed, nil
	}
	if parsed, err := time.Parse("2006-01-02", trimmed); err == nil {
		return parsed, nil
	}
	return time.Time{}, fmt.Errorf("invalid time %q: use RFC3339 or YYYY-MM-DD", trimmed)
}

func parseWindow(r *http.Request, now time.Time) (time.Time, time.Time, error) {
	from, err := parseOptionalTime(r.URL.Query().Get("from"), now.AddDate(0, 0, -30))
	if err != nil {
		return time.Time{}, time.Time{}, err
	}
	to, err := parseOptionalTime(r.URL.Query().Get("to"), now)
	if err != nil {
		return time.Time{}, time.Time{}, err
	}
	if err := domain.ValidateTimeRange(from, to); err != nil {
		return time.Time{}, time.Time{}, err
	}
	return from, to, nil
}

func parseLimit(value string, fallback, maximum int) int {
	parsed, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || parsed <= 0 {
		return fallback
	}
	if parsed > maximum {
		return maximum
	}
	return parsed
}
