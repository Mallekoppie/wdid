// Package ai contains the one provider abstraction used for AI summaries. It
// speaks the Anthropic Messages streaming protocol and never stores or logs the
// API key it is given.
package ai

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

const (
	// anthropicVersion is the Messages API version sent with every request.
	anthropicVersion = "2023-06-01"
	// maxOutputTokens bounds one generated summary. It is deliberately generous
	// so a long report is never cut off mid-sentence.
	maxOutputTokens = 4096
)

// Request is one streaming generation request. The key comes from the user's
// settings and is passed in memory only.
type Request struct {
	BaseURL string
	APIKey  string
	Model   string
	Prompt  string
}

// Response carries the provider-reported model name, so the check-in records
// what actually produced its summary.
type Response struct {
	Model string
}

// Provider is the single seam between the service and an Anthropic-compatible
// endpoint. Tests supply a fake implementation; the service never reaches the
// network without one.
type Provider interface {
	// Stream sends the prompt and calls onDelta for each text fragment. The
	// call returns only after the provider finishes; an error means the
	// response is incomplete and must not be persisted.
	Stream(ctx context.Context, request Request, onDelta func(string) error) (Response, error)
}

// AnthropicProvider posts to {baseURL}/v1/messages with streaming enabled. It
// also serves Anthropic-compatible endpoints such as DeepSeek's
// https://api.deepseek.com/anthropic base.
type AnthropicProvider struct {
	client *http.Client
}

// NewAnthropicProvider builds the provider. A nil client uses http.DefaultClient
// semantics without a total timeout, because a stream can legitimately run for
// minutes.
func NewAnthropicProvider(client *http.Client) *AnthropicProvider {
	if client == nil {
		client = &http.Client{}
	}
	return &AnthropicProvider{client: client}
}

// Stream implements Provider.
func (p *AnthropicProvider) Stream(ctx context.Context, request Request, onDelta func(string) error) (Response, error) {
	endpoint, err := messagesURL(request.BaseURL)
	if err != nil {
		return Response{}, err
	}
	if strings.TrimSpace(request.Model) == "" {
		return Response{}, errors.New("AI model is not configured")
	}
	if strings.TrimSpace(request.APIKey) == "" {
		return Response{}, errors.New("AI API key is not configured")
	}

	payload, err := json.Marshal(messagesRequest{
		Model:     request.Model,
		MaxTokens: maxOutputTokens,
		Stream:    true,
		Messages: []message{
			{Role: "user", Content: request.Prompt},
		},
		// DeepSeek's reasoning models stream a private thinking block first and
		// count it against max_tokens. At the summary budget they can spend every
		// token thinking and emit no answer, so ask the compatible endpoint for
		// the answer directly. Anthropic and custom models are left untouched.
		Thinking: thinkingForModel(request.Model),
	})
	if err != nil {
		return Response{}, fmt.Errorf("encode AI request: %w", err)
	}

	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return Response{}, fmt.Errorf("build AI request: %w", err)
	}
	httpRequest.Header.Set("x-api-key", request.APIKey)
	httpRequest.Header.Set("anthropic-version", anthropicVersion)
	httpRequest.Header.Set("Content-Type", "application/json")
	httpRequest.Header.Set("Accept", "text/event-stream")

	response, err := p.client.Do(httpRequest)
	if err != nil {
		return Response{}, fmt.Errorf("call the AI provider: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return Response{}, providerStatusError(response)
	}

	model := ""
	scanner := bufio.NewScanner(response.Body)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, ":") || strings.HasPrefix(line, "event:") {
			continue
		}
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "" || data == "[DONE]" {
			continue
		}

		var event streamEvent
		if err := json.Unmarshal([]byte(data), &event); err != nil {
			return Response{}, fmt.Errorf("decode AI stream: %w", err)
		}
		switch event.Type {
		case "message_start":
			if event.Message.Model != "" {
				model = event.Message.Model
			}
		case "content_block_delta":
			if event.Delta.Text == "" {
				continue
			}
			if err := onDelta(event.Delta.Text); err != nil {
				return Response{}, err
			}
		case "error":
			if event.Error != nil && event.Error.Message != "" {
				return Response{}, errors.New(event.Error.Message)
			}
			return Response{}, errors.New("the AI provider reported an error")
		case "message_stop":
			model = responseModel(model, request.Model)
			return Response{Model: model}, nil
		}
	}
	if err := scanner.Err(); err != nil {
		return Response{}, fmt.Errorf("read the AI stream: %w", err)
	}
	return Response{Model: responseModel(model, request.Model)}, nil
}

func responseModel(reported, requested string) string {
	if reported != "" {
		return reported
	}
	return requested
}

// messagesURL accepts a base URL such as https://api.anthropic.com,
// https://api.deepseek.com/anthropic or a custom proxy, and appends the
// documented path. A URL that already names the endpoint is left alone, which
// keeps proxy-style configurations working.
func messagesURL(baseURL string) (string, error) {
	trimmed := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if trimmed == "" {
		return "", errors.New("AI base URL is not configured")
	}
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return "", fmt.Errorf("AI base URL is invalid: %w", err)
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", errors.New("AI base URL must use http or https")
	}
	if parsed.Host == "" {
		return "", errors.New("AI base URL must include a host")
	}
	switch {
	case strings.HasSuffix(trimmed, "/v1/messages"):
		return trimmed, nil
	case strings.HasSuffix(trimmed, "/v1"):
		return trimmed + "/messages", nil
	default:
		return trimmed + "/v1/messages", nil
	}
}

func providerStatusError(response *http.Response) error {
	body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
	detail := strings.TrimSpace(string(body))
	if detail == "" {
		return fmt.Errorf("AI provider returned %s", response.Status)
	}
	var providerError struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal([]byte(detail), &providerError); err == nil &&
		providerError.Error.Message != "" {
		detail = providerError.Error.Message
	}
	return fmt.Errorf("AI provider returned %s: %s", response.Status, detail)
}

type messagesRequest struct {
	Model     string          `json:"model"`
	MaxTokens int             `json:"max_tokens"`
	Stream    bool            `json:"stream"`
	Messages  []message       `json:"messages"`
	Thinking  *thinkingConfig `json:"thinking,omitempty"`
}

// thinkingConfig disables or enables the provider's hidden reasoning block. The
// Anthropic Messages protocol accepts it; DeepSeek honors "disabled" for its
// reasoning models.
type thinkingConfig struct {
	Type string `json:"type"`
}

// thinkingForModel asks DeepSeek reasoning models to answer without a hidden
// thinking block. DeepSeek counts thinking tokens against max_tokens, so a
// summary-sized budget can be exhausted before any answer text arrives. Other
// providers get no thinking field, preserving their default behaviour.
func thinkingForModel(model string) *thinkingConfig {
	if strings.HasPrefix(strings.ToLower(strings.TrimSpace(model)), "deepseek-") {
		return &thinkingConfig{Type: "disabled"}
	}
	return nil
}

type message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type streamEvent struct {
	Type    string `json:"type"`
	Message struct {
		Model string `json:"model"`
	} `json:"message"`
	Delta struct {
		Text string `json:"text"`
	} `json:"delta"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}
