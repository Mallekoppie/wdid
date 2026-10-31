package rpc_test

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/ai"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
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
		People:        []string{"Priya"},
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
	if report.GetSupportDuration().AsDuration() != 30*time.Minute || report.GetSupportInteractions() != 1 {
		t.Fatalf("support totals = %v/%d interactions, want the authoritative 30m support entry",
			report.GetSupportDuration().AsDuration(), report.GetSupportInteractions())
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

func TestSummaryServiceSupportRollupsRespectPeriodBoundaries(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	supportID, unblockID := createSupportTaxonomy(t, server, token)

	review, err := categoryClient(server).CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: supportID,
		Name:       "Review",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("create review mode: %v", err)
	}
	reviewID := review.Msg.GetSubcategory().GetId()

	supportEntry := func(person, subcategoryID, description string, start time.Time, length time.Duration) {
		t.Helper()
		createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
			CategoryId:    supportID,
			SubcategoryId: subcategoryID,
			People:        []string{person},
			Description:   description,
			StartedAt:     timestamppb.New(start),
			Duration:      durationpb.New(length),
		})
	}

	// The period's inclusive first and last local days are inside; the entries
	// on either side are excluded. Person grouping is case-insensitive.
	supportEntry("Priya", unblockID, "Unblocked CI", time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC), 30*time.Minute)
	supportEntry("Priya", reviewID, "Reviewed the plan", time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC), 45*time.Minute)
	supportEntry("priya", unblockID, "Unblocked the keys", time.Date(2026, 10, 21, 9, 0, 0, 0, time.UTC), 15*time.Minute)
	supportEntry("Sam", unblockID, "Last day of the period", time.Date(2026, 10, 25, 23, 0, 0, 0, time.UTC), 60*time.Minute)
	supportEntry("Sam", unblockID, "Day after the period", time.Date(2026, 10, 26, 0, 0, 0, 0, time.UTC), 60*time.Minute)

	response, err := summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-25",
	}, token))
	if err != nil {
		t.Fatalf("get support report: %v", err)
	}
	report := response.Msg.GetReport()

	people := report.GetSupportPeople()
	if len(people) != 2 ||
		people[0].GetPerson() != "Priya" || people[0].GetDuration().AsDuration() != 90*time.Minute || people[0].GetInteractions() != 3 ||
		people[1].GetPerson() != "Sam" || people[1].GetDuration().AsDuration() != 60*time.Minute || people[1].GetInteractions() != 1 {
		t.Fatalf("support people = %+v, want Priya 90m/3 and Sam 60m/1", people)
	}
	modes := report.GetSupportModes()
	if len(modes) != 2 ||
		modes[0].GetName() != "Unblock" || modes[0].GetDuration().AsDuration() != 105*time.Minute || modes[0].GetInteractions() != 3 ||
		modes[1].GetName() != "Review" || modes[1].GetDuration().AsDuration() != 45*time.Minute || modes[1].GetInteractions() != 1 {
		t.Fatalf("support modes = %+v, want Unblock 105m/3 and Review 45m/1", modes)
	}
	if report.GetTotal().AsDuration() != 150*time.Minute || report.GetEntryCount() != 4 {
		t.Fatalf("totals = %v/%d, want the four entries inside the period", report.GetTotal().AsDuration(), report.GetEntryCount())
	}
	if report.GetSupportDuration().AsDuration() != 150*time.Minute || report.GetSupportInteractions() != 4 {
		t.Fatalf("support totals = %v/%d interactions, want the four support entries",
			report.GetSupportDuration().AsDuration(), report.GetSupportInteractions())
	}

	// A period ending before the last entry drops both Sam's time and his row.
	earlier, err := summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-24",
	}, token))
	if err != nil {
		t.Fatalf("get earlier support report: %v", err)
	}
	if people := earlier.Msg.GetReport().GetSupportPeople(); len(people) != 1 ||
		people[0].GetPerson() != "Priya" || people[0].GetDuration().AsDuration() != 90*time.Minute {
		t.Fatalf("earlier support people = %+v, want only Priya", people)
	}

	empty, err := summaryClient(server).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-01-01",
		ToDate:   "2026-01-07",
	}, token))
	if err != nil {
		t.Fatalf("empty support report: %v", err)
	}
	if len(empty.Msg.GetReport().GetSupportPeople()) != 0 || len(empty.Msg.GetReport().GetSupportModes()) != 0 {
		t.Fatalf("empty support report = %+v, want empty rollups", empty.Msg.GetReport())
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
		len(empty.Msg.GetReport().GetSupportPeople()) != 0 ||
		len(empty.Msg.GetReport().GetSupportModes()) != 0 ||
		len(empty.Msg.GetReport().GetWeeks()) != 2 {
		t.Fatalf("empty report = %+v, want zero totals, an empty support rollup and the two weeks the period touches", empty.Msg.GetReport())
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

func TestSummaryServiceSupportRollupsServeGRPCWeb(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	supportID, unblockID := createSupportTaxonomy(t, server, token)

	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    supportID,
		SubcategoryId: unblockID,
		People:        []string{"Priya"},
		Description:   "Late-night unblock",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 19, 23, 30, 0, 0, time.UTC)),
		Duration:      durationpb.New(25 * time.Minute),
	})
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    supportID,
		SubcategoryId: unblockID,
		People:        []string{"Priya"},
		Description:   "Morning unblock",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(35 * time.Minute),
	})
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    supportID,
		SubcategoryId: unblockID,
		People:        []string{"Sam"},
		Description:   "First day of the period",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 19, 8, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(20 * time.Minute),
	})
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    supportID,
		SubcategoryId: unblockID,
		People:        []string{"Sam"},
		Description:   "Day after the period",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 26, 0, 30, 0, 0, time.UTC)),
		Duration:      durationpb.New(40 * time.Minute),
	})

	client := summaryClient(server, connect.WithGRPCWeb())
	response, err := client.GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-20",
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web support report: %v", err)
	}

	people := response.Msg.GetReport().GetSupportPeople()
	if len(people) != 2 ||
		people[0].GetPerson() != "Priya" || people[0].GetDuration().AsDuration() != 60*time.Minute || people[0].GetInteractions() != 2 ||
		people[1].GetPerson() != "Sam" || people[1].GetDuration().AsDuration() != 20*time.Minute || people[1].GetInteractions() != 1 {
		t.Fatalf("gRPC-Web support people = %+v, want Priya 60m/2 and Sam 20m/1", people)
	}
	modes := response.Msg.GetReport().GetSupportModes()
	if len(modes) != 1 || modes[0].GetName() != "Unblock" ||
		modes[0].GetDuration().AsDuration() != 80*time.Minute || modes[0].GetInteractions() != 3 {
		t.Fatalf("gRPC-Web support modes = %+v, want Unblock 80m/3", modes)
	}

	// The day before the period and an empty range both return no rollup rows.
	previousDay, err := client.GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-18",
		ToDate:   "2026-10-18",
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web previous-day support report: %v", err)
	}
	if len(previousDay.Msg.GetReport().GetSupportPeople()) != 0 ||
		len(previousDay.Msg.GetReport().GetSupportModes()) != 0 {
		t.Fatalf("gRPC-Web previous-day support report = %+v, want empty rollups", previousDay.Msg.GetReport())
	}

	empty, err := client.GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-01-01",
		ToDate:   "2026-01-07",
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web empty support report: %v", err)
	}
	if len(empty.Msg.GetReport().GetSupportPeople()) != 0 || len(empty.Msg.GetReport().GetSupportModes()) != 0 {
		t.Fatalf("gRPC-Web empty support report = %+v, want empty rollups", empty.Msg.GetReport())
	}
}

// forEachSummaryProtocol runs the same export assertions over unary Connect and
// gRPC-Web, the two transports the Flutter client can use.
func forEachSummaryProtocol(t *testing.T, run func(t *testing.T, options ...connect.ClientOption)) {
	t.Helper()

	protocols := []struct {
		name    string
		options []connect.ClientOption
	}{
		{name: "connect"},
		{name: "grpc-web", options: []connect.ClientOption{connect.WithGRPCWeb()}},
	}
	for _, protocol := range protocols {
		t.Run(protocol.name, func(t *testing.T) {
			run(t, protocol.options...)
		})
	}
}

func exportFile(t *testing.T, response *wdidv1.BuildExportResponse, name string) string {
	t.Helper()

	for _, file := range response.GetFiles() {
		if file.GetName() == name {
			return file.GetContent()
		}
	}
	t.Fatalf("bundle has no %s; files = %v", name, bundleFileNames(response))
	return ""
}

