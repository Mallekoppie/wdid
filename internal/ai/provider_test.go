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

func TestAnthropicProviderStreamsDeltasFromMessages(t *testing.T) {
	var gotPath, gotAPIKey, gotVersion, gotContentType, gotAccept string
	var gotBody struct {
		Model     string `json:"model"`
		MaxTokens int    `json:"max_tokens"`
		Stream    bool   `json:"stream"`
		Messages  []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages"`
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotAPIKey = r.Header.Get("x-api-key")
		gotVersion = r.Header.Get("anthropic-version")
		gotContentType = r.Header.Get("Content-Type")
		gotAccept = r.Header.Get("Accept")
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Fatalf("decode request: %v", err)
		}

		w.Header().Set("Content-Type", "text/event-stream")
		for _, event := range []string{
			"event: message_start\n" +
				`data: {"type":"message_start","message":{"id":"msg_1","model":"provider-model","content":[]}}` + "\n\n",
			"event: content_block_start\n" +
				`data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}` + "\n\n",
			"event: content_block_delta\n" +
				`data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"## Highlights\n"}}` + "\n\n",
			"event: content_block_delta\n" +
				`data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"- Shipped it"}}` + "\n\n",
			"event: content_block_stop\n" +
				`data: {"type":"content_block_stop","index":0}` + "\n\n",
			"event: message_delta\n" +
				`data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}` + "\n\n",
			"event: message_stop\n" +
				`data: {"type":"message_stop"}` + "\n\n",
		} {
			_, _ = w.Write([]byte(event))
		}
	}))
	defer server.Close()

	var streamed strings.Builder
	response, err := ai.NewAnthropicProvider(server.Client()).Stream(
		context.Background(),
		ai.Request{
			BaseURL:  server.URL,
			APIKey:   "sk-ant-test-key",
			Model:    "requested-model",
			Messages: []ai.Message{{Role: "user", Content: "instruction and period data"}},
		},
		func(delta string) error {
			streamed.WriteString(delta)
			return nil
		},
	)
	if err != nil {
		t.Fatalf("stream: %v", err)
	}

	if gotPath != "/v1/messages" {
		t.Fatalf("path = %q, want the Anthropic Messages endpoint", gotPath)
	}
	if gotAPIKey != "sk-ant-test-key" {
		t.Fatalf("x-api-key = %q, want the per-user key", gotAPIKey)
	}
	if gotVersion != "2023-06-01" {
		t.Fatalf("anthropic-version = %q, want 2023-06-01", gotVersion)
	}
	if gotContentType != "application/json" {
		t.Fatalf("content type = %q", gotContentType)
	}
	if gotAccept != "text/event-stream" {
		t.Fatalf("accept = %q", gotAccept)
	}
	if !gotBody.Stream || gotBody.Model != "requested-model" || gotBody.MaxTokens <= 0 {
		t.Fatalf("request body = %+v, want a streaming request with a max token budget", gotBody)
	}
	if len(gotBody.Messages) != 1 || gotBody.Messages[0].Role != "user" ||
		gotBody.Messages[0].Content != "instruction and period data" {
		t.Fatalf("messages = %+v, want the single user message", gotBody.Messages)
	}
	if streamed.String() != "## Highlights\n- Shipped it" {
		t.Fatalf("streamed = %q", streamed.String())
	}
	if response.Model != "provider-model" {
		t.Fatalf("model = %q, want the provider-reported model", response.Model)
	}
}

// TestAnthropicProviderEncodesMultiTurnMessages proves the provider seam can
// carry a refine conversation: the instruction and data, the stored summary and
// the user's feedback must all reach the Anthropic-compatible payload in order.
func TestAnthropicProviderEncodesMultiTurnMessages(t *testing.T) {
	var gotBody struct {
		Messages []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages"`
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte(`data: {"type":"message_stop"}` + "\n\n"))
	}))
	defer server.Close()

	messages := []ai.Message{
		{Role: "user", Content: "instruction and data"},
		{Role: "assistant", Content: "current summary, exactly as stored"},
		{Role: "user", Content: "make it shorter"},
	}
	if _, err := ai.NewAnthropicProvider(server.Client()).Stream(
		context.Background(),
		ai.Request{BaseURL: server.URL, APIKey: "k", Model: "m", Messages: messages},
		func(string) error { return nil },
	); err != nil {
		t.Fatalf("stream: %v", err)
	}

	if len(gotBody.Messages) != len(messages) {
		t.Fatalf("messages = %+v, want %d turns", gotBody.Messages, len(messages))
	}
	for index, want := range messages {
		if gotBody.Messages[index].Role != want.Role || gotBody.Messages[index].Content != want.Content {
			t.Fatalf("message %d = %+v, want %+v", index, gotBody.Messages[index], want)
		}
	}
}

