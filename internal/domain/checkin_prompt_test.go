package domain_test

import (
	"strings"
	"testing"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestPromptVariantFollowsKindAndAudience(t *testing.T) {
	cases := []struct {
		name    string
		checkIn domain.CheckIn
		want    domain.PromptVariant
	}{
		{
			name:    "manager one on one",
			checkIn: domain.CheckIn{Kind: domain.CheckInKindManager, Audience: domain.AudienceOneOnOne},
			want:    domain.PromptVariantManagerOneOnOne,
		},
		{
			name:    "manager performance review",
			checkIn: domain.CheckIn{Kind: domain.CheckInKindManager, Audience: domain.AudiencePerformanceReview},
			want:    domain.PromptVariantManagerPerformanceReview,
		},
		{
			// One-on-one is the product default for a manager check-in.
			name:    "manager without an audience",
			checkIn: domain.CheckIn{Kind: domain.CheckInKindManager},
			want:    domain.PromptVariantManagerOneOnOne,
		},
		{
			name:    "personal review",
			checkIn: domain.CheckIn{Kind: domain.CheckInKindPersonal},
			want:    domain.PromptVariantPersonalReview,
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			if got := domain.PromptVariantFor(testCase.checkIn); got != testCase.want {
				t.Fatalf("variant = %q, want %q", got, testCase.want)
			}
		})
	}
}

func TestBuildPromptSelectsTheVariantTemplateAndKeepsTheSummary(t *testing.T) {
	summary := "## Highlights\n- Cut invoicing from 40 min to 3 min"
	oneOnOne := domain.CheckIn{
		Kind:            domain.CheckInKindManager,
		Audience:        domain.AudienceOneOnOne,
		SummaryMarkdown: summary,
	}
	performance := oneOnOne
	performance.Audience = domain.AudiencePerformanceReview
	personal := domain.CheckIn{
		Kind:            domain.CheckInKindPersonal,
		SummaryMarkdown: summary,
	}

	oneOnOnePrompt := domain.BuildPrompt(oneOnOne)
	performancePrompt := domain.BuildPrompt(performance)
	personalPrompt := domain.BuildPrompt(personal)

	if !strings.Contains(oneOnOnePrompt, "1:1") {
		t.Fatalf("one-on-one prompt = %q, want the 1:1 instruction", oneOnOnePrompt)
	}
	if !strings.Contains(performancePrompt, "performance review") {
		t.Fatalf("performance prompt = %q, want the review instruction", performancePrompt)
	}
	if !strings.Contains(personalPrompt, "your own working period") {
		t.Fatalf("personal prompt = %q, want the personal instruction", personalPrompt)
	}
	if oneOnOnePrompt == performancePrompt || oneOnOnePrompt == personalPrompt || performancePrompt == personalPrompt {
		t.Fatal("prompt variants must differ")
	}

	// Every variant carries the supplied summary unchanged and the same
	// data-honesty rules.
	for name, prompt := range map[string]string{
		"one-on-one":  oneOnOnePrompt,
		"performance": performancePrompt,
		"personal":    personalPrompt,
	} {
		if !strings.HasSuffix(prompt, summary) {
			t.Fatalf("%s prompt does not end with the summary: %q", name, prompt)
		}
		if !strings.Contains(prompt, "Invent nothing") {
			t.Fatalf("%s prompt is missing the shared rules", name)
		}
	}

	// An empty summary is allowed; the prompt is then the instruction alone.
	empty := domain.BuildPrompt(domain.CheckIn{Kind: domain.CheckInKindManager})
	if strings.Contains(empty, "\n\n\n") || strings.TrimSpace(empty) == "" {
		t.Fatalf("empty-summary prompt = %q", empty)
	}
	if strings.HasSuffix(empty, "\n\n") {
		t.Fatalf("empty-summary prompt has a trailing body: %q", empty)
	}
}

func TestNormalizeDefaultsAManagerAudienceToOneOnOne(t *testing.T) {
	manager := domain.CheckIn{Kind: domain.CheckInKindManager}
	manager.Normalize()
	if manager.Audience != domain.AudienceOneOnOne {
		t.Fatalf("audience = %q, want the one-on-one default", manager.Audience)
	}

	personal := domain.CheckIn{Kind: domain.CheckInKindPersonal}
	personal.Normalize()
	if personal.Audience != "" {
		t.Fatalf("personal audience = %q, want none", personal.Audience)
	}
}