func bundleFileNames(response *wdidv1.BuildExportResponse) []string {
	names := make([]string, 0, len(response.GetFiles()))
	for _, file := range response.GetFiles() {
		names = append(names, file.GetName())
	}
	return names
}

func readExportCSV(t *testing.T, content string) [][]string {
	t.Helper()

	rows, err := csv.NewReader(strings.NewReader(content)).ReadAll()
	if err != nil {
		t.Fatalf("parse CSV: %v", err)
	}
	return rows
}

// buildSummaryExportFixture seeds one initiative and one support entry, a day
// note and a completed milestone, then returns the project id.
func buildSummaryExportFixture(t *testing.T, server *httptest.Server, database *store.Store, token string) (categoryID, projectID string) {
	t.Helper()

	initiativeID, projectID := createEntryTaxonomy(t, server, token)
	categoryID = initiativeID
	supportID, unblockID := createSupportTaxonomy(t, server, token)

	if _, err := categoryClient(server).UpdateSubcategory(context.Background(), withBearer(&wdidv1.UpdateSubcategoryRequest{
		Id:            projectID,
		Name:          "Billing migration",
		Status:        wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
		Progress:      64,
		TargetOutcome: "Invoice generation under 5 minutes",
	}, token)); err != nil {
		t.Fatalf("update project: %v", err)
	}

	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    initiativeID,
		SubcategoryId: projectID,
		Description:   "Backfill script",
		Outcome:       "Shipped the backfill",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(90 * time.Minute),
	})
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    supportID,
		SubcategoryId: unblockID,
		Description:   "event bus design",
		Outcome:       "3 risks identified before implementation",
		People:        []string{"Priya", "Sam"},
		Team:          "Payments",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 19, 11, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(30 * time.Minute),
	})

	userID := currentUserID(t, server, token)
	if err := database.SaveNote(domain.Note{
		ID:        "note-day",
		UserID:    userID,
		Date:      "2026-10-19",
		Text:      "Shipped the backfill",
		CreatedAt: time.Date(2026, 10, 19, 12, 0, 0, 0, time.UTC),
	}); err != nil {
		t.Fatalf("save note: %v", err)
	}
	if err := database.SaveMilestone(domain.Milestone{
		ID:            "milestone-backfill",
		UserID:        userID,
		SubcategoryID: projectID,
		Title:         "Backfill complete",
		DueDate:       "2026-10-30",
		Done:          true,
		CreatedAt:     time.Date(2026, 10, 19, 8, 0, 0, 0, time.UTC),
	}); err != nil {
		t.Fatalf("save milestone: %v", err)
	}
	return categoryID, projectID
}

// TestSummaryServiceBuildExportBundle covers the four files, the fixed
// summary.md contract and the flat CSV sheets over both transports.
func TestSummaryServiceBuildExportBundle(t *testing.T) {
	forEachSummaryProtocol(t, func(t *testing.T, options ...connect.ClientOption) {
		server, database := newDomainServer(t)
		token := bootstrapToken(t, server)
		buildSummaryExportFixture(t, server, database, token)

		response, err := summaryClient(server, options...).BuildExport(
			context.Background(),
			withBearer(&wdidv1.BuildExportRequest{
				FromDate: "2026-10-19",
				ToDate:   "2026-10-25",
			}, token),
		)
		if err != nil {
			t.Fatalf("build export: %v", err)
		}
		bundle := response.Msg

		if bundle.GetDirectory() != "wdid-export-2026-10-19_2026-10-25" {
			t.Fatalf("directory = %q, want the ISO period directory", bundle.GetDirectory())
		}
		names := bundleFileNames(bundle)
		want := []string{"summary.md", "data.json", "entries.csv", "support.csv"}
		if len(names) != len(want) {
			t.Fatalf("files = %v, want %v", names, want)
		}
		for index, name := range want {
			if names[index] != name {
				t.Fatalf("files = %v, want %v in plan order", names, want)
			}
		}

		summary := exportFile(t, bundle, "summary.md")
		for _, heading := range []string{
			"# wdid work report — 2026-10-19 to 2026-10-25",
			"## Context",
			"Period: 7 days · 2h 00m logged · 1 projects · 1 support interactions",
			"## Time allocation",
			"| Category | Hours | Share |",
			"| Billing migration | 1h 30m | 75% |",
			"## Initiative progress",
			"### Billing migration — Active, 64%",
			"- Target outcome: Invoice generation under 5 minutes",
			"- This period: 1h 30m, 1 entries",
			"- Milestones: 1 of 1 complete",
			"- Key outcomes:\n  - Shipped the backfill",
			"## Support and collaboration",
			// Both named people receive the entry's full minutes as a section
			// and the same detail, while the period context counts the entry
			// once.
			"### Priya (Payments) — 0h 30m, 1 interactions",
			"### Sam (Payments) — 0h 30m, 1 interactions",
			"- Unblock: event bus design — 3 risks identified before implementation",
			"## Weekly rhythm",
			"| 2026-10-19 | 2h 00m | Focus |",
			"## Notes and context",
			"- 2026-10-19: Shipped the backfill",
			"## Source data",
			"Structured data: data.json · Flat entries: entries.csv · Support: support.csv",
		} {
			if !strings.Contains(summary, heading) {
				t.Fatalf("summary.md is missing %q:\n%s", heading, summary)
			}
		}

		entriesRows := readExportCSV(t, exportFile(t, bundle, "entries.csv"))
		if len(entriesRows) != 3 {
			t.Fatalf("entries.csv rows = %d, want a header and two entries:\n%s", len(entriesRows), exportFile(t, bundle, "entries.csv"))
		}
		entriesHeader := strings.Join(entriesRows[0], ",")
		for _, column := range []string{"date", "minutes", "category", "subcategory", "outcome", "people"} {
			if !strings.Contains(entriesHeader, column) {
				t.Fatalf("entries.csv header = %q, want %s", entriesHeader, column)
			}
		}
		if joined := strings.Join(entriesRows[1], ","); !strings.Contains(joined, "Billing migration") || !strings.Contains(joined, "Shipped the backfill") {
			t.Fatalf("entries.csv initiative row = %q", joined)
		}
		// The support entry carries both names joined, still as one row.
		supportRow := strings.Join(entriesRows[2], ",")
		if !strings.Contains(supportRow, "Priya;Sam") || !strings.Contains(supportRow, "Unblock") {
			t.Fatalf("entries.csv support row = %q, want both people joined", supportRow)
		}

		supportRows := readExportCSV(t, exportFile(t, bundle, "support.csv"))
		if len(supportRows) != 2 {
			t.Fatalf("support.csv rows = %d, want a header and one support entry:\n%s", len(supportRows), exportFile(t, bundle, "support.csv"))
		}
		if header := strings.Join(supportRows[0], ","); !strings.Contains(header, "people") || !strings.Contains(header, "mode") {
			t.Fatalf("support.csv header = %q, want people and mode columns", header)
		}
		// One row per entry, every name joined by a semicolon.
		if row := strings.Join(supportRows[1], ","); !strings.Contains(row, "Priya;Sam") || !strings.Contains(row, "Unblock") {
			t.Fatalf("support.csv row = %q, want both people joined and the mode", row)
		}

		var data map[string]any
		if err := json.Unmarshal([]byte(exportFile(t, bundle, "data.json")), &data); err != nil {
			t.Fatalf("parse data.json: %v", err)
		}
		for _, key := range []string{
			"schemaVersion", "generatedAt", "period", "settingsSummary", "categories",
			"subcategories", "entries", "support", "checkIns", "notes", "totals",
		} {
			if _, ok := data[key]; !ok {
				t.Fatalf("data.json is missing %q: %v", key, data)
			}
		}
		if data["schemaVersion"].(float64) != 2 {
			t.Fatalf("schemaVersion = %v, want 2", data["schemaVersion"])
		}
		for key, want := range map[string]int{
			"entries":       2,
			"support":       1,
			"notes":         1,
			"categories":    2,
			"subcategories": 2,
		} {
			if got := len(data[key].([]any)); got != want {
				t.Fatalf("data.json %s = %d rows, want %d", key, got, want)
			}
		}
		totals := data["totals"].(map[string]any)
		if totals["minutes"].(float64) != 120 || totals["entryCount"].(float64) != 2 ||
			totals["supportMinutes"].(float64) != 30 ||
			totals["supportInteractions"].(float64) != 1 || totals["projects"].(float64) != 1 {
			t.Fatalf("data.json totals = %v, want 120 minutes, 30 support minutes and one support entry", totals)
		}
		// The structured rows keep every name as a list, not a joined string.
		supportRowsData := data["support"].([]any)
		people := supportRowsData[0].(map[string]any)["people"].([]any)
		if len(people) != 2 || people[0] != "Priya" || people[1] != "Sam" {
			t.Fatalf("data.json support people = %v, want Priya and Sam", people)
		}
	})
}

