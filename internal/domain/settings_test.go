package domain_test

import (
	"testing"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestNormalizeSupportPeople(t *testing.T) {
	settings := domain.DefaultSettings("user-1")
	settings.SupportPeople = []string{" Priya ", "priya", "", "Sam", "  ", "SAM"}

	settings.Normalize()

	want := []string{"Priya", "Sam"}
	if len(settings.SupportPeople) != len(want) {
		t.Fatalf("support people = %#v, want %#v", settings.SupportPeople, want)
	}
	for i := range want {
		if settings.SupportPeople[i] != want[i] {
			t.Fatalf("support people = %#v, want %#v", settings.SupportPeople, want)
		}
	}
}

func TestNormalizeSupportPeopleDropsAnEmptyRoster(t *testing.T) {
	settings := domain.DefaultSettings("user-1")
	settings.SupportPeople = []string{" ", ""}

	settings.Normalize()

	if settings.SupportPeople != nil {
		t.Fatalf("support people = %#v, want nil", settings.SupportPeople)
	}
}

func TestDefaultSettingsUseTheAnthropicPreset(t *testing.T) {
	settings := domain.DefaultSettings("user-1")

	if settings.AIBaseURL != "https://api.anthropic.com" {
		t.Fatalf("ai base url = %q, want the Anthropic preset", settings.AIBaseURL)
	}
	if settings.AIModel != "claude-sonnet-5-5" {
		t.Fatalf("ai model = %q, want the Anthropic preset model", settings.AIModel)
	}
	if settings.AIAPIKey != "" {
		t.Fatalf("ai key = %q, want no key on a new account", settings.AIAPIKey)
	}
}

func TestNormalizeTrimsTheAIKey(t *testing.T) {
	settings := domain.DefaultSettings("user-1")
	settings.AIAPIKey = "  sk-ant-test  "

	settings.Normalize()

	if settings.AIAPIKey != "sk-ant-test" {
		t.Fatalf("ai key = %q, want the trimmed key", settings.AIAPIKey)
	}
}

func TestMigrateLegacyAIDefaultsReplacesTheRetiredOpenAIPreset(t *testing.T) {
	settings := domain.DefaultSettings("user-1")
	settings.AIBaseURL = "https://api.openai.com/v1"
	settings.AIModel = "gpt-4.1-mini"

	if !settings.MigrateLegacyAIDefaults() {
		t.Fatal("expected the retired OpenAI defaults to migrate")
	}
	if settings.AIBaseURL != domain.AIProviderAnthropicBaseURL {
		t.Fatalf("ai base url = %q, want the Anthropic preset", settings.AIBaseURL)
	}
	if settings.AIModel != domain.AIProviderAnthropicModel {
		t.Fatalf("ai model = %q, want the Anthropic preset model", settings.AIModel)
	}
}

func TestMigrateLegacyAIDefaultsFillsEmptyValues(t *testing.T) {
	settings := domain.DefaultSettings("user-1")
	settings.AIBaseURL = ""
	settings.AIModel = "  "

	settings.MigrateLegacyAIDefaults()

	if settings.AIBaseURL != domain.AIProviderAnthropicBaseURL {
		t.Fatalf("ai base url = %q, want the Anthropic preset", settings.AIBaseURL)
	}
	if settings.AIModel != domain.AIProviderAnthropicModel {
		t.Fatalf("ai model = %q, want the Anthropic preset model", settings.AIModel)
	}
}

func TestMigrateLegacyAIDefaultsPreservesCustomValues(t *testing.T) {
	settings := domain.DefaultSettings("user-1")
	settings.AIBaseURL = "https://proxy.example/anthropic"
	settings.AIModel = "custom-model"

	if settings.MigrateLegacyAIDefaults() {
		t.Fatal("custom values must not be reported as migrated")
	}
	if settings.AIBaseURL != "https://proxy.example/anthropic" {
		t.Fatalf("ai base url = %q, want the custom value", settings.AIBaseURL)
	}
	if settings.AIModel != "custom-model" {
		t.Fatalf("ai model = %q, want the custom value", settings.AIModel)
	}
}

func TestMigrateLegacyAIDefaultsLeavesTheAPIKeyAlone(t *testing.T) {
	settings := domain.DefaultSettings("user-1")
	settings.AIBaseURL = "https://api.openai.com/v1"
	settings.AIModel = "gpt-4.1-mini"
	settings.AIAPIKey = "sk-ant-stored"

	settings.MigrateLegacyAIDefaults()

	if !settings.HasAIKey() {
		t.Fatal("the stored API key must survive the migration")
	}
	if settings.AIAPIKey != "sk-ant-stored" {
		t.Fatalf("ai key = %q, want the stored key", settings.AIAPIKey)
	}
}
