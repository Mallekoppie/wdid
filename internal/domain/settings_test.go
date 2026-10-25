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
