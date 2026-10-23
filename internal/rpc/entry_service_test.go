package rpc_test

import (
	"context"
	"net/http/httptest"
	"slices"
	"testing"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
)

func entryClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.EntryServiceClient {
	return wdidv1connect.NewEntryServiceClient(server.Client(), server.URL, options...)
}

func createEntryTaxonomy(t *testing.T, server *httptest.Server, token string) (categoryID, subcategoryID string) {
	t.Helper()

	category, err := categoryClient(server).CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Focus",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
	}, token))
	if err != nil {
		t.Fatalf("create category: %v", err)
	}
	categoryID = category.Msg.GetCategory().GetId()

	subcategory, err := categoryClient(server).CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: categoryID,
		Name:       "Billing migration",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("create subcategory: %v", err)
	}
	return categoryID, subcategory.Msg.GetSubcategory().GetId()
}

func TestEntryServiceRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)

	_, err := entryClient(server).ListEntries(context.Background(), connect.NewRequest(&wdidv1.ListEntriesRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

func TestEntryServiceCreatesListsAndAddsOutcome(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categoryID, subcategoryID := createEntryTaxonomy(t, server, token)
	client := entryClient(server)

	started := time.Now().UTC()
	created, err := client.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   "  Backfill script skeleton  ",
		StartedAt:     timestamppb.New(started),
		Duration:      durationpb.New(42 * time.Minute),
	}, token))
	if err != nil {
		t.Fatalf("create entry: %v", err)
	}

	entry := created.Msg.GetEntry()
	if entry.GetId() == "" {
		t.Fatal("created entry has no id")
	}
	if entry.GetDescription() != "Backfill script skeleton" {
		t.Fatalf("description = %q, want the trimmed description", entry.GetDescription())
	}
	if entry.GetCategoryId() != categoryID || entry.GetSubcategoryId() != subcategoryID {
		t.Fatalf("attribution = %s/%s, want %s/%s", entry.GetCategoryId(), entry.GetSubcategoryId(), categoryID, subcategoryID)
	}
	if entry.GetDuration().AsDuration() != 42*time.Minute {
		t.Fatalf("duration = %v, want 42m", entry.GetDuration().AsDuration())
	}
	if entry.GetLocalDate() != started.Format(domain.DateLayout) {
		t.Fatalf("localDate = %q, want the started day", entry.GetLocalDate())
	}
	if entry.GetSource() != wdidv1.EntrySource_ENTRY_SOURCE_MANUAL {
		t.Fatalf("source = %v, want manual", entry.GetSource())
	}

	updated, err := client.UpdateEntry(context.Background(), withBearer(&wdidv1.UpdateEntryRequest{
		Id:            entry.GetId(),
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   entry.GetDescription(),
		Outcome:       "Script runs against staging",
		StartedAt:     entry.GetStartedAt(),
		Duration:      entry.GetDuration(),
	}, token))
	if err != nil {
		t.Fatalf("add outcome: %v", err)
	}
	if updated.Msg.GetEntry().GetOutcome() != "Script runs against staging" {
		t.Fatalf("outcome = %q, want the saved outcome", updated.Msg.GetEntry().GetOutcome())
	}

	listed, err := client.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
		LocalDate: entry.GetLocalDate(),
	}, token))
	if err != nil {
		t.Fatalf("list entries: %v", err)
	}
	if len(listed.Msg.GetEntries()) != 1 {
		t.Fatalf("entries = %d, want one for the day", len(listed.Msg.GetEntries()))
	}
	listedEntry := listed.Msg.GetEntries()[0]
	if listedEntry.GetCategoryId() != categoryID ||
		listedEntry.GetSubcategoryId() != subcategoryID ||
		listedEntry.GetDescription() != "Backfill script skeleton" ||
		listedEntry.GetOutcome() != "Script runs against staging" {
		t.Fatalf("listed entry = %+v, want attribution, description and outcome", listedEntry)
	}

	// The server owns the day boundary: `today` resolves in the user's
	// configured timezone instead of trusting a client date.
	today, err := client.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{Today: true}, token))
	if err != nil {
		t.Fatalf("list today: %v", err)
	}
	if len(today.Msg.GetEntries()) != 1 || today.Msg.GetEntries()[0].GetId() != entry.GetId() {
		t.Fatalf("today entries = %+v, want the created entry", today.Msg.GetEntries())
	}
}