// TestSummaryServiceBuildExportScopesToTheSelectedPeriodOrCheckIn proves a
// check-in's stored period wins over request dates and both scopes exclude
// entries outside the boundary.
func TestSummaryServiceBuildExportScopesToTheSelectedPeriodOrCheckIn(t *testing.T) {
	forEachSummaryProtocol(t, func(t *testing.T, options ...connect.ClientOption) {
		server, database := newDomainServer(t)
		token := bootstrapToken(t, server)
		categoryID, projectID := buildSummaryExportFixture(t, server, database, token)

		// A second entry outside the check-in period.
		createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
			CategoryId:    categoryID,
			SubcategoryId: projectID,
			Description:   "Later work",
			StartedAt:     timestamppb.New(time.Date(2026, 10, 26, 9, 0, 0, 0, time.UTC)),
			Duration:      durationpb.New(60 * time.Minute),
		})

		created, err := checkInClient(server, options...).CreateCheckIn(
			context.Background(),
			withBearer(&wdidv1.CreateCheckInRequest{
				Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
				PeriodStart: "2026-10-19",
				PeriodEnd:   "2026-10-25",
				FocusNotes:  "Keep the migration on track",
			}, token),
		)
		if err != nil {
			t.Fatalf("create check-in: %v", err)
		}
		checkInID := created.Msg.GetCheckIn().GetId()

		// Request dates deliberately point elsewhere; the check-in period wins.
		response, err := summaryClient(server, options...).BuildExport(
			context.Background(),
			withBearer(&wdidv1.BuildExportRequest{
				CheckInId: checkInID,
				FromDate:  "2026-10-26",
				ToDate:    "2026-10-26",
			}, token),
		)
		if err != nil {
			t.Fatalf("build check-in export: %v", err)
		}
		if response.Msg.GetDirectory() != "wdid-export-2026-10-19_2026-10-25" {
			t.Fatalf("check-in directory = %q, want the stored period", response.Msg.GetDirectory())
		}
		rows := readExportCSV(t, exportFile(t, response.Msg, "entries.csv"))
		if len(rows) != 3 {
			t.Fatalf("check-in entries.csv rows = %d, want the two entries inside its period:\n%v", len(rows), rows)
		}
		summary := exportFile(t, response.Msg, "summary.md")
		if !strings.Contains(summary, "- Focus notes: Keep the migration on track") {
			t.Fatalf("check-in summary.md = %q, want the focus notes", summary)
		}
		if strings.Contains(summary, "Later work") {
			t.Fatalf("check-in summary.md leaked an entry outside the period:\n%s", summary)
		}

		// A bare period export honours the requested dates instead.
		period, err := summaryClient(server, options...).BuildExport(
			context.Background(),
			withBearer(&wdidv1.BuildExportRequest{
				FromDate: "2026-10-26",
				ToDate:   "2026-10-26",
			}, token),
		)
		if err != nil {
			t.Fatalf("build period export: %v", err)
		}
		if period.Msg.GetDirectory() != "wdid-export-2026-10-26_2026-10-26" {
			t.Fatalf("period directory = %q", period.Msg.GetDirectory())
		}
		if rows := readExportCSV(t, exportFile(t, period.Msg, "entries.csv")); len(rows) != 2 {
			t.Fatalf("period entries.csv rows = %d, want only the 26 October entry:\n%v", len(rows), rows)
		}
	})
}

// TestSummaryServiceBuildExportCarriesAdditionalContext proves the scoped
// check-in's context reaches both export files and that a custom prompt
// template is recorded in the settings summary without the API key.
func TestSummaryServiceBuildExportCarriesAdditionalContext(t *testing.T) {
	forEachSummaryProtocol(t, func(t *testing.T, options ...connect.ClientOption) {
		server, database := newDomainServer(t)
		token := bootstrapToken(t, server)
		buildSummaryExportFixture(t, server, database, token)
		userID := currentUserID(t, server, token)

		contextText := "The outage postmortem is at https://internal.example/postmortem.\n\nWe added a canary gate."
		created := time.Date(2026, 10, 20, 8, 0, 0, 0, time.UTC)
		checkIn := domain.CheckIn{
			ID:                "checkin-context",
			UserID:            userID,
			Kind:              domain.CheckInKindManager,
			State:             domain.CheckInStateGenerated,
			PeriodStart:       "2026-10-19",
			PeriodEnd:         "2026-10-25",
			FocusNotes:        "Land the migration",
			SummaryMarkdown:   "# Summary",
			AdditionalContext: contextText,
			GenerationPrompt:  "[user]\nInstruction",
			CreatedAt:         created,
			UpdatedAt:         created,
		}
		if err := database.SaveCheckIn(checkIn); err != nil {
			t.Fatalf("save check-in: %v", err)
		}
		settings := domain.DefaultSettings(userID)
		settings.PromptTemplates = map[domain.PromptVariant]string{
			domain.PromptVariantManagerOneOnOne: "Write a blunt summary.",
		}
		settings.AIAPIKey = "sk-export-secret"
		if err := database.SaveSettings(settings); err != nil {
			t.Fatalf("save settings: %v", err)
		}

		response, err := summaryClient(server, options...).BuildExport(context.Background(), withBearer(&wdidv1.BuildExportRequest{
			CheckInId: checkIn.ID,
		}, token))
		if err != nil {
			t.Fatalf("build export: %v", err)
		}
		if summary := exportFile(t, response.Msg, "summary.md"); !strings.Contains(summary, "Additional context:\n\n"+contextText) {
			t.Fatalf("summary.md is missing the check-in context:\n%s", summary)
		}

		var data map[string]any
		if err := json.Unmarshal([]byte(exportFile(t, response.Msg, "data.json")), &data); err != nil {
			t.Fatalf("parse data.json: %v", err)
		}
		exportedCheckIn := data["checkIns"].([]any)[0].(map[string]any)
		if exportedCheckIn["additionalContext"] != contextText {
			t.Fatalf("data.json additionalContext = %v", exportedCheckIn["additionalContext"])
		}
		if exportedCheckIn["generationPrompt"] != "[user]\nInstruction" {
			t.Fatalf("data.json generationPrompt = %v", exportedCheckIn["generationPrompt"])
		}
		exportedSettings := data["settingsSummary"].(map[string]any)
		templates := exportedSettings["promptTemplates"].(map[string]any)
		if templates[string(domain.PromptVariantManagerOneOnOne)] != "Write a blunt summary." {
			t.Fatalf("data.json promptTemplates = %v", templates)
		}
		raw := exportFile(t, response.Msg, "data.json")
		if strings.Contains(raw, "sk-export-secret") || strings.Contains(raw, "aiApiKey") {
			t.Fatalf("data.json leaked the API key:\n%s", raw)
		}
	})
}

