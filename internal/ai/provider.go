// Package ai contains the one provider abstraction used for AI summaries. It
// speaks the OpenAI-compatible chat completions streaming protocol and never
// stores or logs the API key it is given.
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

// Request is one streaming generation request. The key comes from the
// environment and is passed in memory only.
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

// Provider is the single seam between the service and an OpenAI-compatible
// endpoint. Tests supply a fake implementation; the service never reaches the
// network without one.
type Provider interface {
	// Stream sends the prompt and calls onDelta for each text fragment. The
	// call returns only after the provider finishes; an error means the
	// response is incomplete and must not be persisted.
	Stream(ctx context.Context, request Request, onDelta func(string) error) (Response, error)
}

// OpenAIProvider posts to {baseURL}/chat/completions with streaming enabled.
type OpenAIProvider struct {
	client *http.Client
}

// NewOpenAIProvider builds the provider. A nil client uses http.DefaultClient
// semantics without a total timeout, because a stream can legitimately run for
// minutes.
func NewOpenAIProvider(client *http.Client) *OpenAIProvider {
	if client == nil {
		client = &http.Client{}
	}
	return &OpenAIProvider{client: client}
}

// Stream implements Provider.
func (p *OpenAIProvider) Stream(ctx context.Context, request Request, onDelta func(string) error) (Response, error) {
	endpoint, err := chatCompletionsURL(request.BaseURL)
	if err != nil {
		return Response{}, err
	}
	if strings.TrimSpace(request.Model) == "" {
		return Response{}, errors.New("AI model is not configured")
	}
	if strings.TrimSpace(request.APIKey) == "" {
		return Response{}, errors.New("AI API key is not configured")
	}

	payload, err := json.Marshal(chatRequest{
		Model:  request.Model,
		Stream: true,
		Messages: []chatMessage{
			{Role: "user", Content: request.Prompt},
		},
	})
	if err != nil {
		return Response{}, fmt.Errorf("encode AI request: %w", err)
	}

	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return Response{}, fmt.Errorf("build AI request: %w", err)
	}
	httpRequest.Header.Set("Authorization", "Bearer "+request.APIKey)
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
		if line == "" || strings.HasPrefix(line, ":") {
			continue
		}
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "[DONE]" {
			break
		}

		var chunk chatChunk
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			return Response{}, fmt.Errorf("decode AI stream: %w", err)
		}
		if chunk.Model != "" {
			model = chunk.Model
		}
		if chunk.Error != nil && chunk.Error.Message != "" {
			return Response{}, errors.New(chunk.Error.Message)
		}
		for _, choice := range chunk.Choices {
			if choice.Delta.Content == "" {
				continue
			}
			if err := onDelta(choice.Delta.Content); err != nil {
				return Response{}, err
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return Response{}, fmt.Errorf("read the AI stream: %w", err)
	}
	if model == "" {
		model = request.Model
	}
	return Response{Model: model}, nil
}

// chatCompletionsURL accepts a base URL such as https://api.openai.com/v1 and
// appends the documented path. A URL that already names the endpoint is left
// alone, which keeps proxy-style configurations working.
func chatCompletionsURL(baseURL string) (string, error) {
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
	if strings.HasSuffix(trimmed, "/chat/completions") {
		return trimmed, nil
	}
	return trimmed + "/chat/completions", nil
}

func providerStatusError(response *http.Response) error {
	body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
	detail := strings.TrimSpace(string(body))
	if detail == "" {
		return fmt.Errorf("AI provider returned %s", response.Status)
	}
	return fmt.Errorf("AI provider returned %s: %s", response.Status, detail)
}

type chatRequest struct {
	Model    string        `json:"model"`
	Stream   bool          `json:"stream"`
	Messages []chatMessage `json:"messages"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatChunk struct {
	Model   string `json:"model"`
	Choices []struct {
		Delta struct {
			Content string `json:"content"`
		} `json:"delta"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}
