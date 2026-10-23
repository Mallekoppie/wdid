package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Mallekoppie/goslow/platform"

	"github.com/Mallekoppie/wdid/internal/config"
)

func newRouteServer(t *testing.T) *httptest.Server {
	t.Helper()

	// Other tests in this package configure the platform for storage-only CLI
	// commands; reset it so the route server does not depend on test order.
	storage := config.Config{StorageOnly: true}
	if err := platform.SetPlatformConfiguration(storage.PlatformConfig()); err != nil {
		t.Fatalf("reset platform configuration: %v", err)
	}

	handler, err := platform.NewApplicationHandler(platform.ApplicationServerOptions{
		Routes: nonRPCRoutes(),
	})
	if err != nil {
		t.Fatalf("build application handler: %v", err)
	}

	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)

	return server
}

func TestHealthzIsPublic(t *testing.T) {
	server := newRouteServer(t)

	response, err := server.Client().Get(server.URL + "/healthz")
	if err != nil {
		t.Fatalf("healthz request: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		t.Fatalf("healthz status = %d, want 200", response.StatusCode)
	}

	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatalf("read healthz response: %v", err)
	}
	if string(body) != `{"status":"ok"}` {
		t.Fatalf("healthz body = %q, want %q", body, `{"status":"ok"}`)
	}
}

// TestLegacyRESTRoutesAreGone asserts the route table no longer registers the
// old domain API. The deployed handler falls through unmatched paths to the SPA,
// so this checks registration, not a 404 from the composed server.
func TestLegacyRESTRoutesAreGone(t *testing.T) {
	server := newRouteServer(t)

	legacy := []struct {
		method string
		path   string
	}{
		{http.MethodPost, "/api/v1/auth/register"},
		{http.MethodPost, "/api/v1/auth/login"},
		{http.MethodGet, "/api/v1/auth/config"},
		{http.MethodGet, "/api/v1/auth/me"},
		{http.MethodGet, "/api/v1/initiatives"},
		{http.MethodPost, "/api/v1/initiatives"},
		{http.MethodGet, "/api/v1/initiatives/init-1"},
		{http.MethodPatch, "/api/v1/initiatives/init-1"},
		{http.MethodDelete, "/api/v1/initiatives/init-1"},
		{http.MethodGet, "/api/v1/entries"},
		{http.MethodPost, "/api/v1/entries"},
		{http.MethodGet, "/api/v1/entries/entry-1"},
		{http.MethodPatch, "/api/v1/entries/entry-1"},
		{http.MethodDelete, "/api/v1/entries/entry-1"},
		{http.MethodGet, "/api/v1/timer"},
		{http.MethodPost, "/api/v1/timer/start"},
		{http.MethodPost, "/api/v1/timer/pause"},
		{http.MethodPost, "/api/v1/timer/resume"},
		{http.MethodPost, "/api/v1/timer/stop"},
		{http.MethodGet, "/api/v1/summary"},
		{http.MethodGet, "/api/v1/export"},
	}

	for _, route := range legacy {
		request, err := http.NewRequest(route.method, server.URL+route.path, nil)
		if err != nil {
			t.Fatalf("build %s %s request: %v", route.method, route.path, err)
		}

		response, err := server.Client().Do(request)
		if err != nil {
			t.Fatalf("%s %s: %v", route.method, route.path, err)
		}
		response.Body.Close()

		if response.StatusCode != http.StatusNotFound {
			t.Errorf("%s %s status = %d, want 404", route.method, route.path, response.StatusCode)
		}
	}
}