func TestAnthropicProviderPresetBases(t *testing.T) {
	tests := []struct {
		name   string
		suffix string
		want   string
	}{
		{name: "Anthropic", suffix: "", want: "/v1/messages"},
		{name: "DeepSeek", suffix: "/anthropic", want: "/anthropic/v1/messages"},
		{name: "versioned base", suffix: "/v1", want: "/v1/messages"},
		{name: "explicit endpoint", suffix: "/v1/messages", want: "/v1/messages"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var gotPath string
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				gotPath = r.URL.Path
				w.Header().Set("Content-Type", "text/event-stream")
				_, _ = w.Write([]byte(`data: {"type":"message_stop"}` + "\n\n"))
			}))
			defer server.Close()

			base := server.URL + test.suffix

			if _, err := ai.NewAnthropicProvider(server.Client()).Stream(
				context.Background(),
				ai.Request{BaseURL: base, APIKey: "k", Model: "m", Messages: []ai.Message{{Role: "user", Content: "p"}}},
				func(string) error { return nil },
			); err != nil {
				t.Fatalf("stream: %v", err)
			}
			if gotPath != test.want {
				t.Fatalf("path = %q, want %q", gotPath, test.want)
			}
		})
	}
}

func TestAnthropicProviderReportsStatusAndConfigurationFailures(t *testing.T) {
	errorServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"type":"error","error":{"type":"not_found_error","message":"model not found"}}`))
	}))
	defer errorServer.Close()

	_, err := ai.NewAnthropicProvider(errorServer.Client()).Stream(
		context.Background(),
		ai.Request{BaseURL: errorServer.URL, APIKey: "k", Model: "m", Messages: []ai.Message{{Role: "user", Content: "p"}}},
		func(string) error { return nil },
	)
	if err == nil || !strings.Contains(err.Error(), "404") || !strings.Contains(err.Error(), "model not found") {
		t.Fatalf("status error = %v, want a 404 with the provider message", err)
	}

	prompt := []ai.Message{{Role: "user", Content: "p"}}
	for name, request := range map[string]ai.Request{
		"missing base URL": {APIKey: "k", Model: "m", Messages: prompt},
		"invalid scheme":   {BaseURL: "ftp://example.com", APIKey: "k", Model: "m", Messages: prompt},
		"missing model":    {BaseURL: "https://example.com", APIKey: "k", Messages: prompt},
		"missing key":      {BaseURL: "https://example.com", Model: "m", Messages: prompt},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := ai.NewAnthropicProvider(nil).Stream(
				context.Background(), request, func(string) error { return nil },
			); err == nil {
				t.Fatal("expected a configuration error")
			}
		})
	}
}

func TestAnthropicProviderSurfacesStreamErrors(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("event: error\n" +
			`data: {"type":"error","error":{"type":"overloaded_error","message":"provider overloaded"}}` + "\n\n"))
	}))
	defer server.Close()

	_, err := ai.NewAnthropicProvider(server.Client()).Stream(
		context.Background(),
		ai.Request{BaseURL: server.URL, APIKey: "k", Model: "m", Messages: []ai.Message{{Role: "user", Content: "p"}}},
		func(string) error { return nil },
	)
	if err == nil || !strings.Contains(err.Error(), "provider overloaded") {
		t.Fatalf("stream error = %v, want the provider's message", err)
	}
}

func TestAnthropicProviderDisablesDeepSeekThinking(t *testing.T) {
	for _, test := range []struct {
		name        string
		model       string
		wantDisable bool
	}{
		{"deepseek reasoning model", "deepseek-flash", true},
		{"deepseek chat model", "deepseek-chat", true},
		{"anthropic model", "claude-sonnet-5-5", false},
		{"custom model", "custom-model", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			var got struct {
				Thinking *struct {
					Type string `json:"type"`
				} `json:"thinking"`
			}
			var decodeErr error
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
					decodeErr = err
					return
				}
				w.Header().Set("Content-Type", "text/event-stream")
				_, _ = w.Write([]byte(`data: {"type":"message_stop"}` + "\n\n"))
			}))
			defer server.Close()

			_, err := ai.NewAnthropicProvider(server.Client()).Stream(
				context.Background(),
				ai.Request{BaseURL: server.URL, APIKey: "k", Model: test.model, Messages: []ai.Message{{Role: "user", Content: "p"}}},
				func(string) error { return nil },
			)
			if decodeErr != nil {
				t.Fatalf("decode request: %v", decodeErr)
			}
			if err != nil {
				t.Fatalf("stream: %v", err)
			}
			if test.wantDisable {
				if got.Thinking == nil || got.Thinking.Type != "disabled" {
					t.Fatalf("thinking = %+v, want type disabled", got.Thinking)
				}
				return
			}
			if got.Thinking != nil {
				t.Fatalf("thinking = %+v, want the field omitted", got.Thinking)
			}
		})
	}
}

func TestAnthropicProviderStopsWhenTheConsumerFails(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("event: content_block_delta\n" +
			`data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}}` + "\n\n"))
	}))
	defer server.Close()

	stop := errors.New("client went away")
	_, err := ai.NewAnthropicProvider(server.Client()).Stream(
		context.Background(),
		ai.Request{BaseURL: server.URL, APIKey: "k", Model: "m", Messages: []ai.Message{{Role: "user", Content: "p"}}},
		func(string) error { return stop },
	)
	if !errors.Is(err, stop) {
		t.Fatalf("error = %v, want the consumer's error", err)
	}
}