// TestSummaryServiceBuildPromptAppendsSummary proves the copy-prompt text is
// the versioned instruction followed by exactly the bundle's summary.md, and
// that the check-in kind and audience select the variant.
func TestSummaryServiceBuildPromptAppendsSummary(t *testing.T) {
	forEachSummaryProtocol(t, func(t *testing.T, options ...connect.ClientOption) {
		server, database := newDomainServer(t)
		token := bootstrapToken(t, server)
		buildSummaryExportFixture(t, server, database, token)
		client := summaryClient(server, options...)
		request := &wdidv1.BuildPromptRequest{FromDate: "2026-10-19", ToDate: "2026-10-25"}

		bundle, err := client.BuildExport(context.Background(), withBearer(&wdidv1.BuildExportRequest{
			FromDate: request.GetFromDate(),
			ToDate:   request.GetToDate(),
		}, token))
		if err != nil {
			t.Fatalf("build export: %v", err)
		}
		summary := strings.TrimSpace(exportFile(t, bundle.Msg, "summary.md"))

		prompt, err := client.BuildPrompt(context.Background(), withBearer(request, token))
		if err != nil {
			t.Fatalf("build prompt: %v", err)
		}
		if prompt.Msg.GetPromptVersion() != domain.PromptVersion {
			t.Fatalf("prompt version = %q, want %q", prompt.Msg.GetPromptVersion(), domain.PromptVersion)
		}
		if prompt.Msg.GetVariant() != wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE {
			t.Fatalf("period variant = %v, want the manager 1:1 default", prompt.Msg.GetVariant())
		}
		if !strings.Contains(prompt.Msg.GetPrompt(), "1:1") || !strings.HasSuffix(prompt.Msg.GetPrompt(), summary) {
			t.Fatalf("prompt = %q, want the instruction followed by summary.md", prompt.Msg.GetPrompt())
		}

		// The check-in audience selects the performance-review template.
		created, err := checkInClient(server, options...).CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
			Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
			PeriodStart: "2026-10-19",
			PeriodEnd:   "2026-10-25",
			Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
		}, token))
		if err != nil {
			t.Fatalf("create check-in: %v", err)
		}
		checkInPrompt, err := client.BuildPrompt(context.Background(), withBearer(&wdidv1.BuildPromptRequest{
			CheckInId: created.Msg.GetCheckIn().GetId(),
		}, token))
		if err != nil {
			t.Fatalf("build check-in prompt: %v", err)
		}
		if checkInPrompt.Msg.GetVariant() != wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW {
			t.Fatalf("check-in variant = %v, want performance review", checkInPrompt.Msg.GetVariant())
		}
		if !strings.Contains(checkInPrompt.Msg.GetPrompt(), "formal performance review") ||
			!strings.HasSuffix(checkInPrompt.Msg.GetPrompt(), summary) {
			t.Fatalf("performance-review prompt = %q", checkInPrompt.Msg.GetPrompt())
		}

		// A personal review always uses the personal template.
		personal, err := checkInClient(server, options...).CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
			Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL,
			PeriodStart: "2026-10-19",
			PeriodEnd:   "2026-10-25",
		}, token))
		if err != nil {
			t.Fatalf("create personal review: %v", err)
		}
		personalPrompt, err := client.BuildPrompt(context.Background(), withBearer(&wdidv1.BuildPromptRequest{
			CheckInId: personal.Msg.GetCheckIn().GetId(),
		}, token))
		if err != nil {
			t.Fatalf("build personal prompt: %v", err)
		}
		if personalPrompt.Msg.GetVariant() != wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW {
			t.Fatalf("personal variant = %v", personalPrompt.Msg.GetVariant())
		}

		// An explicit variant override applies to a bare period.
		override, err := client.BuildPrompt(context.Background(), withBearer(&wdidv1.BuildPromptRequest{
			FromDate: "2026-10-19",
			ToDate:   "2026-10-25",
			Variant:  wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW,
		}, token))
		if err != nil {
			t.Fatalf("override prompt: %v", err)
		}
		if override.Msg.GetVariant() != wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW {
			t.Fatalf("override variant = %v, want personal review", override.Msg.GetVariant())
		}

		_, err = client.BuildPrompt(context.Background(), withBearer(&wdidv1.BuildPromptRequest{
			FromDate: "2026-10-19",
			ToDate:   "2026-10-25",
			Variant:  wdidv1.CheckInPromptVariant(99),
		}, token))
		if connect.CodeOf(err) != connect.CodeInvalidArgument {
			t.Fatalf("unknown variant code = %v, want invalid argument", connect.CodeOf(err))
		}
		if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "variant" {
			t.Fatalf("field violations = %v, want variant", fields)
		}
	})
}

// TestSummaryServiceExportNeverWritesIntoTheDatabaseDirectory proves the
// bundle is generated in memory: the directory holding the database gains no
// files when an export is built.
func TestSummaryServiceExportNeverWritesIntoTheDatabaseDirectory(t *testing.T) {
	cfg := testConfig(t)
	server, database := newDomainServerWithConfig(t, cfg)
	token := bootstrapToken(t, server)
	buildSummaryExportFixture(t, server, database, token)

	directory := filepath.Dir(cfg.DBPath)
	before := exportDirectoryEntries(t, directory)

	if _, err := summaryClient(server).BuildExport(context.Background(), withBearer(&wdidv1.BuildExportRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-25",
	}, token)); err != nil {
		t.Fatalf("build export: %v", err)
	}

	after := exportDirectoryEntries(t, directory)
	if len(after) != len(before) {
		t.Fatalf("database directory files = %v, want unchanged %v", after, before)
	}
	for name := range after {
		if _, ok := before[name]; !ok {
			t.Fatalf("export wrote %q into the database directory", name)
		}
		if strings.HasPrefix(name, "wdid-export") {
			t.Fatalf("database directory holds an export directory %q", name)
		}
	}
}

func exportDirectoryEntries(t *testing.T, directory string) map[string]struct{} {
	t.Helper()

	entries, err := os.ReadDir(directory)
	if err != nil {
		t.Fatalf("read database directory: %v", err)
	}
	result := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		result[entry.Name()] = struct{}{}
	}
	return result
}

// --- AI summary generation -------------------------------------------------

// fakeAIProvider records every request and replays a scripted stream. Tests
// never reach a real provider.
type fakeAIProvider struct {
	requests  []ai.Request
	deltas    []string
	response  ai.Response
	err       error
	failAfter int

	// started and release let a test hold one call inside the provider, so a
	// second concurrent write can be proved to be rejected.
	mu          sync.Mutex
	started     chan struct{}
	release     chan struct{}
	startedOnce sync.Once
}

func (p *fakeAIProvider) Stream(_ context.Context, request ai.Request, onDelta func(string) error) (ai.Response, error) {
	p.mu.Lock()
	p.requests = append(p.requests, request)
	p.mu.Unlock()

	if p.started != nil {
		p.startedOnce.Do(func() { close(p.started) })
	}
	if p.release != nil {
		<-p.release
	}

	for index, delta := range p.deltas {
		if p.err != nil && index >= p.failAfter {
			return ai.Response{}, p.err
		}
		if err := onDelta(delta); err != nil {
			return ai.Response{}, err
		}
	}
	if p.err != nil {
		return ai.Response{}, p.err
	}
	return p.response, nil
}

func (p *fakeAIProvider) lastRequest() ai.Request {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.requests) == 0 {
		return ai.Request{}
	}
	return p.requests[len(p.requests)-1]
}

func (p *fakeAIProvider) requestCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.requests)
}

// lastPrompt joins the turns of the last provider request, which is how the
// streaming assertions read the generate transcript.
func (p *fakeAIProvider) lastPrompt() string {
	request := p.lastRequest()
	contents := make([]string, 0, len(request.Messages))
	for _, message := range request.Messages {
		contents = append(contents, message.Content)
	}
	return strings.Join(contents, "\n\n")
}

type generationResult struct {
	text   string
	final  *wdidv1.CheckIn
	deltas int
}

func collectGeneration(t *testing.T, server *httptest.Server, token, checkInID string, overwrite bool, options ...connect.ClientOption) (generationResult, error) {
	t.Helper()

	stream, err := summaryClient(server, options...).GenerateSummary(
		context.Background(),
		withBearer(&wdidv1.GenerateSummaryRequest{
			CheckInId:            checkInID,
			OverwriteManualEdits: overwrite,
		}, token),
	)
	if err != nil {
		return generationResult{}, err
	}
	defer stream.Close()

	result := generationResult{}
	for stream.Receive() {
		delta := stream.Msg()
		result.text += delta.GetText()
		result.deltas++
		if delta.GetCheckIn() != nil {
			result.final = delta.GetCheckIn()
		}
	}
	return result, stream.Err()
}

func createSummaryCheckIn(t *testing.T, server *httptest.Server, token string, kind wdidv1.CheckInKind, audience wdidv1.CheckInAudience) string {
	t.Helper()

	response, err := checkInClient(server).CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
		Kind:        kind,
		PeriodStart: "2026-10-19",
		PeriodEnd:   "2026-10-25",
		Audience:    audience,
		FocusNotes:  "Ship the backfill",
	}, token))
	if err != nil {
		t.Fatalf("create check-in: %v", err)
	}
	return response.Msg.GetCheckIn().GetId()
}

func updateAISettings(t *testing.T, server *httptest.Server, token, baseURL, model string, redact bool) {
	t.Helper()

	if _, err := settingsClient(server).UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: &wdidv1.Settings{
			Timezone:             "UTC",
			WeekStart:            1,
			DailyTarget:          minutes(450),
			ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_OFF,
			LongTimerThreshold:   minutes(240),
			DefaultEntryDuration: minutes(30),
			BackupInterval:       minutes(360),
			BackupRetention:      30,
			AiBaseUrl:            baseURL,
			AiModel:              model,
			AiRedact:             redact,
			Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM,
			Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMFORTABLE,
		},
	}, token)); err != nil {
		t.Fatalf("update AI settings: %v", err)
	}
}