func TestEntryServiceUsesTheSettingsDefaultDuration(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categoryID, _ := createEntryTaxonomy(t, server, token)
	client := entryClient(server)

	created, err := client.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
		CategoryId:  categoryID,
		Description: "Pointless meeting",
		StartedAt:   timestamppb.New(time.Now().UTC()),
	}, token))
	if err != nil {
		t.Fatalf("create entry without duration: %v", err)
	}
	if got := created.Msg.GetEntry().GetDuration().AsDuration(); got != 30*time.Minute {
		t.Fatalf("duration = %v, want the seeded 30m default", got)
	}

	settings := &wdidv1.Settings{
		Timezone:             "UTC",
		WeekStart:            1,
		DailyTarget:          minutes(450),
		ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_OFF,
		LongTimerThreshold:   minutes(240),
		DefaultEntryDuration: minutes(45),
		BackupInterval:       minutes(360),
		BackupRetention:      30,
		Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM,
		Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMFORTABLE,
	}
	if _, err := settingsClient(server).UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: settings}, token)); err != nil {
		t.Fatalf("update settings: %v", err)
	}

	created, err = client.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
		CategoryId:  categoryID,
		Description: "Default lunch",
		StartedAt:   timestamppb.New(time.Now().UTC()),
	}, token))
	if err != nil {
		t.Fatalf("create entry with updated default: %v", err)
	}
	if got := created.Msg.GetEntry().GetDuration().AsDuration(); got != 45*time.Minute {
		t.Fatalf("duration = %v, want the updated 45m default", got)
	}
}

func TestEntryServiceRejectsInvalidEntries(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categoryID, subcategoryID := createEntryTaxonomy(t, server, token)
	client := entryClient(server)

	otherCategory, err := categoryClient(server).CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Other",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_OTHER,
	}, token))
	if err != nil {
		t.Fatalf("create other category: %v", err)
	}

	supportCategory, err := categoryClient(server).CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Support",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT,
	}, token))
	if err != nil {
		t.Fatalf("create support category: %v", err)
	}

	valid := func() *wdidv1.CreateEntryRequest {
		return &wdidv1.CreateEntryRequest{
			CategoryId:  categoryID,
			Description: "Backfill",
			StartedAt:   timestamppb.New(time.Now().UTC()),
			Duration:    durationpb.New(30 * time.Minute),
		}
	}

	cases := []struct {
		name   string
		mutate func(*wdidv1.CreateEntryRequest)
		field  string
	}{
		{"missing description", func(r *wdidv1.CreateEntryRequest) { r.Description = "  " }, "description"},
		{"missing category", func(r *wdidv1.CreateEntryRequest) { r.CategoryId = "" }, "categoryId"},
		{"unknown category", func(r *wdidv1.CreateEntryRequest) { r.CategoryId = "missing" }, "categoryId"},
		{
			"subcategory from another category",
			func(r *wdidv1.CreateEntryRequest) {
				r.CategoryId = otherCategory.Msg.GetCategory().GetId()
				r.SubcategoryId = subcategoryID
			},
			"subcategoryId",
		},
		{
			"support without person",
			func(r *wdidv1.CreateEntryRequest) { r.CategoryId = supportCategory.Msg.GetCategory().GetId() },
			"person",
		},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			request := valid()
			testCase.mutate(request)
			_, err := client.CreateEntry(context.Background(), withBearer(request, token))
			if connect.CodeOf(err) != connect.CodeInvalidArgument {
				t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
			}
			if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != testCase.field {
				t.Fatalf("field violations = %v, want %s", fields, testCase.field)
			}
		})
	}
}

