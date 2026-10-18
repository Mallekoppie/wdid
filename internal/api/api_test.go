package api_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Mallekoppie/goslow/platform"

	"github.com/Mallekoppie/wdid/internal/api"
	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	"github.com/Mallekoppie/wdid/internal/export"
	"github.com/Mallekoppie/wdid/internal/store"
)

const testSecret = "test-registration-secret"

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()

	cfg := config.Config{
		HTTPAddr:             "127.0.0.1:0",
		DBPath:               filepath.Join(t.TempDir(), "wdid-api.db"),
		RegistrationSecret:   testSecret,
		JWTSecret:            strings.Repeat("k", 32),
		JWTSigningMethod:     "HS256",
		JWTExpirationMinutes: 60,
		MaxBlockMinutes:      240,
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("test config invalid: %v", err)
	}

	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		_ = database.Close()
	})

	authService := auth.NewService(database, cfg)
	handler := api.New(database, authService, cfg)

	application, err := platform.NewApplicationHandler(platform.ApplicationServerOptions{
		Routes:       handler.Routes(),
		ServiceNames: []string{config.AuthServiceName},
	})
	if err != nil {
		t.Fatalf("build application handler: %v", err)
	}

	server := httptest.NewServer(application)
	t.Cleanup(server.Close)

	return server
}

func doJSON(t *testing.T, method, target, token string, payload interface{}) (*http.Response, []byte) {
	t.Helper()

	var body io.Reader
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			t.Fatalf("marshal request: %v", err)
		}
		body = bytes.NewReader(encoded)
	}

	request, err := http.NewRequest(method, target, body)
	if err != nil {
		t.Fatalf("build request: %v", err)
	}
	request.Header.Set("Content-Type", "application/json")
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("do request: %v", err)
	}

	data, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatalf("read response: %v", err)
	}
	response.Body.Close()

	return response, data
}