func saveManualSummary(t *testing.T, server *httptest.Server, token, checkInID, summary string) {
	t.Helper()

	checkIn, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get check-in: %v", err)
	}
	if _, err := checkInClient(server).UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
		Id:              checkInID,
		PeriodStart:     checkIn.Msg.GetCheckIn().GetPeriodStart(),
		PeriodEnd:       checkIn.Msg.GetCheckIn().GetPeriodEnd(),
		Audience:        checkIn.Msg.GetCheckIn().GetAudience(),
		FocusNotes:      checkIn.Msg.GetCheckIn().GetFocusNotes(),
		SummaryMarkdown: summary,
		SummarySource:   wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL,
	}, token)); err != nil {
		t.Fatalf("save summary: %v", err)
	}
}

func TestSummaryServiceGenerateSummaryStreamsAndPersistsMetadata(t *testing.T) {
	forEachSummaryProtocol(t, func(t *testing.T, options ...connect.ClientOption) {
		provider := &fakeAIProvider{
			deltas:   []string{"## Highlights\n", "- Shipped the backfill"},
			response: ai.Response{Model: "provider-model"},
		}
		server, database := newDomainServerWithAI(t, provider)
		token := bootstrapToken(t, server)
		setAIKey(t, server, token, "sk-test-key")
		buildSummaryExportFixture(t, server, database, token)
		checkInID := createSummaryCheckIn(t, server, token,
			wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
			wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		)

		result, err := collectGeneration(t, server, token, checkInID, false, options...)
		if err != nil {
			t.Fatalf("generate summary: %v", err)
		}

		if result.text != "## Highlights\n- Shipped the backfill" {
			t.Fatalf("streamed text = %q", result.text)
		}
		if result.deltas != 3 || result.final == nil {
			t.Fatalf("stream = %d deltas with final %v, want two text deltas and a final check-in", result.deltas, result.final)
		}
		if result.final.GetSummaryModel() != "provider-model" ||
			result.final.GetPromptVersion() != domain.PromptVersion ||
			result.final.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_GENERATED {
			t.Fatalf("final check-in = %+v, want generated with model and prompt version", result.final)
		}

		request := provider.lastRequest()
		if request.APIKey != "sk-test-key" {
			t.Fatalf("provider key = %q, want the in-memory key", request.APIKey)
		}
		if request.BaseURL == "" || request.Model == "" {
			t.Fatalf("provider request = %+v, want a configured base URL and model", request)
		}
		if prompt := provider.lastPrompt(); !strings.Contains(prompt, "1:1") ||
			!strings.Contains(prompt, "Billing migration") {
			t.Fatalf("prompt = %q, want the 1:1 instruction and period data", prompt)
		}

		stored, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
		if err != nil {
			t.Fatalf("get check-in: %v", err)
		}
		if stored.Msg.GetCheckIn().GetSummaryMarkdown() != "## Highlights\n- Shipped the backfill" ||
			stored.Msg.GetCheckIn().GetSummaryModel() != "provider-model" ||
			stored.Msg.GetCheckIn().GetPromptVersion() != domain.PromptVersion {
			t.Fatalf("stored check-in = %+v, want the generated summary and metadata", stored.Msg.GetCheckIn())
		}
	})
}

func TestSummaryServiceGenerateSummarySelectsThePromptVariant(t *testing.T) {
	provider := &fakeAIProvider{deltas: []string{"summary"}, response: ai.Response{Model: "m"}}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	buildSummaryExportFixture(t, server, database, token)

	performanceID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
	)
	if _, err := collectGeneration(t, server, token, performanceID, false); err != nil {
		t.Fatalf("generate performance summary: %v", err)
	}
	if prompt := provider.lastPrompt(); !strings.Contains(prompt, "formal performance review") {
		t.Fatalf("performance prompt = %q, want the performance-review instruction", prompt)
	}

	personalID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_UNSPECIFIED,
	)
	if _, err := collectGeneration(t, server, token, personalID, false); err != nil {
		t.Fatalf("generate personal summary: %v", err)
	}
	if prompt := provider.lastPrompt(); !strings.Contains(prompt, "your own working period") {
		t.Fatalf("personal prompt = %q, want the personal-review instruction", prompt)
	}
}

func TestSummaryServiceGenerateSummaryRedactionStripsURLsAndNotes(t *testing.T) {
	provider := &fakeAIProvider{deltas: []string{"summary"}, response: ai.Response{Model: "m"}}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	categoryID, projectID := buildSummaryExportFixture(t, server, database, token)
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    categoryID,
		SubcategoryId: projectID,
		Description:   "Backfill script https://internal.example/runbook",
		Outcome:       "Shipped https://internal.example/runbook",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(30 * time.Minute),
	})
	userID := currentUserID(t, server, token)
	if err := database.SaveNote(domain.Note{
		ID:        "note-private",
		UserID:    userID,
		Date:      "2026-10-20",
		Text:      "Private note at https://internal.example/notes",
		CreatedAt: time.Date(2026, 10, 20, 10, 0, 0, 0, time.UTC),
	}); err != nil {
		t.Fatalf("save note: %v", err)
	}
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	// Additional context is deliberate user input and is never redacted.
	updateAdditionalContext(t, server, token, checkInID, "Off-ledger detail https://context.example/detail")

	// Without redaction the prompt carries the notes and URLs.
	if _, err := collectGeneration(t, server, token, checkInID, false); err != nil {
		t.Fatalf("generate unredacted summary: %v", err)
	}
	unredacted := provider.lastPrompt()
	for _, expected := range []string{"https://internal.example/runbook", "Private note", "Ship the backfill"} {
		if !strings.Contains(unredacted, expected) {
			t.Fatalf("unredacted prompt is missing %q:\n%s", expected, unredacted)
		}
	}

	updateAISettings(t, server, token, "https://provider.example/v1", "model-name", true)
	if _, err := collectGeneration(t, server, token, checkInID, false); err != nil {
		t.Fatalf("generate redacted summary: %v", err)
	}
	redacted := provider.lastPrompt()
	for _, forbidden := range []string{"https://internal.example", "Private note", "Ship the backfill"} {
		if strings.Contains(redacted, forbidden) {
			t.Fatalf("redacted prompt contains %q:\n%s", forbidden, redacted)
		}
	}
	if !strings.Contains(redacted, "[link removed]") {
		t.Fatalf("redacted prompt = %q, want a visible redaction marker", redacted)
	}

	// The stored snapshot is the transcript the model saw, so it records the
	// redacted text while the deliberately supplied context survives.
	stored, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get redacted check-in: %v", err)
	}
	snapshot := stored.Msg.GetCheckIn().GetGenerationPrompt()
	for _, forbidden := range []string{"https://internal.example", "Private note", "Ship the backfill"} {
		if strings.Contains(snapshot, forbidden) {
			t.Fatalf("snapshot contains the redacted %q:\n%s", forbidden, snapshot)
		}
	}
	if !strings.Contains(snapshot, "[link removed]") {
		t.Fatalf("snapshot = %q, want the redaction marker", snapshot)
	}
	if !strings.Contains(snapshot, "https://context.example/detail") {
		t.Fatalf("snapshot = %q, want the deliberately supplied additional context kept", snapshot)
	}
}

func TestSummaryServiceGenerateSummaryFailureIsNonDestructiveAndRetryable(t *testing.T) {
	provider := &fakeAIProvider{
		deltas:    []string{"## Partial"},
		err:       errors.New("provider stream failed"),
		failAfter: 1,
	}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	buildSummaryExportFixture(t, server, database, token)
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	saveManualSummary(t, server, token, checkInID, "## Existing\n- My own words")

	result, err := collectGeneration(t, server, token, checkInID, true)
	if err == nil {
		t.Fatal("expected the stream to fail")
	}
	if connect.CodeOf(err) != connect.CodeUnavailable {
		t.Fatalf("code = %v, want unavailable", connect.CodeOf(err))
	}
	if result.text != "## Partial" {
		t.Fatalf("partial text = %q", result.text)
	}

	stored, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get check-in after failure: %v", err)
	}
	if stored.Msg.GetCheckIn().GetSummaryMarkdown() != "## Existing\n- My own words" {
		t.Fatalf("summary after failure = %q, want the existing text untouched", stored.Msg.GetCheckIn().GetSummaryMarkdown())
	}
	if stored.Msg.GetCheckIn().GetSummaryModel() != "" || stored.Msg.GetCheckIn().GetPromptVersion() != "" {
		t.Fatalf("metadata after failure = %q/%q, want none",
			stored.Msg.GetCheckIn().GetSummaryModel(), stored.Msg.GetCheckIn().GetPromptVersion())
	}

	// A retry succeeds and persists only the complete response.
	provider.err = nil
	provider.deltas = []string{"## New\n", "- Generated"}
	provider.response = ai.Response{Model: "retry-model"}
	if _, err := collectGeneration(t, server, token, checkInID, true); err != nil {
		t.Fatalf("retry generation: %v", err)
	}
	retried, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get retried check-in: %v", err)
	}
	if retried.Msg.GetCheckIn().GetSummaryMarkdown() != "## New\n- Generated" ||
		retried.Msg.GetCheckIn().GetSummaryModel() != "retry-model" {
		t.Fatalf("retried check-in = %+v, want the complete retry", retried.Msg.GetCheckIn())
	}
}

