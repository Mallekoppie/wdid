package store_test

import (
	"testing"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestSettingsLoadMigratesTheRetiredOpenAIPreset(t *testing.T) {
	database := newStore(t)

	legacy := domain.DefaultSettings("user-legacy")
	legacy.AIBaseURL = "https://api.openai.com/v1"
	legacy.AIModel = "gpt-4.1-mini"
	legacy.AIAPIKey = "sk-ant-kept"
	if err := database.SaveSettings(legacy); err != nil {
		t.Fatalf("save legacy settings: %v", err)
	}

	loaded, err := database.Settings("user-legacy")
	if err != nil {
		t.Fatalf("load settings: %v", err)
	}
	if loaded.AIBaseURL != domain.AIProviderAnthropicBaseURL {
		t.Fatalf("ai base url = %q, want the Anthropic preset", loaded.AIBaseURL)
	}
	if loaded.AIModel != domain.AIProviderAnthropicModel {
		t.Fatalf("ai model = %q, want the Anthropic preset model", loaded.AIModel)
	}
	if !loaded.HasAIKey() {
		t.Fatal("the stored API key must be unaffected by the migration")
	}
}

func TestSettingsLoadPreservesCustomAIValues(t *testing.T) {
	database := newStore(t)

	custom := domain.DefaultSettings("user-custom")
	custom.AIBaseURL = "https://proxy.example/anthropic"
	custom.AIModel = "custom-model"
	if err := database.SaveSettings(custom); err != nil {
		t.Fatalf("save custom settings: %v", err)
	}

	loaded, err := database.Settings("user-custom")
	if err != nil {
		t.Fatalf("load settings: %v", err)
	}
	if loaded.AIBaseURL != "https://proxy.example/anthropic" || loaded.AIModel != "custom-model" {
		t.Fatalf("loaded ai settings = (%q, %q), want the custom values", loaded.AIBaseURL, loaded.AIModel)
	}
}

func TestEnsureSupportPeopleAlsoMigratesLegacyAIValues(t *testing.T) {
	database := newStore(t)

	legacy := domain.DefaultSettings("user-roster")
	legacy.AIBaseURL = "https://api.openai.com/v1"
	legacy.AIModel = "gpt-4.1-mini"
	if err := database.SaveSettings(legacy); err != nil {
		t.Fatalf("save legacy settings: %v", err)
	}

	loaded, err := database.EnsureSupportPeople("user-roster")
	if err != nil {
		t.Fatalf("ensure settings: %v", err)
	}
	if loaded.AIBaseURL != domain.AIProviderAnthropicBaseURL || loaded.AIModel != domain.AIProviderAnthropicModel {
		t.Fatalf("loaded ai settings = (%q, %q), want the Anthropic preset", loaded.AIBaseURL, loaded.AIModel)
	}
}