func TestAPIFlow(t *testing.T) {
	server := newTestServer(t)
	base := server.URL

	response, _ := doJSON(t, http.MethodGet, base+"/api/v1/entries", "", nil)
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("unauthenticated status = %d, want 401", response.StatusCode)
	}

	response, _ = doJSON(t, http.MethodPost, base+"/api/v1/auth/register", "", map[string]string{
		"email":              "dev@example.com",
		"password":           "longenough1",
		"displayName":        "Dev",
		"registrationSecret": "wrong-secret-value",
	})
	if response.StatusCode != http.StatusForbidden {
		t.Fatalf("bad secret status = %d, want 403", response.StatusCode)
	}

	response, body := doJSON(t, http.MethodPost, base+"/api/v1/auth/register", "", map[string]string{
		"email":              "dev@example.com",
		"password":           "longenough1",
		"displayName":        "Dev",
		"registrationSecret": testSecret,
	})
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("register status = %d, want 201: %s", response.StatusCode, body)
	}

	var registration struct {
		User  domain.User `json:"user"`
		Token string      `json:"token"`
	}
	if err := json.Unmarshal(body, &registration); err != nil {
		t.Fatalf("decode registration: %v", err)
	}
	if registration.User.Role != domain.RoleAdmin {
		t.Fatalf("first user role = %q, want admin", registration.User.Role)
	}
	if registration.Token == "" {
		t.Fatal("register returned an empty token")
	}
	token := registration.Token

	response, body = doJSON(t, http.MethodGet, base+"/api/v1/auth/me", token, nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("me status = %d, want 200: %s", response.StatusCode, body)
	}

	response, body = doJSON(t, http.MethodPost, base+"/api/v1/initiatives", token, map[string]interface{}{
		"name":          "Billing migration",
		"status":        "active",
		"targetOutcome": "Cut invoice time",
	})
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("create initiative status = %d, want 201: %s", response.StatusCode, body)
	}

	var initiative domain.Initiative
	if err := json.Unmarshal(body, &initiative); err != nil {
		t.Fatalf("decode initiative: %v", err)
	}

	response, body = doJSON(t, http.MethodPost, base+"/api/v1/entries", token, map[string]interface{}{
		"description":     "Backfill script",
		"initiativeId":    initiative.ID,
		"durationMinutes": 30,
		"outcome":         "Script runs against staging",
	})
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("create entry status = %d, want 201: %s", response.StatusCode, body)
	}

	var entry domain.Entry
	if err := json.Unmarshal(body, &entry); err != nil {
		t.Fatalf("decode entry: %v", err)
	}
	if entry.Kind != domain.EntryInitiative || entry.InitiativeID != initiative.ID {
		t.Fatalf("entry attribution = %q/%q", entry.Kind, entry.InitiativeID)
	}
	if entry.Minutes != 30 {
		t.Fatalf("entry minutes = %d, want 30", entry.Minutes)
	}

	response, body = doJSON(t, http.MethodPost, base+"/api/v1/entries", token, map[string]interface{}{
		"kind":            "initiative",
		"description":     "Missing initiative",
		"durationMinutes": 10,
	})
	if response.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("invalid entry status = %d, want 422: %s", response.StatusCode, body)
	}

	response, body = doJSON(t, http.MethodGet, base+"/api/v1/entries", token, nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("list entries status = %d, want 200: %s", response.StatusCode, body)
	}
	var entries []domain.Entry
	if err := json.Unmarshal(body, &entries); err != nil {
		t.Fatalf("decode entries: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("entries = %d, want 1", len(entries))
	}

	from := time.Now().Add(-time.Hour).UTC().Format(time.RFC3339)
	to := time.Now().Add(2 * time.Hour).UTC().Format(time.RFC3339)
	rangeQuery := url.Values{"from": {from}, "to": {to}}.Encode()

	response, body = doJSON(t, http.MethodGet, base+"/api/v1/summary?"+rangeQuery, token, nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("summary status = %d, want 200: %s", response.StatusCode, body)
	}
	var summary export.Summary
	if err := json.Unmarshal(body, &summary); err != nil {
		t.Fatalf("decode summary: %v", err)
	}
	if summary.TotalMinutes != 30 || summary.EntryCount != 1 {
		t.Fatalf("summary = %d minutes / %d entries, want 30/1", summary.TotalMinutes, summary.EntryCount)
	}

	response, body = doJSON(t, http.MethodGet, base+"/api/v1/export?format=markdown&"+rangeQuery, token, nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("export status = %d, want 200: %s", response.StatusCode, body)
	}
	if contentType := response.Header.Get("Content-Type"); !strings.Contains(contentType, "text/markdown") {
		t.Fatalf("export content type = %q", contentType)
	}
	if !strings.Contains(string(body), "# wdid period summary") {
		t.Fatalf("export body missing summary heading:\n%s", body)
	}

	response, body = doJSON(t, http.MethodPost, base+"/api/v1/timer/start", token, map[string]interface{}{
		"initiativeId": initiative.ID,
		"description":  "Backfill script",
	})
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("timer start status = %d, want 201: %s", response.StatusCode, body)
	}

	var timer struct {
		Active bool `json:"active"`
		Paused bool `json:"paused"`
	}
	if err := json.Unmarshal(body, &timer); err != nil {
		t.Fatalf("decode timer: %v", err)
	}
	if !timer.Active {
		t.Fatal("timer should be active after start")
	}

	response, body = doJSON(t, http.MethodPost, base+"/api/v1/timer/pause", token, map[string]interface{}{})
	if response.StatusCode != http.StatusOK {
		t.Fatalf("timer pause status = %d, want 200: %s", response.StatusCode, body)
	}
	if err := json.Unmarshal(body, &timer); err != nil {
		t.Fatalf("decode paused timer: %v", err)
	}
	if !timer.Paused {
		t.Fatal("timer should be paused")
	}

	response, body = doJSON(t, http.MethodPost, base+"/api/v1/timer/resume", token, map[string]interface{}{})
	if response.StatusCode != http.StatusOK {
		t.Fatalf("timer resume status = %d, want 200: %s", response.StatusCode, body)
	}
	if err := json.Unmarshal(body, &timer); err != nil {
		t.Fatalf("decode resumed timer: %v", err)
	}
	if timer.Paused {
		t.Fatal("timer should not be paused after resume")
	}

	response, body = doJSON(t, http.MethodPost, base+"/api/v1/timer/stop", token, map[string]interface{}{
		"action": "discard",
	})
	if response.StatusCode != http.StatusOK {
		t.Fatalf("timer discard status = %d, want 200: %s", response.StatusCode, body)
	}

	response, body = doJSON(t, http.MethodGet, base+"/api/v1/timer", token, nil)
	if response.StatusCode != http.StatusOK {
		t.Fatalf("timer get status = %d, want 200: %s", response.StatusCode, body)
	}
	if err := json.Unmarshal(body, &timer); err != nil {
		t.Fatalf("decode timer state: %v", err)
	}
	if timer.Active {
		t.Fatal("timer should be inactive after discard")
	}
}