func TestEntryServiceFiltersAndFlagsOverlaps(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categoryID, subcategoryID := createEntryTaxonomy(t, server, token)
	client := entryClient(server)

	otherCategory, err := categoryClient(server).CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Other",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_OTHER,
	}, token))
	if err != nil {
		t.Fatalf("create other category: %v", err)
	}
	otherCategoryID := otherCategory.Msg.GetCategory().GetId()

	dayOne := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC)
	dayTwo := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)

	create := func(category, subcategory, description string, started time.Time, minutes int) *wdidv1.WorkEntry {
		t.Helper()
		response, err := client.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
			CategoryId:    category,
			SubcategoryId: subcategory,
			Description:   description,
			StartedAt:     timestamppb.New(started),
			Duration:      durationpb.New(time.Duration(minutes) * time.Minute),
		}, token))
		if err != nil {
			t.Fatalf("create %q: %v", description, err)
		}
		return response.Msg.GetEntry()
	}

	backfill := create(categoryID, subcategoryID, "Backfill script", dayOne, 60)
	standup := create(otherCategoryID, "", "Daily standup", dayOne.Add(30*time.Minute), 30)
	nextDay := create(categoryID, subcategoryID, "Backfill review", dayTwo, 30)

	list := func(request *wdidv1.ListEntriesRequest) *wdidv1.ListEntriesResponse {
		t.Helper()
		response, err := client.ListEntries(context.Background(), withBearer(request, token))
		if err != nil {
			t.Fatalf("list entries: %v", err)
		}
		return response.Msg
	}

	dayOneRange := &wdidv1.ListEntriesRequest{
		From: timestamppb.New(dayOne),
		To:   timestamppb.New(dayTwo),
	}

	all := list(&wdidv1.ListEntriesRequest{})
	if len(all.GetEntries()) != 3 {
		t.Fatalf("all entries = %d, want 3", len(all.GetEntries()))
	}
	if !slices.Contains(all.GetOverlappingEntryIds(), backfill.GetId()) ||
		!slices.Contains(all.GetOverlappingEntryIds(), standup.GetId()) {
		t.Fatalf("overlaps = %v, want the intersecting pair", all.GetOverlappingEntryIds())
	}
	if slices.Contains(all.GetOverlappingEntryIds(), nextDay.GetId()) {
		t.Fatalf("overlaps = %v, want the next-day entry unflagged", all.GetOverlappingEntryIds())
	}

	byCategory := list(&wdidv1.ListEntriesRequest{CategoryId: categoryID})
	if len(byCategory.GetEntries()) != 2 {
		t.Fatalf("category entries = %d, want the two initiative entries", len(byCategory.GetEntries()))
	}
	// The marker follows the entry, not the filter: the backfill still
	// intersects the standup even though the standup is filtered out.
	if !slices.Contains(byCategory.GetOverlappingEntryIds(), backfill.GetId()) {
		t.Fatalf("category overlaps = %v, want the backfill still flagged", byCategory.GetOverlappingEntryIds())
	}
	if slices.Contains(byCategory.GetOverlappingEntryIds(), nextDay.GetId()) {
		t.Fatalf("category overlaps = %v, want the next-day entry unflagged", byCategory.GetOverlappingEntryIds())
	}

	bySubcategory := list(&wdidv1.ListEntriesRequest{SubcategoryId: subcategoryID})
	if len(bySubcategory.GetEntries()) != 2 {
		t.Fatalf("subcategory entries = %d, want the two attributed entries", len(bySubcategory.GetEntries()))
	}

	byQuery := list(&wdidv1.ListEntriesRequest{Query: "standup"})
	if len(byQuery.GetEntries()) != 1 || byQuery.GetEntries()[0].GetId() != standup.GetId() {
		t.Fatalf("query entries = %+v, want the standup", byQuery.GetEntries())
	}

	combined := list(&wdidv1.ListEntriesRequest{
		From:       dayOneRange.GetFrom(),
		To:         dayOneRange.GetTo(),
		CategoryId: categoryID,
		Query:      "script",
	})
	if len(combined.GetEntries()) != 1 || combined.GetEntries()[0].GetId() != backfill.GetId() {
		t.Fatalf("combined entries = %+v, want only the backfill", combined.GetEntries())
	}

	nextDayRange := list(&wdidv1.ListEntriesRequest{
		From: timestamppb.New(dayTwo),
		To:   timestamppb.New(dayTwo.Add(24 * time.Hour)),
	})
	if len(nextDayRange.GetEntries()) != 1 || nextDayRange.GetEntries()[0].GetId() != nextDay.GetId() {
		t.Fatalf("range entries = %+v, want the next-day entry", nextDayRange.GetEntries())
	}
}

