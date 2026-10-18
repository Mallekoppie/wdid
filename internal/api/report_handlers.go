package api

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/Mallekoppie/wdid/internal/export"
	"github.com/Mallekoppie/wdid/internal/store"
)

func (a *API) periodSummary(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	now := time.Now().UTC()
	from, to, err := parseWindow(r, now)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_range", err.Error())
		return
	}

	entries, err := a.store.Entries(identity.UserID, store.EntryFilter{From: from, To: to})
	if err != nil {
		writeServiceError(w, err)
		return
	}

	initiatives, err := a.store.Initiatives(identity.UserID)
	if err != nil {
		writeServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, export.Summarize(entries, initiatives, from, to))
}

func (a *API) exportPeriod(w http.ResponseWriter, r *http.Request) {
	identity, ok := caller(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "a valid bearer token is required")
		return
	}

	now := time.Now().UTC()
	from, to, err := parseWindow(r, now)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_range", err.Error())
		return
	}

	entries, err := a.store.Entries(identity.UserID, store.EntryFilter{From: from, To: to})
	if err != nil {
		writeServiceError(w, err)
		return
	}

	initiatives, err := a.store.Initiatives(identity.UserID)
	if err != nil {
		writeServiceError(w, err)
		return
	}

	summary := export.Summarize(entries, initiatives, from, to)

	switch strings.ToLower(strings.TrimSpace(r.URL.Query().Get("format"))) {
	case "", "markdown", "md":
		filename := fmt.Sprintf("wdid-%s-%s.md", from.Format("20060102"), to.Format("20060102"))
		w.Header().Set("Content-Type", "text/markdown; charset=utf-8")
		w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filename))
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, export.Markdown(summary))
	case "json":
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"summary": summary,
			"entries": entries,
		})
	default:
		writeError(w, http.StatusBadRequest, "invalid_format", "format must be markdown or json")
	}
}