func TestSummaryServiceGenerateSummaryRequiresConfirmationForManualEdits(t *testing.T) {
	provider := &fakeAIProvider{deltas: []string{"generated"}, response: ai.Response{Model: "m"}}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	buildSummaryExportFixture(t, server, database, token)
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	saveManualSummary(t, server, token, checkInID, "## Manual\n- Own words")

	if _, err := collectGeneration(t, server, token, checkInID, false); err == nil ||
		connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("unconfirmed generation error = %v, want failed precondition", err)
	}
	if len(provider.requests) != 0 {
		t.Fatalf("provider calls = %d, want none before confirmation", len(provider.requests))
	}

	if _, err := collectGeneration(t, server, token, checkInID, true); err != nil {
		t.Fatalf("confirmed generation: %v", err)
	}
	if len(provider.requests) != 1 {
		t.Fatalf("provider calls = %d, want one after confirmation", len(provider.requests))
	}
}

func TestSummaryServiceGenerateSummaryRequiresAPerUserKey(t *testing.T) {
	provider := &fakeAIProvider{deltas: []string{"generated"}, response: ai.Response{Model: "m"}}
	server, _ := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)

	_, err := collectGeneration(t, server, token, checkInID, false)
	if connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("missing key code = %v, want failed precondition", connect.CodeOf(err))
	}
	if !strings.Contains(err.Error(), "Settings") || !strings.Contains(err.Error(), "key") {
		t.Fatalf("missing key error = %v, want a prompt to add a key in Settings", err)
	}
	if len(provider.requests) != 0 {
		t.Fatalf("provider calls = %d, want none without a key", len(provider.requests))
	}
}

func TestSummaryServiceGenerateSummaryUsesTheCallersOwnKey(t *testing.T) {
	provider := &fakeAIProvider{deltas: []string{"generated"}, response: ai.Response{Model: "m"}}
	server, database := newDomainServerWithAI(t, provider)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "summary-member@example.com")
	setAIKey(t, server, memberToken, "sk-ant-member")

	memberCheckIn := createSummaryCheckIn(t, server, memberToken,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	if _, err := collectGeneration(t, server, memberToken, memberCheckIn, false); err != nil {
		t.Fatalf("generate with the member's own key: %v", err)
	}
	if key := provider.lastRequest().APIKey; key != "sk-ant-member" {
		t.Fatalf("provider key = %q, want the member's own key", key)
	}

	// The administrator has no key, so their generation is disabled even
	// though the member's key is stored.
	adminCheckIn := createSummaryCheckIn(t, server, adminToken,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	_, err := collectGeneration(t, server, adminToken, adminCheckIn, false)
	if connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("admin missing key code = %v, want failed precondition", connect.CodeOf(err))
	}
}

func TestSummaryServiceGetPromptTemplate(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := summaryClient(server)

	cases := []struct {
		variant wdidv1.CheckInPromptVariant
		want    string
	}{
		{wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_UNSPECIFIED, "1:1"},
		{wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE, "1:1"},
		{wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW, "formal performance review"},
		{wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW, "your own working period"},
	}
	for _, testCase := range cases {
		response, err := client.GetPromptTemplate(context.Background(), withBearer(&wdidv1.GetPromptTemplateRequest{
			Variant: testCase.variant,
		}, token))
		if err != nil {
			t.Fatalf("get prompt template for %v: %v", testCase.variant, err)
		}
		if !strings.Contains(response.Msg.GetTemplate(), testCase.want) {
			t.Fatalf("template for %v = %q, want %q", testCase.variant, response.Msg.GetTemplate(), testCase.want)
		}
		if response.Msg.GetPromptVersion() != domain.PromptVersion {
			t.Fatalf("prompt version = %q, want %q", response.Msg.GetPromptVersion(), domain.PromptVersion)
		}
	}

	_, err := client.GetPromptTemplate(context.Background(), withBearer(&wdidv1.GetPromptTemplateRequest{
		Variant: wdidv1.CheckInPromptVariant(99),
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("unknown variant code = %v, want invalid argument", connect.CodeOf(err))
	}
}

// TestSummaryServiceExportNeverContainsTheAIKey proves the stored per-user key
// is absent from every generated artifact the caller can download.
func TestSummaryServiceExportNeverContainsTheAIKey(t *testing.T) {
	const apiKey = "sk-very-secret-key"
	server, database := newDomainServerWithAI(t, &fakeAIProvider{})
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, apiKey)
	buildSummaryExportFixture(t, server, database, token)

	response, err := summaryClient(server).BuildExport(context.Background(), withBearer(&wdidv1.BuildExportRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-25",
	}, token))
	if err != nil {
		t.Fatalf("build export: %v", err)
	}
	for _, file := range response.Msg.GetFiles() {
		if strings.Contains(file.GetContent(), apiKey) {
			t.Fatalf("%s contains the AI key", file.GetName())
		}
	}
}

// --- prompt resolution, snapshots, refine and revert ------------------------

func snapshotOfRequest(request ai.Request) string {
	messages := make([]domain.PromptMessage, 0, len(request.Messages))
	for _, message := range request.Messages {
		messages = append(messages, domain.PromptMessage{Role: message.Role, Content: message.Content})
	}
	return domain.RenderPromptSnapshot(messages)
}

// updateAdditionalContext saves context without changing the summary, using
// the stored values so the server keeps the lifecycle where it was.
func updateAdditionalContext(t *testing.T, server *httptest.Server, token, checkInID, text string) {
	t.Helper()

	current, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get check-in before context save: %v", err)
	}
	checkIn := current.Msg.GetCheckIn()
	if _, err := checkInClient(server).UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
		Id:                checkInID,
		PeriodStart:       checkIn.GetPeriodStart(),
		PeriodEnd:         checkIn.GetPeriodEnd(),
		Audience:          checkIn.GetAudience(),
		FocusNotes:        checkIn.GetFocusNotes(),
		SummaryMarkdown:   checkIn.GetSummaryMarkdown(),
		SummaryModel:      checkIn.GetSummaryModel(),
		PromptVersion:     checkIn.GetPromptVersion(),
		SummarySource:     wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL,
		AdditionalContext: text,
	}, token)); err != nil {
		t.Fatalf("save additional context: %v", err)
	}
}

func collectRefinement(t *testing.T, server *httptest.Server, token, checkInID, feedback string, options ...connect.ClientOption) (generationResult, error) {
	t.Helper()

	stream, err := summaryClient(server, options...).RefineSummary(
		context.Background(),
		withBearer(&wdidv1.RefineSummaryRequest{CheckInId: checkInID, Feedback: feedback}, token),
	)
	if err != nil {
		return generationResult{}, err
	}
	defer stream.Close()

	result := generationResult{}
	for stream.Receive() {
		delta := stream.Msg()
		result.text += delta.GetText()
		result.deltas++
		if delta.GetCheckIn() != nil {
			result.final = delta.GetCheckIn()
		}
	}
	return result, stream.Err()
}

func revertSummary(t *testing.T, server *httptest.Server, token, checkInID string) (*wdidv1.CheckIn, error) {
	t.Helper()

	response, err := summaryClient(server).RevertSummary(context.Background(), withBearer(&wdidv1.RevertSummaryRequest{
		CheckInId: checkInID,
	}, token))
	if err != nil {
		return nil, err
	}
	return response.Msg.GetCheckIn(), nil
}

