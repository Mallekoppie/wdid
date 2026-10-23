package rpc_test

import (
	"context"
	"net/http/httptest"
	"testing"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
)

func summaryClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.SummaryServiceClient {
	return wdidv1connect.NewSummaryServiceClient(server.Client(), server.URL, options...)
}

func createSupportTaxonomy(t *testing.T, server *httptest.Server, token string) (categoryID, modeID string) {
	t.Helper()

	category, err := categoryClient(server).CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Support",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT,
	}, token))
	if err != nil {
		t.Fatalf("create support category: %v", err)
	}
	categoryID = category.Msg.GetCategory().GetId()

	mode, err := categoryClient(server).CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: categoryID,
		Name:       "Unblock",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("create support mode: %v", err)
	}
	return categoryID, mode.Msg.GetSubcategory().GetId()
}

func createReportEntry(t *testing.T, server *httptest.Server, token string, request *wdidv1.CreateEntryRequest) *wdidv1.WorkEntry {
	t.Helper()

	response, err := entryClient(server).CreateEntry(context.Background(), withBearer(request, token))
	if err != nil {
		t.Fatalf("create entry: %v", err)
	}
	return response.Msg.GetEntry()
}

func currentUserID(t *testing.T, server *httptest.Server, token string) string {
	t.Helper()

	response, err := authClient(server).GetCurrentUser(context.Background(), withBearer(&wdidv1.GetCurrentUserRequest{}, token))
	if err != nil {
		t.Fatalf("get current user: %v", err)
	}
	return response.Msg.GetUser().GetId()
}

// updateReportTimezone sets the account's timezone so report boundaries have a
// non-UTC day to resolve.
func updateReportTimezone(t *testing.T, client wdidv1connect.SettingsServiceClient, token, timezone string) {
	t.Helper()

	if _, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: &wdidv1.Settings{
			Timezone:             timezone,
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
	}, token)); err != nil {
		t.Fatalf("update settings: %v", err)
	}
}

func TestSummaryServiceRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)

	_, err := summaryClient(server).GetPeriodReport(context.Background(), connect.NewRequest(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-19",
	}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

func TestSummaryServiceGetPeriodReportAggregates(t *testing.T) {
	server, database := newDomainServer(t)
	token := bootstrapToken(t, server)
	initiativeID, billingID := createEntryTaxonomy(t, server, token)
	supportID, unblockID := createSupportTaxonomy(t, server, token)

	monday := time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC)
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    initiativeID,
		SubcategoryId: billingID,
		Description:   "Backfill script",
		StartedAt:     timestamppb.New(monday),
		Duration:      durationpb.New(60 * time.Minute),
	})
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    supportID,
		SubcategoryId: unblockID,
		Description:   "Unblocked the CI keys",
		Person:        "Priya",
		StartedAt:     timestamppb.New(monday.Add(2 * time.Hour)),
		Duration:      durationpb.New(30 * time.Minute),
	})

	// The note service arrives with a later slice; seed the context directly so
	// the report's note section is exercised now.
	if err := database.SaveNote(domain.Note{
		ID:        "note-day",
		UserID:    currentUserID(t, server, token),
		Date:      "2026-10-19",
		Text:      "Shipped the backfill",
		CreatedAt: monday.Add(4 * time.Hour),
	}); err != nil {
		t.Fatalf("save note: %v", err)
	}

	response, err := summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-19",
	}, token))
	if err != nil {
		t.Fatalf("get period report: %v", err)
	}

	report := response.Msg.GetReport()
	if report.GetFromDate() != "2026-10-19" || report.GetToDate() != "2026-10-19" {
		t.Fatalf("period = %s..%s, want the requested range", report.GetFromDate(), report.GetToDate())
	}
	if report.GetTotal().AsDuration() != 90*time.Minute || report.GetEntryCount() != 2 {
		t.Fatalf("totals = %v/%d, want 90m across 2 entries", report.GetTotal().AsDuration(), report.GetEntryCount())
	}

	categories := report.GetCategories()
	if len(categories) != 2 {
		t.Fatalf("categories = %+v, want Focus and Support", categories)
	}
	if categories[0].GetName() != "Focus" || categories[0].GetDuration().AsDuration() != 60*time.Minute ||
		categories[0].GetRole() != wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE ||
		categories[0].GetEntryCount() != 1 {
		t.Fatalf("first category = %+v, want Focus with 60m", categories[0])
	}
	if categories[1].GetName() != "Support" || categories[1].GetDuration().AsDuration() != 30*time.Minute {
		t.Fatalf("second category = %+v, want Support with 30m", categories[1])
	}

	subcategories := report.GetSubcategories()
	if len(subcategories) != 2 ||
		subcategories[0].GetName() != "Billing migration" || subcategories[0].GetDuration().AsDuration() != 60*time.Minute ||
		subcategories[1].GetName() != "Unblock" || subcategories[1].GetDuration().AsDuration() != 30*time.Minute {
		t.Fatalf("subcategories = %+v, want Billing migration then Unblock", subcategories)
	}
	if subcategories[0].GetLastActivityDate() != "2026-10-19" ||
		subcategories[0].GetLastActivityDescription() != "Backfill script" {
		t.Fatalf("billing last activity = %q/%q, want the latest entry",
			subcategories[0].GetLastActivityDate(), subcategories[0].GetLastActivityDescription())
	}

	people := report.GetSupportPeople()
	if len(people) != 1 || people[0].GetPerson() != "Priya" ||
		people[0].GetDuration().AsDuration() != 30*time.Minute || people[0].GetInteractions() != 1 {
		t.Fatalf("support people = %+v, want Priya with 30m and one interaction", people)
	}
	modes := report.GetSupportModes()
	if len(modes) != 1 || modes[0].GetName() != "Unblock" || modes[0].GetDuration().AsDuration() != 30*time.Minute {
		t.Fatalf("support modes = %+v, want Unblock with 30m", modes)
	}

	weeks := report.GetWeeks()
	if len(weeks) != 1 || weeks[0].GetWeekStartDate() != "2026-10-19" ||
		weeks[0].GetDuration().AsDuration() != 90*time.Minute ||
		weeks[0].GetTopCategoryName() != "Focus" {
		t.Fatalf("weeks = %+v, want the week of 19 October topped by Focus", weeks)
	}

	notes := report.GetNotes()
	if len(notes) != 1 || notes[0].GetId() != "note-day" || notes[0].GetDate() != "2026-10-19" {
		t.Fatalf("notes = %+v, want the day note inside the period", notes)
	}
}