func TestEntryServiceResolvesLocalDateFiltersInTheUsersTimezone(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categoryID, _ := createEntryTaxonomy(t, server, token)

	_, err := settingsClient(server).UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: &wdidv1.Settings{
			Timezone:             "Europe/Amsterdam",
			WeekStart:            1,
			DailyTarget:          minutes(450),
			ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_OFF,
			LongTimerThreshold:   minutes(240),
			DefaultEntryDuration: minutes(30),
			BackupInterval:       minutes(360),
			BackupRetention:      30,
			Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM,
			Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMFORTABLE,
		},
	}, token))
	if err != nil {
		t.Fatalf("update settings: %v", err)
	}

	// 23:30 UTC on 17 October is already 01:30 on 18 October in Amsterdam.
	created, err := entryClient(server).CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
		CategoryId:  categoryID,
		Description: "Late backfill",
		StartedAt:   timestamppb.New(time.Date(2026, 10, 17, 23, 30, 0, 0, time.UTC)),
		Duration:    durationpb.New(60 * time.Minute),
	}, token))
	if err != nil {
		t.Fatalf("create entry: %v", err)
	}
	if created.Msg.GetEntry().GetLocalDate() != "2026-10-18" {
		t.Fatalf("localDate = %q, want the Amsterdam day", created.Msg.GetEntry().GetLocalDate())
	}

	list := func(request *wdidv1.ListEntriesRequest) *wdidv1.ListEntriesResponse {
		t.Helper()
		response, err := entryClient(server).ListEntries(context.Background(), withBearer(request, token))
		if err != nil {
			t.Fatalf("list entries: %v", err)
		}
		return response.Msg
	}

	amsterdamDay := list(&wdidv1.ListEntriesRequest{
		FromDate: "2026-10-18",
		ToDate:   "2026-10-18",
	})
	if len(amsterdamDay.GetEntries()) != 1 {
		t.Fatalf("Amsterdam-day entries = %d, want the late entry", len(amsterdamDay.GetEntries()))
	}

	utcDay := list(&wdidv1.ListEntriesRequest{
		FromDate: "2026-10-17",
		ToDate:   "2026-10-17",
	})
	if len(utcDay.GetEntries()) != 0 {
		t.Fatalf("previous-day entries = %d, want none", len(utcDay.GetEntries()))
	}

	for _, testCase := range []struct {
		name    string
		request *wdidv1.ListEntriesRequest
		field   string
	}{
		{"bad from date", &wdidv1.ListEntriesRequest{FromDate: "18-10-2026"}, "fromDate"},
		{"bad to date", &wdidv1.ListEntriesRequest{ToDate: "tomorrow"}, "toDate"},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := entryClient(server).ListEntries(context.Background(), withBearer(testCase.request, token))
			if connect.CodeOf(err) != connect.CodeInvalidArgument {
				t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
			}
			if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != testCase.field {
				t.Fatalf("field violations = %v, want %s", fields, testCase.field)
			}
		})
	}
}