// TestSummaryServiceGenerateSummaryRecordsTheExactTranscript proves a custom
// template reaches generation, the transcript sent to the provider is stored
// verbatim, and list responses omit that snapshot.
func TestSummaryServiceGenerateSummaryRecordsTheExactTranscript(t *testing.T) {
	provider := &fakeAIProvider{
		deltas:   []string{"## Result\n", "- generated"},
		response: ai.Response{Model: "provider-model"},
	}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	buildSummaryExportFixture(t, server, database, token)
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	updateAdditionalContext(t, server, token, checkInID, "Off-ledger: migrated 12 customers.")

	if _, err := settingsClient(server).UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE,
		Body:    "Write a very blunt, evidence-first brief.",
	}, token)); err != nil {
		t.Fatalf("update prompt template: %v", err)
	}

	result, err := collectGeneration(t, server, token, checkInID, false)
	if err != nil {
		t.Fatalf("generate summary: %v", err)
	}
	if result.final == nil || result.final.GetPromptVersion() != domain.PromptVersionCustom {
		t.Fatalf("final = %+v, want the custom prompt version", result.final)
	}

	request := provider.lastRequest()
	if len(request.Messages) != 1 || request.Messages[0].Role != domain.PromptRoleUser {
		t.Fatalf("provider messages = %+v, want one user turn", request.Messages)
	}
	content := request.Messages[0].Content
	for _, expected := range []string{
		"Write a very blunt, evidence-first brief.",
		domain.PromptRules,
		"Off-ledger: migrated 12 customers.",
		"Billing migration",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("prompt is missing %q:\n%s", expected, content)
		}
	}

	stored, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get check-in: %v", err)
	}
	checkIn := stored.Msg.GetCheckIn()
	if checkIn.GetGenerationPrompt() != snapshotOfRequest(request) {
		t.Fatalf("stored snapshot =\n%q\nwant exactly what the provider received:\n%q",
			checkIn.GetGenerationPrompt(), snapshotOfRequest(request))
	}
	if checkIn.GetPreviousSummaryMarkdown() != "" {
		t.Fatalf("previous summary = %q, want none for a first generation", checkIn.GetPreviousSummaryMarkdown())
	}
	if checkIn.GetSummaryModel() != "provider-model" {
		t.Fatalf("model = %q", checkIn.GetSummaryModel())
	}

	// List responses stay small: the snapshot and revert slot are omitted, but
	// ordinary additional context is still present.
	listed, err := checkInClient(server).ListCheckIns(context.Background(), withBearer(&wdidv1.ListCheckInsRequest{}, token))
	if err != nil {
		t.Fatalf("list check-ins: %v", err)
	}
	if len(listed.Msg.GetCheckIns()) != 1 {
		t.Fatalf("check-ins = %d, want one", len(listed.Msg.GetCheckIns()))
	}
	listedCheckIn := listed.Msg.GetCheckIns()[0]
	if listedCheckIn.GetGenerationPrompt() != "" || listedCheckIn.GetPreviousSummaryMarkdown() != "" {
		t.Fatalf("list response carries provenance: %+v", listedCheckIn)
	}
	if listedCheckIn.GetAdditionalContext() != "Off-ledger: migrated 12 customers." {
		t.Fatalf("list context = %q, want the additional context kept", listedCheckIn.GetAdditionalContext())
	}
}

// TestSummaryServiceRevertRestoresThePreviousSummaryOnce proves a replaced
// summary moves into the revert slot, one revert restores it, the slot then
// clears, and a final check-in rejects generate, refine and revert.
func TestSummaryServiceRevertRestoresThePreviousSummaryOnce(t *testing.T) {
	provider := &fakeAIProvider{
		deltas:   []string{"first summary"},
		response: ai.Response{Model: "model-one"},
	}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	buildSummaryExportFixture(t, server, database, token)
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)

	if _, err := collectGeneration(t, server, token, checkInID, false); err != nil {
		t.Fatalf("first generation: %v", err)
	}
	if _, err := revertSummary(t, server, token, checkInID); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("revert without a previous summary code = %v, want failed precondition", connect.CodeOf(err))
	}

	provider.deltas = []string{"second summary"}
	if _, err := collectGeneration(t, server, token, checkInID, false); err != nil {
		t.Fatalf("second generation: %v", err)
	}
	stored, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get check-in: %v", err)
	}
	if stored.Msg.GetCheckIn().GetSummaryMarkdown() != "second summary" ||
		stored.Msg.GetCheckIn().GetPreviousSummaryMarkdown() != "first summary" {
		t.Fatalf("check-in after replacement = %+v, want the first summary in the slot", stored.Msg.GetCheckIn())
	}

	reverted, err := revertSummary(t, server, token, checkInID)
	if err != nil {
		t.Fatalf("revert: %v", err)
	}
	if reverted.GetSummaryMarkdown() != "first summary" || reverted.GetPreviousSummaryMarkdown() != "" {
		t.Fatalf("reverted check-in = %+v, want the first summary and an empty slot", reverted)
	}
	if reverted.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_GENERATED {
		t.Fatalf("state = %v, want the generated state kept", reverted.GetState())
	}

	// One step only.
	if _, err := revertSummary(t, server, token, checkInID); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("second revert code = %v, want failed precondition", connect.CodeOf(err))
	}

	// Leave a revert slot, then finalize: every writer is rejected.
	provider.deltas = []string{"third summary"}
	if _, err := collectGeneration(t, server, token, checkInID, false); err != nil {
		t.Fatalf("third generation: %v", err)
	}
	if _, err := checkInClient(server).FinalizeCheckIn(context.Background(), withBearer(&wdidv1.FinalizeCheckInRequest{Id: checkInID}, token)); err != nil {
		t.Fatalf("finalize check-in: %v", err)
	}
	before := provider.requestCount()
	if _, err := collectGeneration(t, server, token, checkInID, false); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("final generate code = %v, want failed precondition", connect.CodeOf(err))
	}
	if _, err := collectRefinement(t, server, token, checkInID, "tighten it"); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("final refine code = %v, want failed precondition", connect.CodeOf(err))
	}
	if _, err := revertSummary(t, server, token, checkInID); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("final revert code = %v, want failed precondition", connect.CodeOf(err))
	}
	if provider.requestCount() != before {
		t.Fatalf("provider calls after final rejection = %d, want %d", provider.requestCount(), before)
	}
}

// TestSummaryServiceRefineSummaryReplacesAHandEditedSummary proves refine sends
// the stored summary as an assistant turn, replaces it without an overwrite
// confirmation, records the exact transcript, and enforces its guards.
func TestSummaryServiceRefineSummaryReplacesAHandEditedSummary(t *testing.T) {
	provider := &fakeAIProvider{
		deltas:   []string{"refined summary"},
		response: ai.Response{Model: "refined-model"},
	}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	buildSummaryExportFixture(t, server, database, token)
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	handEdited := "## Hand edited\n- my own words"
	saveManualSummary(t, server, token, checkInID, handEdited)

	result, err := collectRefinement(t, server, token, checkInID, "  Make it shorter.  ")
	if err != nil {
		t.Fatalf("refine summary: %v", err)
	}
	if result.text != "refined summary" || result.final == nil {
		t.Fatalf("refine result = %+v", result)
	}
	if result.final.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_GENERATED ||
		result.final.GetPromptVersion() != domain.PromptVersion {
		t.Fatalf("refine final = %+v, want generated with the built-in version", result.final)
	}

	request := provider.lastRequest()
	if len(request.Messages) != 3 {
		t.Fatalf("messages = %+v, want instruction, stored summary and feedback", request.Messages)
	}
	if request.Messages[0].Role != domain.PromptRoleUser ||
		!strings.Contains(request.Messages[0].Content, "1:1") ||
		!strings.Contains(request.Messages[0].Content, "Billing migration") {
		t.Fatalf("first turn = %+v, want the instruction and period data", request.Messages[0])
	}
	if request.Messages[1].Role != domain.PromptRoleAssistant || request.Messages[1].Content != handEdited {
		t.Fatalf("assistant turn = %+v, want the stored hand-edited summary exactly", request.Messages[1])
	}
	if request.Messages[2].Role != domain.PromptRoleUser || request.Messages[2].Content != "Make it shorter." {
		t.Fatalf("feedback turn = %+v, want the trimmed feedback", request.Messages[2])
	}

	stored, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get refined check-in: %v", err)
	}
	refined := stored.Msg.GetCheckIn()
	if refined.GetSummaryMarkdown() != "refined summary" ||
		refined.GetPreviousSummaryMarkdown() != handEdited ||
		refined.GetSummaryModel() != "refined-model" ||
		refined.GetGenerationPrompt() != snapshotOfRequest(request) {
		t.Fatalf("refined check-in = %+v, want the new summary, slot, model and exact snapshot", refined)
	}

	// The hand-edited summary comes back with one revert.
	reverted, err := revertSummary(t, server, token, checkInID)
	if err != nil {
		t.Fatalf("revert refinement: %v", err)
	}
	if reverted.GetSummaryMarkdown() != handEdited {
		t.Fatalf("reverted summary = %q, want the hand-edited text", reverted.GetSummaryMarkdown())
	}

	// A check-in with no stored summary cannot be refined.
	emptyID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	before := provider.requestCount()
	if _, err := collectRefinement(t, server, token, emptyID, "tighten"); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("empty-summary refine code = %v, want failed precondition", connect.CodeOf(err))
	}

	// Blank feedback is a field error, not a provider call.
	saveManualSummary(t, server, token, emptyID, "## Something\n- to refine")
	_, err = collectRefinement(t, server, token, emptyID, "   ")
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("blank feedback code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "feedback" {
		t.Fatalf("blank feedback field violations = %v, want feedback", fields)
	}
	if provider.requestCount() != before {
		t.Fatalf("provider calls = %d, want %d after guard rejections", provider.requestCount(), before)
	}

	// A different account has no key, so its refinement is disabled even though
	// the administrator's key is stored.
	memberToken := registeredUserToken(t, server, database, "refine-member@example.com")
	memberID := createSummaryCheckIn(t, server, memberToken,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)
	saveManualSummary(t, server, memberToken, memberID, "## Member\n- own words")
	_, err = collectRefinement(t, server, memberToken, memberID, "tighten")
	if connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("member missing key code = %v, want failed precondition", connect.CodeOf(err))
	}
	if !strings.Contains(err.Error(), "Settings") || !strings.Contains(err.Error(), "key") {
		t.Fatalf("member missing key error = %v, want a Settings key prompt", err)
	}
	if provider.requestCount() != before {
		t.Fatalf("provider calls = %d, want %d without a member key", provider.requestCount(), before)
	}
}