func TestSummaryServiceUsesTheUsersTimezoneForPeriodBoundaries(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categoryID, subcategoryID := createEntryTaxonomy(t, server, token)

	updateReportTimezone(t, settingsClient(server), token, "Europe/Amsterdam")

	// 22:30 UTC on 18 October is already 19 October in Amsterdam.
	inside := createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   "After midnight local time",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 18, 22, 30, 0, 0, time.UTC)),
		Duration:      durationpb.New(42 * time.Minute),
	})
	// 22:30 UTC on 19 October is 20 October in Amsterdam.
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   "Next local day",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 19, 22, 30, 0, 0, time.UTC)),
		Duration:      durationpb.New(30 * time.Minute),
	})

	response, err := summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-19",
	}, token))
	if err != nil {
		t.Fatalf("get period report: %v", err)
	}
	if response.Msg.GetReport().GetEntryCount() != 1 ||
		response.Msg.GetReport().GetTotal().AsDuration() != 42*time.Minute {
		t.Fatalf("report = %+v, want only the entry whose Amsterdam date is 19 October", response.Msg.GetReport())
	}
	if inside.GetLocalDate() != "2026-10-19" {
		t.Fatalf("entry localDate = %q, want 2026-10-19", inside.GetLocalDate())
	}
}

func TestSummaryServiceResolvesCurrentWeekOnTheServer(t *testing.T) {
	// 22:30 UTC on 21 October is 00:30 on 22 October in Amsterdam, inside the
	// week that starts on Monday 19 October.
	now := time.Date(2026, 10, 21, 22, 30, 0, 0, time.UTC)
	server, _ := newDomainServerWithSummaryClock(t, func() time.Time { return now })
	token := bootstrapToken(t, server)
	categoryID, subcategoryID := createEntryTaxonomy(t, server, token)
	updateReportTimezone(t, settingsClient(server), token, "Europe/Amsterdam")

	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   "This local week",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 18, 22, 30, 0, 0, time.UTC)),
		Duration:      durationpb.New(42 * time.Minute),
	})
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   "Next local week",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 26, 9, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(30 * time.Minute),
	})

	response, err := summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		CurrentWeek: true,
	}, token))
	if err != nil {
		t.Fatalf("current week report: %v", err)
	}

	report := response.Msg.GetReport()
	if report.GetFromDate() != "2026-10-19" || report.GetToDate() != "2026-10-25" {
		t.Fatalf("period = %s..%s, want the server-resolved week", report.GetFromDate(), report.GetToDate())
	}
	if report.GetTotal().AsDuration() != 42*time.Minute || report.GetEntryCount() != 1 {
		t.Fatalf("current week = %v/%d, want only this week's entry", report.GetTotal().AsDuration(), report.GetEntryCount())
	}
}