func TestEntryServiceSplitsEntries(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categoryID, subcategoryID := createEntryTaxonomy(t, server, token)
	client := entryClient(server)

	started := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC)
	created, err := client.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   "Long backfill",
		StartedAt:     timestamppb.New(started),
		Duration:      durationpb.New(60 * time.Minute),
	}, token))
	if err != nil {
		t.Fatalf("create entry: %v", err)
	}
	original := created.Msg.GetEntry()

	split, err := client.SplitEntry(context.Background(), withBearer(&wdidv1.SplitEntryRequest{
		Id: original.GetId(),
		At: durationpb.New(25 * time.Minute),
	}, token))
	if err != nil {
		t.Fatalf("split entry: %v", err)
	}

	first := split.Msg.GetFirst()
	second := split.Msg.GetSecond()
	if first.GetId() != original.GetId() {
		t.Fatalf("first id = %q, want the original id", first.GetId())
	}
	if first.GetDuration().AsDuration() != 25*time.Minute ||
		!first.GetStartedAt().AsTime().Equal(started) ||
		!first.GetEndedAt().AsTime().Equal(started.Add(25*time.Minute)) {
		t.Fatalf("first half = %+v, want 09:00–09:25 with 25 minutes", first)
	}
	if second.GetId() == "" || second.GetId() == first.GetId() {
		t.Fatalf("second id = %q, want a new id", second.GetId())
	}
	if second.GetDuration().AsDuration() != 35*time.Minute ||
		!second.GetStartedAt().AsTime().Equal(first.GetEndedAt().AsTime()) ||
		!second.GetEndedAt().AsTime().Equal(started.Add(60*time.Minute)) {
		t.Fatalf("second half = %+v, want 09:25–10:00 with 35 minutes", second)
	}
	if second.GetCategoryId() != categoryID || second.GetSubcategoryId() != subcategoryID ||
		second.GetDescription() != "Long backfill" {
		t.Fatalf("second half attribution = %+v, want the original fields", second)
	}

	listed, err := client.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
		LocalDate: first.GetLocalDate(),
	}, token))
	if err != nil {
		t.Fatalf("list split halves: %v", err)
	}
	if len(listed.Msg.GetEntries()) != 2 {
		t.Fatalf("split entries = %d, want both halves", len(listed.Msg.GetEntries()))
	}
	if len(listed.Msg.GetOverlappingEntryIds()) != 0 {
		t.Fatalf("split overlaps = %v, want none for contiguous halves", listed.Msg.GetOverlappingEntryIds())
	}

	for _, at := range []int32{0, 60, -5} {
		_, err := client.SplitEntry(context.Background(), withBearer(&wdidv1.SplitEntryRequest{
			Id: first.GetId(),
			At: durationpb.New(time.Duration(at) * time.Minute),
		}, token))
		if connect.CodeOf(err) != connect.CodeInvalidArgument {
			t.Fatalf("split at %d code = %v, want invalid argument", at, connect.CodeOf(err))
		}
		if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "atMinutes" {
			t.Fatalf("split at %d fields = %v, want atMinutes", at, fields)
		}
	}

	_, err = client.SplitEntry(context.Background(), withBearer(&wdidv1.SplitEntryRequest{
		Id: "missing",
		At: durationpb.New(10 * time.Minute),
	}, token))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("missing split code = %v, want not found", connect.CodeOf(err))
	}

	// Both halves are ordinary entries: one can be edited or deleted on its own.
	updated, err := client.UpdateEntry(context.Background(), withBearer(&wdidv1.UpdateEntryRequest{
		Id:            second.GetId(),
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   second.GetDescription(),
		Outcome:       "Checked the backfill output",
		StartedAt:     second.GetStartedAt(),
		Duration:      second.GetDuration(),
	}, token))
	if err != nil {
		t.Fatalf("update second half: %v", err)
	}
	if updated.Msg.GetEntry().GetOutcome() != "Checked the backfill output" {
		t.Fatalf("second outcome = %q, want the update", updated.Msg.GetEntry().GetOutcome())
	}
	if _, err := client.DeleteEntry(context.Background(), withBearer(&wdidv1.DeleteEntryRequest{Id: first.GetId()}, token)); err != nil {
		t.Fatalf("delete first half: %v", err)
	}

	remaining, err := client.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
		LocalDate: first.GetLocalDate(),
	}, token))
	if err != nil {
		t.Fatalf("list after delete: %v", err)
	}
	if len(remaining.Msg.GetEntries()) != 1 || remaining.Msg.GetEntries()[0].GetId() != second.GetId() {
		t.Fatalf("remaining entries = %+v, want only the second half", remaining.Msg.GetEntries())
	}
}

func TestEntryServiceServesGRPCWeb(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := entryClient(server, connect.WithGRPCWeb())

	categoryResponse, err := categoryClient(server, connect.WithGRPCWeb()).CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Web work",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_OTHER,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateCategory: %v", err)
	}

	created, err := client.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
		CategoryId:  categoryResponse.Msg.GetCategory().GetId(),
		Description: "Web capture",
		StartedAt:   timestamppb.New(time.Now().UTC()),
		Duration:    durationpb.New(15 * time.Minute),
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateEntry: %v", err)
	}
	if created.Msg.GetEntry().GetDuration().AsDuration() != 15*time.Minute {
		t.Fatalf("gRPC-Web created = %+v", created.Msg.GetEntry())
	}

	listed, err := client.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
		Today: true,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web ListEntries: %v", err)
	}
	if len(listed.Msg.GetEntries()) != 1 {
		t.Fatalf("gRPC-Web entries = %d, want one", len(listed.Msg.GetEntries()))
	}

	_, err = client.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
		CategoryId: categoryResponse.Msg.GetCategory().GetId(),
		StartedAt:  timestamppb.New(time.Now().UTC()),
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("gRPC-Web validation code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "description" {
		t.Fatalf("gRPC-Web field violations = %v, want description", fields)
	}
}