// TestSummaryServiceRefineSummaryFailureIsNonDestructive proves a failed
// refinement leaves the stored summary, the revert slot and the snapshot
// untouched.
func TestSummaryServiceRefineSummaryFailureIsNonDestructive(t *testing.T) {
	provider := &fakeAIProvider{
		deltas:   []string{"first summary"},
		response: ai.Response{Model: "model-one"},
	}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	buildSummaryExportFixture(t, server, database, token)
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)

	if _, err := collectGeneration(t, server, token, checkInID, false); err != nil {
		t.Fatalf("first generation: %v", err)
	}
	provider.deltas = []string{"second summary"}
	if _, err := collectGeneration(t, server, token, checkInID, false); err != nil {
		t.Fatalf("second generation: %v", err)
	}
	handEdited := "## Hand\n- mine"
	saveManualSummary(t, server, token, checkInID, handEdited)

	before, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get check-in before failure: %v", err)
	}
	beforeCheckIn := before.Msg.GetCheckIn()
	if beforeCheckIn.GetPreviousSummaryMarkdown() != "first summary" || beforeCheckIn.GetGenerationPrompt() == "" {
		t.Fatalf("setup check-in = %+v, want a revert slot and snapshot", beforeCheckIn)
	}

	provider.deltas = []string{"## Partial"}
	provider.err = errors.New("provider stream failed")
	provider.failAfter = 1
	result, err := collectRefinement(t, server, token, checkInID, "tighten it")
	if err == nil {
		t.Fatal("expected the refinement to fail")
	}
	if connect.CodeOf(err) != connect.CodeUnavailable {
		t.Fatalf("code = %v, want unavailable", connect.CodeOf(err))
	}
	if result.text != "## Partial" {
		t.Fatalf("partial text = %q", result.text)
	}

	after, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkInID}, token))
	if err != nil {
		t.Fatalf("get check-in after failure: %v", err)
	}
	afterCheckIn := after.Msg.GetCheckIn()
	if afterCheckIn.GetSummaryMarkdown() != handEdited ||
		afterCheckIn.GetPreviousSummaryMarkdown() != "first summary" ||
		afterCheckIn.GetGenerationPrompt() != beforeCheckIn.GetGenerationPrompt() ||
		afterCheckIn.GetSummaryModel() != beforeCheckIn.GetSummaryModel() ||
		afterCheckIn.GetPromptVersion() != beforeCheckIn.GetPromptVersion() ||
		afterCheckIn.GetState() != beforeCheckIn.GetState() {
		t.Fatalf("check-in after failure = %+v, want everything unchanged", afterCheckIn)
	}

	// The untouched slot still reverts to the pre-refine summary.
	reverted, err := revertSummary(t, server, token, checkInID)
	if err != nil {
		t.Fatalf("revert after failure: %v", err)
	}
	if reverted.GetSummaryMarkdown() != "first summary" {
		t.Fatalf("reverted summary = %q, want the preserved slot", reverted.GetSummaryMarkdown())
	}
}

// TestSummaryServiceRejectsAConcurrentWriteForTheSameCheckIn proves generate,
// refine and revert share one in-flight slot, and that the slot is released
// when the provider finishes.
func TestSummaryServiceRejectsAConcurrentWriteForTheSameCheckIn(t *testing.T) {
	provider := &fakeAIProvider{
		deltas:   []string{"slow summary"},
		response: ai.Response{Model: "m"},
		started:  make(chan struct{}),
		release:  make(chan struct{}),
	}
	server, database := newDomainServerWithAI(t, provider)
	token := bootstrapToken(t, server)
	setAIKey(t, server, token, "sk-test-key")
	buildSummaryExportFixture(t, server, database, token)
	checkInID := createSummaryCheckIn(t, server, token,
		wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	)

	done := make(chan error, 1)
	go func() {
		stream, err := summaryClient(server).GenerateSummary(context.Background(), withBearer(&wdidv1.GenerateSummaryRequest{
			CheckInId: checkInID,
		}, token))
		if err != nil {
			done <- err
			return
		}
		defer stream.Close()
		for stream.Receive() {
		}
		done <- stream.Err()
	}()

	select {
	case <-provider.started:
	case <-time.After(10 * time.Second):
		t.Fatal("the first generation never reached the provider")
	}

	_, err := collectGeneration(t, server, token, checkInID, false)
	if connect.CodeOf(err) != connect.CodeFailedPrecondition || !strings.Contains(err.Error(), "in progress") {
		t.Fatalf("concurrent generate error = %v, want a failed-precondition in-flight error", err)
	}
	if _, err := revertSummary(t, server, token, checkInID); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("concurrent revert code = %v, want failed precondition", connect.CodeOf(err))
	}

	close(provider.release)
	if err := <-done; err != nil {
		t.Fatalf("first generation: %v", err)
	}

	// The slot is released, so a later write succeeds.
	provider.deltas = []string{"next summary"}
	if _, err := collectGeneration(t, server, token, checkInID, false); err != nil {
		t.Fatalf("generation after the slot was released: %v", err)
	}
}

// TestSummaryServiceBuildPromptUsesTheCallersTemplate proves the copy-prompt
// path resolves per-user overrides and reports the custom label, without
// leaking one account's override into another's.
func TestSummaryServiceBuildPromptUsesTheCallersTemplate(t *testing.T) {
	server, database := newDomainServer(t)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "build-prompt-member@example.com")
	buildSummaryExportFixture(t, server, database, adminToken)

	variant := wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE
	if _, err := settingsClient(server).UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: variant,
		Body:    "Admin-only prompt body.",
	}, adminToken)); err != nil {
		t.Fatalf("update prompt template: %v", err)
	}

	adminPrompt, err := summaryClient(server).BuildPrompt(context.Background(), withBearer(&wdidv1.BuildPromptRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-25",
	}, adminToken))
	if err != nil {
		t.Fatalf("build admin prompt: %v", err)
	}
	if !strings.Contains(adminPrompt.Msg.GetPrompt(), "Admin-only prompt body.") ||
		!strings.HasSuffix(adminPrompt.Msg.GetPrompt(), "Support: support.csv") {
		t.Fatalf("admin prompt = %q, want the custom body followed by summary.md", adminPrompt.Msg.GetPrompt())
	}
	if adminPrompt.Msg.GetPromptVersion() != domain.PromptVersionCustom {
		t.Fatalf("admin prompt version = %q, want custom", adminPrompt.Msg.GetPromptVersion())
	}

	memberPrompt, err := summaryClient(server).BuildPrompt(context.Background(), withBearer(&wdidv1.BuildPromptRequest{
		FromDate: "2026-10-19",
		ToDate:   "2026-10-25",
	}, memberToken))
	if err != nil {
		t.Fatalf("build member prompt: %v", err)
	}
	if strings.Contains(memberPrompt.Msg.GetPrompt(), "Admin-only prompt body.") {
		t.Fatalf("member prompt = %q, leaked the administrator's override", memberPrompt.Msg.GetPrompt())
	}
	if memberPrompt.Msg.GetPromptVersion() != domain.PromptVersion {
		t.Fatalf("member prompt version = %q, want %q", memberPrompt.Msg.GetPromptVersion(), domain.PromptVersion)
	}
}
