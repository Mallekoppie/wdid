package rpc_test

import (
	"context"
	"testing"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
)

// TestSupportLoggingServesConnectAndGRPCWeb covers the support capture contract
// on both transports: a support entry carries a person, team, mode (the
// subcategory of a support-role category), duration, description, outcome and
// links; the listing returns it newest first; a support entry without a person
// is a field error; and support work never becomes project work.
func TestSupportLoggingServesConnectAndGRPCWeb(t *testing.T) {
	transports := []struct {
		name    string
		options []connect.ClientOption
	}{
		{name: "connect"},
		{name: "grpc-web", options: []connect.ClientOption{connect.WithGRPCWeb()}},
	}

	for _, transport := range transports {
		t.Run(transport.name, func(t *testing.T) {
			server, _ := newDomainServer(t)
			token := bootstrapToken(t, server)
			categories := categoryClient(server, transport.options...)
			entries := entryClient(server, transport.options...)

			support, err := categories.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
				Name: "Mentoring",
				Role: wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT,
			}, token))
			if err != nil {
				t.Fatalf("create support category: %v", err)
			}
			supportID := support.Msg.GetCategory().GetId()
			unblock := createMode(t, categories, token, supportID, "Unblock")
			review := createMode(t, categories, token, supportID, "Review")

			initiative, err := categories.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
				Name: "Initiatives",
				Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
			}, token))
			if err != nil {
				t.Fatalf("create initiative category: %v", err)
			}
			initiativeID := initiative.Msg.GetCategory().GetId()
			project := createMode(t, categories, token, initiativeID, "Billing migration")

			day := time.Date(2026, 10, 21, 0, 0, 0, 0, time.UTC)
			earlier := day.Add(9 * time.Hour)
			later := day.Add(14 * time.Hour)

			create := func(request *wdidv1.CreateEntryRequest) *wdidv1.WorkEntry {
				t.Helper()
				response, err := entries.CreateEntry(context.Background(), withBearer(request, token))
				if err != nil {
					t.Fatalf("create support entry: %v", err)
				}
				return response.Msg.GetEntry()
			}

			first := create(&wdidv1.CreateEntryRequest{
				CategoryId:    supportID,
				SubcategoryId: unblock,
				Description:   "Unblocked the billing migration",
				Outcome:       "Shipped the fix the same day",
				People:        []string{"Priya", "Alex"},
				Team:          "Payments",
				StartedAt:     timestamppb.New(earlier),
				Duration:      durationpb.New(45 * time.Minute),
				Links: []*wdidv1.Link{
					{Label: "Thread", Url: "https://example.com/thread"},
				},
			})
			if len(first.GetPeople()) != 2 || first.GetPeople()[0] != "Priya" ||
				first.GetPeople()[1] != "Alex" || first.GetTeam() != "Payments" {
				t.Fatalf("support entry = %+v, want people and team", first)
			}
			if first.GetSubcategoryId() != unblock {
				t.Fatalf("mode = %q, want the support subcategory", first.GetSubcategoryId())
			}
			if first.GetDescription() != "Unblocked the billing migration" ||
				first.GetOutcome() != "Shipped the fix the same day" {
				t.Fatalf("support entry = %+v, want description and outcome", first)
			}
			if len(first.GetLinks()) != 1 || first.GetLinks()[0].GetUrl() != "https://example.com/thread" {
				t.Fatalf("links = %+v, want the saved link", first.GetLinks())
			}
			if first.GetDuration().AsDuration() != 45*time.Minute {
				t.Fatalf("duration = %v, want 45m", first.GetDuration().AsDuration())
			}

			second := create(&wdidv1.CreateEntryRequest{
				CategoryId:    supportID,
				SubcategoryId: review,
				Description:   "Reviewed the launch plan",
				People:        []string{"Sam"},
				StartedAt:     timestamppb.New(later),
				Duration:      durationpb.New(30 * time.Minute),
			})

			listed, err := entries.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
				CategoryId: supportID,
				FromDate:   "2026-10-21",
				ToDate:     "2026-10-21",
			}, token))
			if err != nil {
				t.Fatalf("list support entries: %v", err)
			}
			if len(listed.Msg.GetEntries()) != 2 {
				t.Fatalf("support entries = %d, want 2", len(listed.Msg.GetEntries()))
			}
			if listed.Msg.GetEntries()[0].GetId() != second.GetId() ||
				listed.Msg.GetEntries()[1].GetId() != first.GetId() {
				t.Fatalf("support order = %+v, want newest first", listed.Msg.GetEntries())
			}
			for _, entry := range listed.Msg.GetEntries() {
				if entry.GetCategoryId() != supportID {
					t.Fatalf("entry category = %q, want the support category", entry.GetCategoryId())
				}
			}

			// The filter matches any name on an entry, case-insensitively.
			for _, name := range []string{"priya", " ALEX "} {
				byPerson, err := entries.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
					Person:     name,
					CategoryId: supportID,
				}, token))
				if err != nil {
					t.Fatalf("list support by %q: %v", name, err)
				}
				if len(byPerson.Msg.GetEntries()) != 1 || byPerson.Msg.GetEntries()[0].GetId() != first.GetId() {
					t.Fatalf("entries for %q = %+v, want the multi-person entry", name, byPerson.Msg.GetEntries())
				}
			}

			// A support entry without a person is rejected on the person field.
			_, err = entries.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
				CategoryId:    supportID,
				SubcategoryId: unblock,
				Description:   "Helped someone",
				StartedAt:     timestamppb.New(earlier),
				Duration:      durationpb.New(15 * time.Minute),
			}, token))
			if connect.CodeOf(err) != connect.CodeInvalidArgument {
				t.Fatalf("person rule code = %v, want invalid argument", connect.CodeOf(err))
			}
			if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "person" {
				t.Fatalf("person rule fields = %v, want person", fields)
			}

			// A project is a subcategory of an initiative-role category, so a
			// support entry can never be filed against one.
			_, err = entries.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
				CategoryId:    supportID,
				SubcategoryId: project,
				Description:   "Cross-attributed support",
				People:        []string{"Priya"},
				StartedAt:     timestamppb.New(earlier),
				Duration:      durationpb.New(15 * time.Minute),
			}, token))
			if connect.CodeOf(err) != connect.CodeInvalidArgument {
				t.Fatalf("cross-attribution code = %v, want invalid argument", connect.CodeOf(err))
			}
			if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "subcategoryId" {
				t.Fatalf("cross-attribution fields = %v, want subcategoryId", fields)
			}

			projectEntries, err := entries.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
				CategoryId: initiativeID,
			}, token))
			if err != nil {
				t.Fatalf("list initiative entries: %v", err)
			}
			if len(projectEntries.Msg.GetEntries()) != 0 {
				t.Fatalf("initiative entries = %+v, want no support work", projectEntries.Msg.GetEntries())
			}
		})
	}
}

func createMode(t *testing.T, client wdidv1connect.CategoryServiceClient, token, categoryID, name string) string {
	t.Helper()
	response, err := client.CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: categoryID,
		Name:       name,
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("create subcategory %q: %v", name, err)
	}
	return response.Msg.GetSubcategory().GetId()
}
