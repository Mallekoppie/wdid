package domain_test

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/Mallekoppie/wdid/internal/domain"
)

func TestWorkEntryNormalizeDedupesPeopleCaseInsensitively(t *testing.T) {
	entry := domain.WorkEntry{
		People: []string{" Priya ", "sam", "priya", "", "Sam"},
	}

	entry.Normalize()

	want := []string{"Priya", "sam"}
	if !reflect.DeepEqual(entry.People, want) {
		t.Fatalf("people = %#v, want %#v", entry.People, want)
	}
}

func TestWorkEntryUnmarshalLoadsLegacyPersonAsOneName(t *testing.T) {
	var entry domain.WorkEntry
	if err := json.Unmarshal([]byte(`{"id":"legacy","person":" Priya "}`), &entry); err != nil {
		t.Fatalf("unmarshal legacy entry: %v", err)
	}

	want := []string{"Priya"}
	if !reflect.DeepEqual(entry.People, want) {
		t.Fatalf("people = %#v, want %#v", entry.People, want)
	}
}

func TestWorkEntryUnmarshalReadsPeopleList(t *testing.T) {
	var entry domain.WorkEntry
	if err := json.Unmarshal([]byte(`{"id":"multi","people":["Priya","Sam"],"person":"Ignored"}`), &entry); err != nil {
		t.Fatalf("unmarshal entry: %v", err)
	}

	want := []string{"Priya", "Sam"}
	if !reflect.DeepEqual(entry.People, want) {
		t.Fatalf("people = %#v, want %#v", entry.People, want)
	}
}

func TestWorkEntryMarshalWritesPeopleNotPerson(t *testing.T) {
	encoded, err := json.Marshal(domain.WorkEntry{ID: "multi", People: []string{"Priya", "Sam"}})
	if err != nil {
		t.Fatalf("marshal entry: %v", err)
	}

	text := string(encoded)
	if !strings.Contains(text, `"people":["Priya","Sam"]`) {
		t.Fatalf("encoded entry = %s, want a people list", text)
	}
	if strings.Contains(text, `"person":`) {
		t.Fatalf("encoded entry = %s, want no legacy person field", text)
	}
}

func TestActiveTimerUnmarshalLoadsLegacyPersonAsOneName(t *testing.T) {
	var timer domain.ActiveTimer
	if err := json.Unmarshal([]byte(`{"userId":"user-1","person":"Sam"}`), &timer); err != nil {
		t.Fatalf("unmarshal legacy timer: %v", err)
	}

	want := []string{"Sam"}
	if !reflect.DeepEqual(timer.People, want) {
		t.Fatalf("people = %#v, want %#v", timer.People, want)
	}
}

func TestActiveTimerNormalizeDedupesPeople(t *testing.T) {
	timer := domain.ActiveTimer{
		People: []string{" Priya ", "priya", "Sam"},
	}

	timer.Normalize()

	want := []string{"Priya", "Sam"}
	if !reflect.DeepEqual(timer.People, want) {
		t.Fatalf("people = %#v, want %#v", timer.People, want)
	}
}