func TestSummaryServiceEmptyAndInvalidPeriods(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)

	empty, err := summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-01-01",
		ToDate:   "2026-01-07",
	}, token))
	if err != nil {
		t.Fatalf("empty period: %v", err)
	}
	if empty.Msg.GetReport().GetTotal().AsDuration() != 0 ||
		empty.Msg.GetReport().GetEntryCount() != 0 ||
		len(empty.Msg.GetReport().GetCategories()) != 0 ||
		len(empty.Msg.GetReport().GetWeeks()) != 2 {
		t.Fatalf("empty report = %+v, want zero totals and the two weeks the period touches", empty.Msg.GetReport())
	}

	_, err = summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		ToDate: "2026-01-07",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("missing start code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "fromDate" {
		t.Fatalf("missing start violations = %v, want fromDate", fields)
	}

	_, err = summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-01-07",
		ToDate:   "2026-01-01",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("reversed period code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "toDate" {
		t.Fatalf("reversed period violations = %v, want toDate", fields)
	}
}

func TestSummaryServiceServesGRPCWeb(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categories := categoryClient(server, connect.WithGRPCWeb())
	category, err := categories.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Initiatives",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateCategory: %v", err)
	}
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:  category.Msg.GetCategory().GetId(),
		Description: "Web report entry",
		StartedAt:   timestamppb.New(time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC)),
		Duration:    durationpb.New(45 * time.Minute),
	})

	response, err := summaryClient(server, connect.WithGRPCWeb()).GetPeriodReport(
		context.Background(),
		withBearer(&wdidv1.GetPeriodReportRequest{
			FromDate: "2026-10-19",
			ToDate:   "2026-10-19",
		}, token),
	)
	if err != nil {
		t.Fatalf("gRPC-Web GetPeriodReport: %v", err)
	}
	if response.Msg.GetReport().GetTotal().AsDuration() != 45*time.Minute ||
		len(response.Msg.GetReport().GetCategories()) != 1 {
		t.Fatalf("gRPC-Web report = %+v, want 45m in one category", response.Msg.GetReport())
	}

	// An empty period is a zero report, not an error, over gRPC-Web too.
	empty, err := summaryClient(server, connect.WithGRPCWeb()).GetPeriodReport(
		context.Background(),
		withBearer(&wdidv1.GetPeriodReportRequest{
			FromDate: "2026-01-01",
			ToDate:   "2026-01-07",
		}, token),
	)
	if err != nil {
		t.Fatalf("gRPC-Web empty report: %v", err)
	}
	if empty.Msg.GetReport().GetTotal().AsDuration() != 0 ||
		empty.Msg.GetReport().GetEntryCount() != 0 {
		t.Fatalf("gRPC-Web empty report = %+v, want zero totals", empty.Msg.GetReport())
	}

	// The same boundary rules hold over gRPC-Web: 22:30 UTC on 18 October is
	// already 19 October in Amsterdam.
	updateReportTimezone(t, settingsClient(server, connect.WithGRPCWeb()), token, "Europe/Amsterdam")
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:  category.Msg.GetCategory().GetId(),
		Description: "After midnight in Amsterdam",
		StartedAt:   timestamppb.New(time.Date(2026, 10, 18, 22, 30, 0, 0, time.UTC)),
		Duration:    durationpb.New(30 * time.Minute),
	})

	boundary, err := summaryClient(server, connect.WithGRPCWeb()).GetPeriodReport(
		context.Background(),
		withBearer(&wdidv1.GetPeriodReportRequest{
			FromDate: "2026-10-19",
			ToDate:   "2026-10-19",
		}, token),
	)
	if err != nil {
		t.Fatalf("gRPC-Web boundary report: %v", err)
	}
	if boundary.Msg.GetReport().GetTotal().AsDuration() != 75*time.Minute ||
		boundary.Msg.GetReport().GetEntryCount() != 2 {
		t.Fatalf("gRPC-Web boundary report = %+v, want both entries on the local 19th", boundary.Msg.GetReport())
	}

	previousDay, err := summaryClient(server, connect.WithGRPCWeb()).GetPeriodReport(
		context.Background(),
		withBearer(&wdidv1.GetPeriodReportRequest{
			FromDate: "2026-10-18",
			ToDate:   "2026-10-18",
		}, token),
	)
	if err != nil {
		t.Fatalf("gRPC-Web previous-day report: %v", err)
	}
	if previousDay.Msg.GetReport().GetEntryCount() != 0 {
		t.Fatalf("gRPC-Web previous-day report = %+v, want no entries", previousDay.Msg.GetReport())
	}
}
