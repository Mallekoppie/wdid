package ai_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Mallekoppie/wdid/internal/ai"
)

func TestOpenAIProviderStreamsDeltasFromChatCompletions(t *testing.T) {
	var gotPath, gotAuth, gotContentType string
	var gotBody struct {
		Model    string `json:"model"`
		Stream   bool   `json:"stream"`
		Messages []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages"`
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("Authorization")
		gotContentType = r.Header.Get("Content-Type")
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Fatalf("decode request: %v", err)
		}

		w.Header().Set("Content-Type", "text/event-stream")
		for _, line := range []string{
			`data: {"model":"provider-model","choices":[{"delta":{"content":"## Highlights\n"}}]}`,
			`data: {"model":"provider-model","choices":[{"delta":{"content":"- Shipped it"}}]}`,
			`data: [DONE]`,
		} {
			_, _ = w.Write([]byte(line + "\n\n"))
		}
	}))
	defer server.Close()

	var streamed strings.Builder
	response, err := ai.NewOpenAIProvider(server.Client()).Stream(
		context.Background(),
		ai.Request{
			BaseURL: server.URL + "/v1/",
			APIKey:  "sk-test-key",
			Model:   "requested-model",
			Prompt:  "instruction and period data",
		},
		func(delta string) error {
			streamed.WriteString(delta)
			return nil
		},
	)
	if err != nil {
		t.Fatalf("stream: %v", err)
	}

	if gotPath != "/v1/chat/completions" {
		t.Fatalf("path = %q, want the OpenAI-compatible endpoint", gotPath)
	}
	if gotAuth != "Bearer sk-test-key" {
		t.Fatalf("authorization = %q", gotAuth)
	}
	if gotContentType != "application/json" {
		t.Fatalf("content type = %q", gotContentType)
	}
	if !gotBody.Stream || gotBody.Model != "requested-model" {
		t.Fatalf("request body = %+v, want a streaming request for the configured model", gotBody)
	}
	if len(gotBody.Messages) != 1 || gotBody.Messages[0].Role != "user" ||
		gotBody.Messages[0].Content != "instruction and period data" {
		t.Fatalf("messages = %+v, want the prompt as one user message", gotBody.Messages)
	}
	if streamed.String() != "## Highlights\n- Shipped it" {
		t.Fatalf("streamed = %q", streamed.String())
	}
	if response.Model != "provider-model" {
		t.Fatalf("model = %q, want the provider-reported model", response.Model)
	}
}

func TestOpenAIProviderAcceptsAnEndpointURL(t *testing.T) {
	var gotPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("data: {\"model\":\"m\",\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"))
	}))
	defer server.Close()

	if _, err := ai.NewOpenAIProvider(server.Client()).Stream(
		context.Background(),
		ai.Request{BaseURL: server.URL + "/chat/completions", APIKey: "k", Model: "m", Prompt: "p"},
		func(string) error { return nil },
	); err != nil {
		t.Fatalf("stream: %v", err)
	}
	if gotPath != "/chat/completions" {
		t.Fatalf("path = %q, want the provided endpoint", gotPath)
	}
}

func TestOpenAIProviderReportsStatusAndConfigurationFailures(t *testing.T) {
	errorServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "model not found", http.StatusNotFound)
	}))
	defer errorServer.Close()

	_, err := ai.NewOpenAIProvider(errorServer.Client()).Stream(
		context.Background(),
		ai.Request{BaseURL: errorServer.URL + "/v1", APIKey: "k", Model: "m", Prompt: "p"},
		func(string) error { return nil },
	)
	if err == nil || !strings.Contains(err.Error(), "404") {
		t.Fatalf("status error = %v, want a 404 message", err)
	}

	for name, request := range map[string]ai.Request{
		"missing base URL": {APIKey: "k", Model: "m", Prompt: "p"},
		"invalid scheme":   {BaseURL: "ftp://example.com/v1", APIKey: "k", Model: "m", Prompt: "p"},
		"missing model":    {BaseURL: "https://example.com/v1", APIKey: "k", Prompt: "p"},
		"missing key":      {BaseURL: "https://example.com/v1", Model: "m", Prompt: "p"},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := ai.NewOpenAIProvider(nil).Stream(
				context.Background(), request, func(string) error { return nil },
			); err == nil {
				t.Fatal("expected a configuration error")
			}
		})
	}
}

func TestOpenAIProviderStopsWhenTheConsumerFails(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("data: {\"model\":\"m\",\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n"))
	}))
	defer server.Close()

	stop := errors.New("client went away")
	_, err := ai.NewOpenAIProvider(server.Client()).Stream(
		context.Background(),
		ai.Request{BaseURL: server.URL + "/v1", APIKey: "k", Model: "m", Prompt: "p"},
		func(string) error { return stop },
	)
	if !errors.Is(err, stop) {
		t.Fatalf("error = %v, want the consumer's error", err)
	}
}