func TestEntryServiceLogEditingServesGRPCWeb(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := entryClient(server, connect.WithGRPCWeb())
	categories := categoryClient(server, connect.WithGRPCWeb())

	categoryResponse, err := categories.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Initiatives",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateCategory: %v", err)
	}
	categoryID := categoryResponse.Msg.GetCategory().GetId()
	subcategoryResponse, err := categories.CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: categoryID,
		Name:       "Billing migration",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateSubcategory: %v", err)
	}
	subcategoryID := subcategoryResponse.Msg.GetSubcategory().GetId()

	started := time.Date(2026, 10, 17, 9, 0, 0, 0, time.UTC)
	create := func(description string, start time.Time, minutes int) *wdidv1.WorkEntry {
		t.Helper()
		response, err := client.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
			CategoryId:    categoryID,
			SubcategoryId: subcategoryID,
			Description:   description,
			StartedAt:     timestamppb.New(start),
			Duration:      durationpb.New(time.Duration(minutes) * time.Minute),
		}, token))
		if err != nil {
			t.Fatalf("gRPC-Web CreateEntry: %v", err)
		}
		return response.Msg.GetEntry()
	}

	first := create("Backfill script", started, 60)
	second := create("Backfill review", started.Add(30*time.Minute), 30)

	listed, err := client.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
		From:          timestamppb.New(started),
		To:            timestamppb.New(started.Add(24 * time.Hour)),
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Query:         "backfill",
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web ListEntries: %v", err)
	}
	if len(listed.Msg.GetEntries()) != 2 {
		t.Fatalf("gRPC-Web filtered entries = %d, want 2", len(listed.Msg.GetEntries()))
	}
	if !slices.Contains(listed.Msg.GetOverlappingEntryIds(), first.GetId()) ||
		!slices.Contains(listed.Msg.GetOverlappingEntryIds(), second.GetId()) {
		t.Fatalf("gRPC-Web overlaps = %v, want both entries", listed.Msg.GetOverlappingEntryIds())
	}

	updated, err := client.UpdateEntry(context.Background(), withBearer(&wdidv1.UpdateEntryRequest{
		Id:            second.GetId(),
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   second.GetDescription(),
		Outcome:       "Reviewed with Priya",
		StartedAt:     second.GetStartedAt(),
		Duration:      second.GetDuration(),
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web UpdateEntry: %v", err)
	}
	if updated.Msg.GetEntry().GetOutcome() != "Reviewed with Priya" {
		t.Fatalf("gRPC-Web update outcome = %q", updated.Msg.GetEntry().GetOutcome())
	}

	split, err := client.SplitEntry(context.Background(), withBearer(&wdidv1.SplitEntryRequest{
		Id: first.GetId(),
		At: durationpb.New(20 * time.Minute),
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web SplitEntry: %v", err)
	}
	if split.Msg.GetFirst().GetDuration().AsDuration() != 20*time.Minute ||
		split.Msg.GetSecond().GetDuration().AsDuration() != 40*time.Minute {
		t.Fatalf("gRPC-Web split = %+v", split.Msg)
	}

	if _, err := client.DeleteEntry(context.Background(), withBearer(&wdidv1.DeleteEntryRequest{
		Id: split.Msg.GetSecond().GetId(),
	}, token)); err != nil {
		t.Fatalf("gRPC-Web DeleteEntry: %v", err)
	}

	afterDelete, err := client.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
		LocalDate: first.GetLocalDate(),
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web ListEntries after delete: %v", err)
	}
	if len(afterDelete.Msg.GetEntries()) != 2 {
		t.Fatalf("gRPC-Web entries after delete = %d, want the first half and the updated entry", len(afterDelete.Msg.GetEntries()))
	}
}

func TestEntryServiceIsolatesAccounts(t *testing.T) {
	server, database := newDomainServer(t)
	firstToken := bootstrapToken(t, server)
	categoryID, _ := createEntryTaxonomy(t, server, firstToken)

	created, err := entryClient(server).CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
		CategoryId:  categoryID,
		Description: "Private work",
		StartedAt:   timestamppb.New(time.Now().UTC()),
		Duration:    durationpb.New(30 * time.Minute),
	}, firstToken))
	if err != nil {
		t.Fatalf("create entry: %v", err)
	}

	code := createInvite(t, database, "second@example.com")
	second, err := authClient(server).RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:       "second@example.com",
		Password:    testPassword,
		DisplayName: "Second",
		InviteCode:  code,
	}))
	if err != nil {
		t.Fatalf("register second account: %v", err)
	}

	_, err = entryClient(server).GetEntry(context.Background(), withBearer(&wdidv1.GetEntryRequest{Id: created.Msg.GetEntry().GetId()}, second.Msg.GetToken()))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("cross-user get code = %v, want not found", connect.CodeOf(err))
	}

	listed, err := entryClient(server).ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{}, second.Msg.GetToken()))
	if err != nil {
		t.Fatalf("list second account entries: %v", err)
	}
	if len(listed.Msg.GetEntries()) != 0 {
		t.Fatalf("second account entries = %d, want none", len(listed.Msg.GetEntries()))
	}
}
