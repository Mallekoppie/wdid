package rpc_test

import (
	"context"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
)

func checkInClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.CheckInServiceClient {
	return wdidv1connect.NewCheckInServiceClient(server.Client(), server.URL, options...)
}

// forEachCheckInProtocol runs the same contract assertions over the unary
// Connect protocol and gRPC-Web, the two the Flutter client can use.
func forEachCheckInProtocol(t *testing.T, run func(t *testing.T, options ...connect.ClientOption)) {
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

// saveCheckInSettings writes the preferences the boundary calculation reads.
func saveCheckInSettings(t *testing.T, database *store.Store, userID, timezone, journalStart string) {
	t.Helper()

	settings, err := database.Settings(userID)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	settings.Timezone = timezone
	settings.JournalStartDate = journalStart
	if err := database.SaveSettings(settings); err != nil {
		t.Fatalf("save settings: %v", err)
	}
}

func TestCheckInServiceRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)

	_, err := checkInClient(server).ListCheckIns(context.Background(), connect.NewRequest(&wdidv1.ListCheckInsRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}

	_, err = checkInClient(server).DeleteCheckIn(context.Background(), connect.NewRequest(&wdidv1.DeleteCheckInRequest{Id: "checkin-1"}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("delete code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

// TestCheckInServiceDefaultsStartAtTheJournalStartAndUseTheUsersDay pins the
// boundary before any manager check-in exists. The clock is already the next
// day in UTC, so a UTC-based answer would return 23 October instead.
func TestCheckInServiceDefaultsStartAtTheJournalStartAndUseTheUsersDay(t *testing.T) {
	now := time.Date(2026, 10, 23, 2, 0, 0, 0, time.UTC)
	server, database := newDomainServerWithCheckInClock(t, func() time.Time { return now })
	token := bootstrapToken(t, server)
	saveCheckInSettings(t, database, currentUserID(t, server, token), "America/New_York", "2026-09-01")

	response, err := checkInClient(server).GetCheckInDefaults(context.Background(), withBearer(&wdidv1.GetCheckInDefaultsRequest{
		Kind: wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
	}, token))
	if err != nil {
		t.Fatalf("get check-in defaults: %v", err)
	}
	defaults := response.Msg
	if defaults.GetPeriodStart() != "2026-09-01" {
		t.Fatalf("period start = %q, want the journal start date", defaults.GetPeriodStart())
	}
	if defaults.GetPeriodEnd() != "2026-10-22" {
		t.Fatalf("period end = %q, want the user's local today", defaults.GetPeriodEnd())
	}
	if defaults.GetLastFinalCheckInId() != "" {
		t.Fatalf("last final id = %q, want empty before a final check-in", defaults.GetLastFinalCheckInId())
	}

	// An unknown enum value is rejected rather than treated as manager.
	_, err = checkInClient(server).GetCheckInDefaults(context.Background(), withBearer(
		&wdidv1.GetCheckInDefaultsRequest{Kind: wdidv1.CheckInKind(99)}, token,
	))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("unknown kind code = %v, want invalid argument", connect.CodeOf(err))
	}
}

// TestCheckInServiceSnapshotsTheAuthoritativeReport proves the stored totals
// come from the period report rather than anything the client sent.
func TestCheckInServiceSnapshotsTheAuthoritativeReport(t *testing.T) {
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)
	server, database := newDomainServerWithCheckInClock(t, func() time.Time { return now })
	token := bootstrapToken(t, server)
	saveCheckInSettings(t, database, currentUserID(t, server, token), "UTC", "2026-10-01")
	initiativeID, projectID := createEntryTaxonomy(t, server, token)
	supportID, unblockID := createSupportTaxonomy(t, server, token)

	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    initiativeID,
		SubcategoryId: projectID,
		Description:   "Backfill script",
		StartedAt:     timestamppb.New(time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(60 * time.Minute),
	})
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    supportID,
		SubcategoryId: unblockID,
		Description:   "Unblocked CI keys",
		People:        []string{"Priya"},
		StartedAt:     timestamppb.New(time.Date(2026, 10, 21, 9, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(30 * time.Minute),
	})
	// Outside the period, so it must not enter the snapshot.
	createReportEntry(t, server, token, &wdidv1.CreateEntryRequest{
		CategoryId:    initiativeID,
		SubcategoryId: projectID,
		Description:   "Before the period",
		StartedAt:     timestamppb.New(time.Date(2026, 9, 30, 9, 0, 0, 0, time.UTC)),
		Duration:      durationpb.New(120 * time.Minute),
	})

	response, err := checkInClient(server).CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
		Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		PeriodStart: "2026-10-19",
		PeriodEnd:   "2026-10-22",
		Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		FocusNotes:  "  Ship the backfill and keep support small.  ",
	}, token))
	if err != nil {
		t.Fatalf("create check-in: %v", err)
	}

	checkIn := response.Msg.GetCheckIn()
	if checkIn.GetId() == "" {
		t.Fatal("created check-in has no id")
	}
	if checkIn.GetKind() != wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER ||
		checkIn.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_DRAFT {
		t.Fatalf("check-in = %+v, want a draft manager check-in", checkIn)
	}
	if checkIn.GetAudience() != wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE {
		t.Fatalf("audience = %v, want one-on-one", checkIn.GetAudience())
	}
	if checkIn.GetFocusNotes() != "Ship the backfill and keep support small." {
		t.Fatalf("focus notes = %q, want trimmed notes", checkIn.GetFocusNotes())
	}
	if !checkIn.GetCreatedAt().AsTime().Equal(now) {
		t.Fatalf("created at = %v, want the service clock", checkIn.GetCreatedAt().AsTime())
	}

	totals := checkIn.GetTotals()
	if totals.GetTotal().AsDuration() != 90*time.Minute {
		t.Fatalf("total = %v, want 90m from the report", totals.GetTotal().AsDuration())
	}
	categories := totalMinutesByKey(totals.GetByCategory())
	if categories[initiativeID] != 60 || categories[supportID] != 30 {
		t.Fatalf("by category = %v, want 60m initiative and 30m support", categories)
	}
	if subcategories := totalMinutesByKey(totals.GetBySubcategory()); subcategories[projectID] != 60 || subcategories[unblockID] != 30 {
		t.Fatalf("by subcategory = %v, want project and support mode time", subcategories)
	}
	if people := totalMinutesByKey(totals.GetSupportByPerson()); people["Priya"] != 30 {
		t.Fatalf("support by person = %v, want Priya 30m", people)
	}
	if totals.GetSupportDuration().AsDuration() != 30*time.Minute || totals.GetSupportInteractions() != 1 {
		t.Fatalf("support totals = %v/%d interactions, want the authoritative 30m support entry",
			totals.GetSupportDuration().AsDuration(), totals.GetSupportInteractions())
	}

	stored, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: checkIn.GetId()}, token))
	if err != nil {
		t.Fatalf("get check-in: %v", err)
	}
	if stored.Msg.GetCheckIn().GetFocusNotes() != "Ship the backfill and keep support small." {
		t.Fatalf("stored focus notes = %q", stored.Msg.GetCheckIn().GetFocusNotes())
	}
}

// TestCheckInServiceReadsLegacySupportTotals proves a check-in stored before
// the authoritative totals existed still reports the pre-upgrade semantics,
// while a fresh multi-person snapshot keeps its authoritative totals.
func TestCheckInServiceReadsLegacySupportTotals(t *testing.T) {
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)
	server, database := newDomainServer(t)
	token := bootstrapToken(t, server)
	userID := currentUserID(t, server, token)

	storeCheckIn := func(checkIn domain.CheckIn) {
		t.Helper()
		checkIn.UserID = userID
		checkIn.Kind = domain.CheckInKindManager
		checkIn.State = domain.CheckInStateDraft
		checkIn.Audience = domain.AudienceOneOnOne
		checkIn.PeriodStart = "2026-10-01"
		checkIn.PeriodEnd = "2026-10-20"
		checkIn.CreatedAt = now
		checkIn.UpdatedAt = now
		if err := database.SaveCheckIn(checkIn); err != nil {
			t.Fatalf("save check-in: %v", err)
		}
	}

	// Pre-upgrade shape: only per-person rows, no authoritative totals.
	storeCheckIn(domain.CheckIn{
		ID: "legacy-checkin",
		Totals: domain.CheckInTotals{
			Minutes:         90,
			SupportByPerson: map[string]int{"Priya": 30},
		},
	})
	// Fresh multi-person shape: rows sum to 90 but the authoritative total is 45.
	storeCheckIn(domain.CheckIn{
		ID: "fresh-checkin",
		Totals: domain.CheckInTotals{
			Minutes:             90,
			SupportByPerson:     map[string]int{"Priya": 45, "Sam": 45},
			SupportMinutes:      45,
			SupportInteractions: 2,
		},
	})

	tests := []struct {
		id           string
		wantDuration time.Duration
		wantInteract int32
	}{
		{id: "legacy-checkin", wantDuration: 30 * time.Minute, wantInteract: 1},
		{id: "fresh-checkin", wantDuration: 45 * time.Minute, wantInteract: 2},
	}
	for _, test := range tests {
		t.Run(test.id, func(t *testing.T) {
			response, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(
				&wdidv1.GetCheckInRequest{Id: test.id}, token,
			))
			if err != nil {
				t.Fatalf("get check-in: %v", err)
			}
			totals := response.Msg.GetCheckIn().GetTotals()
			if totals.GetSupportDuration().AsDuration() != test.wantDuration ||
				totals.GetSupportInteractions() != test.wantInteract {
				t.Fatalf("support totals = %v/%d, want %v/%d",
					totals.GetSupportDuration().AsDuration(), totals.GetSupportInteractions(),
					test.wantDuration, test.wantInteract)
			}
		})
	}
}

func totalMinutesByKey(totals []*wdidv1.CheckInTotal) map[string]int {
	values := make(map[string]int, len(totals))
	for _, total := range totals {
		values[total.GetKey()] = int(total.GetDuration().AsDuration() / time.Minute)
	}
	return values
}

// TestCheckInServiceCreationFinalizationAndBoundary runs the whole lifecycle
// over both the unary Connect protocol and gRPC-Web.
func TestCheckInServiceCreationFinalizationAndBoundary(t *testing.T) {
	protocols := []struct {
		name    string
		options []connect.ClientOption
	}{
		{name: "connect"},
		{name: "grpc-web", options: []connect.ClientOption{connect.WithGRPCWeb()}},
	}

	for _, protocol := range protocols {
		t.Run(protocol.name, func(t *testing.T) {
			now := time.Date(2026, 10, 23, 12, 0, 0, 0, time.UTC)
			server, database := newDomainServerWithCheckInClock(t, func() time.Time { return now })
			token := bootstrapToken(t, server)
			saveCheckInSettings(t, database, currentUserID(t, server, token), "UTC", "2026-10-01")
			client := checkInClient(server, protocol.options...)

			created, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
				Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
				PeriodStart: "2026-10-01",
				PeriodEnd:   "2026-10-22",
				Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
				FocusNotes:  "Quarterly review evidence.",
			}, token))
			if err != nil {
				t.Fatalf("create check-in: %v", err)
			}
			if created.Msg.GetCheckIn().GetAudience() != wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW {
				t.Fatalf("audience = %v, want performance review", created.Msg.GetCheckIn().GetAudience())
			}

			finalized, err := client.FinalizeCheckIn(context.Background(), withBearer(&wdidv1.FinalizeCheckInRequest{
				Id: created.Msg.GetCheckIn().GetId(),
			}, token))
			if err != nil {
				t.Fatalf("finalize check-in: %v", err)
			}
			if finalized.Msg.GetCheckIn().GetState() != wdidv1.CheckInState_CHECK_IN_STATE_FINAL {
				t.Fatalf("state = %v, want final", finalized.Msg.GetCheckIn().GetState())
			}
			if !finalized.Msg.GetCheckIn().GetUpdatedAt().AsTime().Equal(now) {
				t.Fatalf("updated at = %v, want the finalize time", finalized.Msg.GetCheckIn().GetUpdatedAt().AsTime())
			}

			// A final manager check-in is read-only.
			_, err = client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
				Id:          created.Msg.GetCheckIn().GetId(),
				PeriodStart: "2026-10-01",
				PeriodEnd:   "2026-10-22",
				FocusNotes:  "Rewritten after final",
			}, token))
			if connect.CodeOf(err) != connect.CodeFailedPrecondition {
				t.Fatalf("update final code = %v, want failed precondition", connect.CodeOf(err))
			}

			// Finalizing moves the boundary to the day after its period end.
			defaults, err := client.GetCheckInDefaults(context.Background(), withBearer(&wdidv1.GetCheckInDefaultsRequest{
				Kind: wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
			}, token))
			if err != nil {
				t.Fatalf("get defaults after final: %v", err)
			}
			if defaults.Msg.GetPeriodStart() != "2026-10-23" || defaults.Msg.GetPeriodEnd() != "2026-10-23" {
				t.Fatalf("defaults = %s..%s, want today after the boundary moved",
					defaults.Msg.GetPeriodStart(), defaults.Msg.GetPeriodEnd())
			}
			if defaults.Msg.GetLastFinalCheckInId() != created.Msg.GetCheckIn().GetId() {
				t.Fatalf("last final id = %q, want %q", defaults.Msg.GetLastFinalCheckInId(), created.Msg.GetCheckIn().GetId())
			}

			// The next manager check-in starts at the moved boundary.
			next, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
				Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
				PeriodStart: defaults.Msg.GetPeriodStart(),
				PeriodEnd:   defaults.Msg.GetPeriodEnd(),
				Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
			}, token))
			if err != nil {
				t.Fatalf("create next check-in: %v", err)
			}
			if next.Msg.GetCheckIn().GetPeriodStart() != "2026-10-23" {
				t.Fatalf("next period start = %q, want the moved boundary", next.Msg.GetCheckIn().GetPeriodStart())
			}
		})
	}
}

func TestCheckInServiceFiltersByKindAndProtectsPersonalReviews(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := checkInClient(server)

	create := func(kind wdidv1.CheckInKind, audience wdidv1.CheckInAudience) *wdidv1.CheckIn {
		t.Helper()
		response, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
			Kind:        kind,
			PeriodStart: "2026-10-01",
			PeriodEnd:   "2026-10-07",
			Audience:    audience,
		}, token))
		if err != nil {
			t.Fatalf("create %v check-in: %v", kind, err)
		}
		return response.Msg.GetCheckIn()
	}

	manager := create(wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER, wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE)
	personal := create(wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL, wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_UNSPECIFIED)
	if personal.GetAudience() != wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_UNSPECIFIED {
		t.Fatalf("personal audience = %v, want none", personal.GetAudience())
	}

	managers, err := client.ListCheckIns(context.Background(), withBearer(&wdidv1.ListCheckInsRequest{
		Kind: wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
	}, token))
	if err != nil {
		t.Fatalf("list manager check-ins: %v", err)
	}
	if len(managers.Msg.GetCheckIns()) != 1 || managers.Msg.GetCheckIns()[0].GetId() != manager.GetId() {
		t.Fatalf("manager check-ins = %+v, want only the manager", managers.Msg.GetCheckIns())
	}

	personals, err := client.ListCheckIns(context.Background(), withBearer(&wdidv1.ListCheckInsRequest{
		Kind: wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL,
	}, token))
	if err != nil {
		t.Fatalf("list personal reviews: %v", err)
	}
	if len(personals.Msg.GetCheckIns()) != 1 || personals.Msg.GetCheckIns()[0].GetId() != personal.GetId() {
		t.Fatalf("personal reviews = %+v, want only the personal review", personals.Msg.GetCheckIns())
	}

	all, err := client.ListCheckIns(context.Background(), withBearer(&wdidv1.ListCheckInsRequest{}, token))
	if err != nil {
		t.Fatalf("list all check-ins: %v", err)
	}
	if len(all.Msg.GetCheckIns()) != 2 {
		t.Fatalf("all check-ins = %d, want both kinds", len(all.Msg.GetCheckIns()))
	}

	// A personal review never becomes final.
	if _, err := client.FinalizeCheckIn(context.Background(), withBearer(&wdidv1.FinalizeCheckInRequest{
		Id: personal.GetId(),
	}, token)); connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("finalize personal code = %v, want failed precondition", connect.CodeOf(err))
	}

	// A personal review never carries an audience.
	_, err = client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
		Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL,
		PeriodStart: "2026-10-01",
		PeriodEnd:   "2026-10-07",
		Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("personal audience code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "audience" {
		t.Fatalf("field violations = %v, want audience", fields)
	}
}

func TestCheckInServiceValidatesRequests(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := checkInClient(server)

	_, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
		Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_UNSPECIFIED,
		PeriodStart: "2026-10-01",
		PeriodEnd:   "2026-10-07",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("missing kind code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "kind" {
		t.Fatalf("field violations = %v, want kind", fields)
	}

	_, err = client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
		Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		PeriodStart: "2026-10-07",
		PeriodEnd:   "2026-10-01",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("reversed period code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "periodEnd" {
		t.Fatalf("field violations = %v, want periodEnd", fields)
	}

	// An update always keeps the stored kind, so a personal review cannot
	// acquire an audience through the back door.
	response, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
		Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL,
		PeriodStart: "2026-10-01",
		PeriodEnd:   "2026-10-07",
	}, token))
	if err != nil {
		t.Fatalf("create personal review: %v", err)
	}
	_, err = client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
		Id:          response.Msg.GetCheckIn().GetId(),
		PeriodStart: "2026-10-01",
		PeriodEnd:   "2026-10-07",
		Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("update personal audience code = %v, want invalid argument", connect.CodeOf(err))
	}
}

func TestCheckInServiceKeepsDraftsEditable(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := checkInClient(server)

	created, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
		Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		PeriodStart: "2026-10-01",
		PeriodEnd:   "2026-10-07",
		Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		FocusNotes:  "Initial focus",
	}, token))
	if err != nil {
		t.Fatalf("create check-in: %v", err)
	}

	updated, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
		Id:              created.Msg.GetCheckIn().GetId(),
		PeriodStart:     "2026-10-01",
		PeriodEnd:       "2026-10-08",
		Audience:        wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
		FocusNotes:      "Updated focus",
		SummaryMarkdown: "## Highlights\n- Evidence",
		SummaryModel:    "test/model",
		PromptVersion:   "v2",
	}, token))
	if err != nil {
		t.Fatalf("update draft: %v", err)
	}
	checkIn := updated.Msg.GetCheckIn()
	if checkIn.GetPeriodEnd() != "2026-10-08" || checkIn.GetFocusNotes() != "Updated focus" {
		t.Fatalf("updated check-in = %+v", checkIn)
	}
	if checkIn.GetAudience() != wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW {
		t.Fatalf("audience = %v, want the updated audience", checkIn.GetAudience())
	}
	// A summary edit moves the lifecycle forward.
	if checkIn.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_EDITED {
		t.Fatalf("state = %v, want edited after a summary change", checkIn.GetState())
	}

	// Cross-user access stays hidden.
	if _, err := checkInClient(server).GetCheckIn(context.Background(), withBearer(
		&wdidv1.GetCheckInRequest{Id: checkIn.GetId()}, "someone-else",
	)); connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("cross-user code = %v, want unauthenticated for an invalid token", connect.CodeOf(err))
	}
}

// TestCheckInServicePersonalReviewLifecycle covers saving, editing and deleting
// a personal review over both the unary Connect protocol and gRPC-Web, and
// proves that none of those actions move the manager boundary. "Discard" has
// no service call by design: asking for defaults must not create a draft.
func TestCheckInServicePersonalReviewLifecycle(t *testing.T) {
	protocols := []struct {
		name    string
		options []connect.ClientOption
	}{
		{name: "connect"},
		{name: "grpc-web", options: []connect.ClientOption{connect.WithGRPCWeb()}},
	}

	for _, protocol := range protocols {
		t.Run(protocol.name, func(t *testing.T) {
			now := time.Date(2026, 10, 23, 12, 0, 0, 0, time.UTC)
			server, database := newDomainServerWithCheckInClock(t, func() time.Time { return now })
			token := bootstrapToken(t, server)
			saveCheckInSettings(t, database, currentUserID(t, server, token), "UTC", "2026-10-01")
			client := checkInClient(server, protocol.options...)

			assertBoundary := func(wantLastFinal string) {
				t.Helper()
				defaults, err := client.GetCheckInDefaults(context.Background(), withBearer(&wdidv1.GetCheckInDefaultsRequest{
					Kind: wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
				}, token))
				if err != nil {
					t.Fatalf("get defaults: %v", err)
				}
				if defaults.Msg.GetPeriodStart() != "2026-10-11" {
					t.Fatalf("boundary start = %q, want the day after the final manager check-in", defaults.Msg.GetPeriodStart())
				}
				if defaults.Msg.GetLastFinalCheckInId() != wantLastFinal {
					t.Fatalf("last final id = %q, want %q", defaults.Msg.GetLastFinalCheckInId(), wantLastFinal)
				}
			}

			// Setting up the boundary, then opening (and abandoning) a review
			// must not create anything.
			manager, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
				Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
				PeriodStart: "2026-10-01",
				PeriodEnd:   "2026-10-10",
				Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
			}, token))
			if err != nil {
				t.Fatalf("create manager check-in: %v", err)
			}
			if _, err := client.FinalizeCheckIn(context.Background(), withBearer(&wdidv1.FinalizeCheckInRequest{
				Id: manager.Msg.GetCheckIn().GetId(),
			}, token)); err != nil {
				t.Fatalf("finalize manager check-in: %v", err)
			}
			if _, err := client.GetCheckInDefaults(context.Background(), withBearer(&wdidv1.GetCheckInDefaultsRequest{
				Kind: wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL,
			}, token)); err != nil {
				t.Fatalf("open personal review defaults: %v", err)
			}
			afterDefaults, err := client.ListCheckIns(context.Background(), withBearer(&wdidv1.ListCheckInsRequest{}, token))
			if err != nil {
				t.Fatalf("list after defaults: %v", err)
			}
			if len(afterDefaults.Msg.GetCheckIns()) != 1 {
				t.Fatalf("check-ins after opening a review = %d, want only the manager check-in", len(afterDefaults.Msg.GetCheckIns()))
			}
			assertBoundary(manager.Msg.GetCheckIn().GetId())

			// Save.
			personal, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
				Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL,
				PeriodStart: "2026-10-04",
				PeriodEnd:   "2026-10-10",
				FocusNotes:  "What moved this week?",
			}, token))
			if err != nil {
				t.Fatalf("save personal review: %v", err)
			}
			if personal.Msg.GetCheckIn().GetKind() != wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL {
				t.Fatalf("kind = %v, want personal", personal.Msg.GetCheckIn().GetKind())
			}
			assertBoundary(manager.Msg.GetCheckIn().GetId())

			// Edit: the review stays personal and editable, with no audience.
			edited, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
				Id:              personal.Msg.GetCheckIn().GetId(),
				PeriodStart:     "2026-10-04",
				PeriodEnd:       "2026-10-10",
				FocusNotes:      "What moved, what did not.",
				SummaryMarkdown: "## Highlights\n- Shipped the backfill",
			}, token))
			if err != nil {
				t.Fatalf("edit personal review: %v", err)
			}
			if edited.Msg.GetCheckIn().GetState() != wdidv1.CheckInState_CHECK_IN_STATE_EDITED {
				t.Fatalf("state = %v, want edited", edited.Msg.GetCheckIn().GetState())
			}
			if edited.Msg.GetCheckIn().GetAudience() != wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_UNSPECIFIED {
				t.Fatalf("audience = %v, want none for a personal review", edited.Msg.GetCheckIn().GetAudience())
			}
			assertBoundary(manager.Msg.GetCheckIn().GetId())

			// Delete.
			if _, err := client.DeleteCheckIn(context.Background(), withBearer(&wdidv1.DeleteCheckInRequest{
				Id: personal.Msg.GetCheckIn().GetId(),
			}, token)); err != nil {
				t.Fatalf("delete personal review: %v", err)
			}
			if _, err := client.GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{
				Id: personal.Msg.GetCheckIn().GetId(),
			}, token)); connect.CodeOf(err) != connect.CodeNotFound {
				t.Fatalf("get deleted review code = %v, want not found", connect.CodeOf(err))
			}
			remaining, err := client.ListCheckIns(context.Background(), withBearer(&wdidv1.ListCheckInsRequest{}, token))
			if err != nil {
				t.Fatalf("list after delete: %v", err)
			}
			if len(remaining.Msg.GetCheckIns()) != 1 || remaining.Msg.GetCheckIns()[0].GetKind() != wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER {
				t.Fatalf("check-ins after delete = %+v, want only the manager check-in", remaining.Msg.GetCheckIns())
			}
			assertBoundary(manager.Msg.GetCheckIn().GetId())

			// A final manager check-in is the boundary and cannot be deleted.
			if _, err := client.DeleteCheckIn(context.Background(), withBearer(&wdidv1.DeleteCheckInRequest{
				Id: manager.Msg.GetCheckIn().GetId(),
			}, token)); connect.CodeOf(err) != connect.CodeFailedPrecondition {
				t.Fatalf("delete final manager code = %v, want failed precondition", connect.CodeOf(err))
			}
			assertBoundary(manager.Msg.GetCheckIn().GetId())
		})
	}
}

// TestCheckInServiceSavesSummaryAndProtectsManualEdits proves that a Markdown
// summary can be saved (including an empty one), that an audience change never
// touches it, and that generated output cannot replace a manual edit without
// the explicit confirmation flag.
func TestCheckInServiceSavesSummaryAndProtectsManualEdits(t *testing.T) {
	forEachCheckInProtocol(t, func(t *testing.T, options ...connect.ClientOption) {
		server, _ := newDomainServer(t)
		token := bootstrapToken(t, server)
		client := checkInClient(server, options...)

		created, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
			Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
			PeriodStart: "2026-10-01",
			PeriodEnd:   "2026-10-07",
			Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		}, token))
		if err != nil {
			t.Fatalf("create check-in: %v", err)
		}
		id := created.Msg.GetCheckIn().GetId()

		update := func(summary string, source wdidv1.CheckInSummarySource, overwrite bool) (*wdidv1.CheckIn, error) {
			response, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
				Id:                   id,
				PeriodStart:          "2026-10-01",
				PeriodEnd:            "2026-10-07",
				Audience:             wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
				SummaryMarkdown:      summary,
				SummarySource:        source,
				OverwriteManualEdits: overwrite,
			}, token))
			if err != nil {
				return nil, err
			}
			return response.Msg.GetCheckIn(), nil
		}

		markdown := "## Highlights\n- Cut invoicing from 40 min to 3 min"
		saved, err := update(markdown, wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL, false)
		if err != nil {
			t.Fatalf("save summary: %v", err)
		}
		if saved.GetSummaryMarkdown() != markdown {
			t.Fatalf("summary = %q, want the saved Markdown", saved.GetSummaryMarkdown())
		}
		if saved.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_EDITED {
			t.Fatalf("state = %v, want edited after a manual save", saved.GetState())
		}

		// An empty summary is allowed and is not a validation error.
		empty, err := update("", wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL, false)
		if err != nil {
			t.Fatalf("save empty summary: %v", err)
		}
		if empty.GetSummaryMarkdown() != "" {
			t.Fatalf("summary = %q, want empty", empty.GetSummaryMarkdown())
		}

		if _, err := update(markdown, wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL, false); err != nil {
			t.Fatalf("restore manual summary: %v", err)
		}

		// A generated summary must not replace the manual edit silently.
		_, err = update("## Generated\n- invented evidence", wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_GENERATED, false)
		if connect.CodeOf(err) != connect.CodeFailedPrecondition {
			t.Fatalf("generated overwrite code = %v, want failed precondition", connect.CodeOf(err))
		}
		stored, err := client.GetCheckIn(context.Background(), withBearer(&wdidv1.GetCheckInRequest{Id: id}, token))
		if err != nil {
			t.Fatalf("get check-in after refused overwrite: %v", err)
		}
		if stored.Msg.GetCheckIn().GetSummaryMarkdown() != markdown ||
			stored.Msg.GetCheckIn().GetState() != wdidv1.CheckInState_CHECK_IN_STATE_EDITED {
			t.Fatalf("check-in after refused overwrite = %+v, want the manual summary intact", stored.Msg.GetCheckIn())
		}

		// With confirmation the generated text replaces it and keeps the
		// generated state.
		replaced, err := update("## Generated\n- evidence from the period", wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_GENERATED, true)
		if err != nil {
			t.Fatalf("confirmed overwrite: %v", err)
		}
		if replaced.GetSummaryMarkdown() != "## Generated\n- evidence from the period" {
			t.Fatalf("summary = %q, want the generated text", replaced.GetSummaryMarkdown())
		}
		if replaced.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_GENERATED {
			t.Fatalf("state = %v, want generated", replaced.GetState())
		}

		// A manual edit after generation is always allowed.
		manualAgain, err := update("## Manual again", wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL, false)
		if err != nil {
			t.Fatalf("manual edit after generation: %v", err)
		}
		if manualAgain.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_EDITED {
			t.Fatalf("state = %v, want edited after a manual save", manualAgain.GetState())
		}

		// An audience change sends the same summary text and leaves it alone.
		switched, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
			Id:              id,
			PeriodStart:     "2026-10-01",
			PeriodEnd:       "2026-10-07",
			Audience:        wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
			SummaryMarkdown: "## Manual again",
			SummarySource:   wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL,
		}, token))
		if err != nil {
			t.Fatalf("switch audience: %v", err)
		}
		if switched.Msg.GetCheckIn().GetSummaryMarkdown() != "## Manual again" {
			t.Fatalf("summary after audience change = %q, want it untouched", switched.Msg.GetCheckIn().GetSummaryMarkdown())
		}
		if switched.Msg.GetCheckIn().GetAudience() != wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW {
			t.Fatalf("audience = %v, want performance review", switched.Msg.GetCheckIn().GetAudience())
		}

		// An unknown source is rejected instead of being treated as manual.
		_, err = update("## Anything", wdidv1.CheckInSummarySource(99), false)
		if connect.CodeOf(err) != connect.CodeInvalidArgument {
			t.Fatalf("unknown summary source code = %v, want invalid argument", connect.CodeOf(err))
		}
		if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "summarySource" {
			t.Fatalf("field violations = %v, want summarySource", fields)
		}
	})
}

// TestCheckInServiceAudienceSelectsThePromptVariant proves the audience preset
// is visible on the check-in and changes the prompt template while leaving the
// stored summary and data untouched.
func TestCheckInServiceAudienceSelectsThePromptVariant(t *testing.T) {
	forEachCheckInProtocol(t, func(t *testing.T, options ...connect.ClientOption) {
		server, _ := newDomainServer(t)
		token := bootstrapToken(t, server)
		client := checkInClient(server, options...)

		created, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
			Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
			PeriodStart: "2026-10-01",
			PeriodEnd:   "2026-10-07",
		}, token))
		if err != nil {
			t.Fatalf("create check-in: %v", err)
		}
		if created.Msg.GetCheckIn().GetAudience() != wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE {
			t.Fatalf("audience = %v, want the one-on-one default", created.Msg.GetCheckIn().GetAudience())
		}
		id := created.Msg.GetCheckIn().GetId()

		summary := "## Highlights\n- Shipped the backfill"
		if _, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
			Id:              id,
			PeriodStart:     "2026-10-01",
			PeriodEnd:       "2026-10-07",
			Audience:        wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
			SummaryMarkdown: summary,
			SummarySource:   wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL,
		}, token)); err != nil {
			t.Fatalf("save summary: %v", err)
		}

		oneOnOne, err := client.BuildCheckInPrompt(context.Background(), withBearer(&wdidv1.BuildCheckInPromptRequest{Id: id}, token))
		if err != nil {
			t.Fatalf("build one-on-one prompt: %v", err)
		}
		if oneOnOne.Msg.GetVariant() != wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE {
			t.Fatalf("variant = %v, want manager one-on-one", oneOnOne.Msg.GetVariant())
		}
		if oneOnOne.Msg.GetPromptVersion() != "v1" {
			t.Fatalf("prompt version = %q, want v1", oneOnOne.Msg.GetPromptVersion())
		}
		if !strings.Contains(oneOnOne.Msg.GetPrompt(), "1:1") || !strings.HasSuffix(oneOnOne.Msg.GetPrompt(), summary) {
			t.Fatalf("one-on-one prompt = %q, want the 1:1 instruction followed by the summary", oneOnOne.Msg.GetPrompt())
		}

		// Selecting the performance-review audience changes only the prompt.
		switched, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
			Id:              id,
			PeriodStart:     "2026-10-01",
			PeriodEnd:       "2026-10-07",
			Audience:        wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
			SummaryMarkdown: summary,
			SummarySource:   wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL,
		}, token))
		if err != nil {
			t.Fatalf("switch audience: %v", err)
		}
		if switched.Msg.GetCheckIn().GetAudience() != wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW {
			t.Fatalf("audience = %v, want performance review", switched.Msg.GetCheckIn().GetAudience())
		}
		if switched.Msg.GetCheckIn().GetSummaryMarkdown() != summary {
			t.Fatalf("summary = %q, want the audience change to leave it untouched", switched.Msg.GetCheckIn().GetSummaryMarkdown())
		}

		performance, err := client.BuildCheckInPrompt(context.Background(), withBearer(&wdidv1.BuildCheckInPromptRequest{Id: id}, token))
		if err != nil {
			t.Fatalf("build performance prompt: %v", err)
		}
		if performance.Msg.GetVariant() != wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW {
			t.Fatalf("variant = %v, want manager performance review", performance.Msg.GetVariant())
		}
		if performance.Msg.GetPrompt() == oneOnOne.Msg.GetPrompt() {
			t.Fatal("the performance-review audience must select a different prompt")
		}
		if !strings.Contains(performance.Msg.GetPrompt(), "performance review") ||
			!strings.HasSuffix(performance.Msg.GetPrompt(), summary) {
			t.Fatalf("performance prompt = %q, want the review instruction followed by the summary", performance.Msg.GetPrompt())
		}

		// A personal review uses the personal variant.
		personal, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
			Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL,
			PeriodStart: "2026-10-01",
			PeriodEnd:   "2026-10-07",
		}, token))
		if err != nil {
			t.Fatalf("create personal review: %v", err)
		}
		personalPrompt, err := client.BuildCheckInPrompt(context.Background(), withBearer(&wdidv1.BuildCheckInPromptRequest{
			Id: personal.Msg.GetCheckIn().GetId(),
		}, token))
		if err != nil {
			t.Fatalf("build personal prompt: %v", err)
		}
		if personalPrompt.Msg.GetVariant() != wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW {
			t.Fatalf("variant = %v, want personal review", personalPrompt.Msg.GetVariant())
		}

		// Unknown ids stay hidden and unauthenticated calls are refused.
		if _, err := client.BuildCheckInPrompt(context.Background(), withBearer(&wdidv1.BuildCheckInPromptRequest{
			Id: "missing",
		}, token)); connect.CodeOf(err) != connect.CodeNotFound {
			t.Fatalf("missing id code = %v, want not found", connect.CodeOf(err))
		}
		if _, err := client.BuildCheckInPrompt(context.Background(), connect.NewRequest(&wdidv1.BuildCheckInPromptRequest{
			Id: id,
		})); connect.CodeOf(err) != connect.CodeUnauthenticated {
			t.Fatalf("unauthenticated code = %v, want unauthenticated", connect.CodeOf(err))
		}
	})
}

// TestCheckInServiceUpdatesAdditionalContextWithoutTouchingTheSummary proves a
// context-only update leaves the lifecycle, summary, model and prompt version
// alone, and that a final manager check-in rejects it.
func TestCheckInServiceUpdatesAdditionalContextWithoutTouchingTheSummary(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := checkInClient(server)

	created, err := client.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
		Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
		PeriodStart: "2026-10-01",
		PeriodEnd:   "2026-10-07",
		Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
	}, token))
	if err != nil {
		t.Fatalf("create check-in: %v", err)
	}
	id := created.Msg.GetCheckIn().GetId()

	// A serial port draft context save must not advance the lifecycle.
	draft, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
		Id:                id,
		PeriodStart:       "2026-10-01",
		PeriodEnd:         "2026-10-07",
		Audience:          wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		AdditionalContext: "  Recorded offline: shipped the backfill.  ",
	}, token))
	if err != nil {
		t.Fatalf("context-only draft update: %v", err)
	}
	if draft.Msg.GetCheckIn().GetState() != wdidv1.CheckInState_CHECK_IN_STATE_DRAFT {
		t.Fatalf("state = %v, want draft after a context-only update", draft.Msg.GetCheckIn().GetState())
	}
	if draft.Msg.GetCheckIn().GetAdditionalContext() != "Recorded offline: shipped the backfill." {
		t.Fatalf("context = %q, want the trimmed text", draft.Msg.GetCheckIn().GetAdditionalContext())
	}

	markdown := "## Highlights\n- Cut invoicing from 40 min to 3 min"
	if _, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
		Id:              id,
		PeriodStart:     "2026-10-01",
		PeriodEnd:       "2026-10-07",
		Audience:        wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		SummaryMarkdown: markdown,
		SummaryModel:    "test/model",
		PromptVersion:   "v1",
		SummarySource:   wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL,
	}, token)); err != nil {
		t.Fatalf("save summary: %v", err)
	}

	edited, err := client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
		Id:                id,
		PeriodStart:       "2026-10-01",
		PeriodEnd:         "2026-10-07",
		Audience:          wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		SummaryMarkdown:   markdown,
		SummaryModel:      "test/model",
		PromptVersion:     "v1",
		SummarySource:     wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL,
		AdditionalContext: "Explain the invoicing win here.",
	}, token))
	if err != nil {
		t.Fatalf("context-only edited update: %v", err)
	}
	checkIn := edited.Msg.GetCheckIn()
	if checkIn.GetState() != wdidv1.CheckInState_CHECK_IN_STATE_EDITED {
		t.Fatalf("state = %v, want the edited state kept", checkIn.GetState())
	}
	if checkIn.GetSummaryMarkdown() != markdown ||
		checkIn.GetSummaryModel() != "test/model" ||
		checkIn.GetPromptVersion() != "v1" {
		t.Fatalf("check-in after context save = %+v, want summary metadata untouched", checkIn)
	}
	if checkIn.GetAdditionalContext() != "Explain the invoicing win here." {
		t.Fatalf("context = %q", checkIn.GetAdditionalContext())
	}

	if _, err := client.FinalizeCheckIn(context.Background(), withBearer(&wdidv1.FinalizeCheckInRequest{Id: id}, token)); err != nil {
		t.Fatalf("finalize check-in: %v", err)
	}
	_, err = client.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
		Id:                id,
		PeriodStart:       "2026-10-01",
		PeriodEnd:         "2026-10-07",
		Audience:          wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		SummaryMarkdown:   markdown,
		SummaryModel:      "test/model",
		PromptVersion:     "v1",
		AdditionalContext: "late edit",
	}, token))
	if connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("final context update code = %v, want failed precondition", connect.CodeOf(err))
	}
}

// TestCheckInServiceBuildCheckInPromptUsesTheCallersTemplate proves the
// copy-prompt path resolves the caller's per-account override and reports the
// custom version label.
func TestCheckInServiceBuildCheckInPromptUsesTheCallersTemplate(t *testing.T) {
	server, database := newDomainServer(t)
	adminToken := bootstrapToken(t, server)
	memberToken := registeredUserToken(t, server, database, "prompt-copy@example.com")
	checkIns := checkInClient(server)

	createWithSummary := func(token string) string {
		t.Helper()
		created, err := checkIns.CreateCheckIn(context.Background(), withBearer(&wdidv1.CreateCheckInRequest{
			Kind:        wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER,
			PeriodStart: "2026-10-01",
			PeriodEnd:   "2026-10-07",
			Audience:    wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
		}, token))
		if err != nil {
			t.Fatalf("create check-in: %v", err)
		}
		id := created.Msg.GetCheckIn().GetId()
		if _, err := checkIns.UpdateCheckIn(context.Background(), withBearer(&wdidv1.UpdateCheckInRequest{
			Id:              id,
			PeriodStart:     "2026-10-01",
			PeriodEnd:       "2026-10-07",
			Audience:        wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE,
			SummaryMarkdown: "## Highlights\n- Shipped",
			SummarySource:   wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL,
		}, token)); err != nil {
			t.Fatalf("save summary: %v", err)
		}
		return id
	}

	adminID := createWithSummary(adminToken)
	memberID := createWithSummary(memberToken)

	variant := wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE
	if _, err := settingsClient(server).UpdatePromptTemplate(context.Background(), withBearer(&wdidv1.UpdatePromptTemplateRequest{
		Variant: variant,
		Body:    "Write the administrator's blunt 1:1 brief.",
	}, adminToken)); err != nil {
		t.Fatalf("update prompt template: %v", err)
	}

	adminPrompt, err := checkIns.BuildCheckInPrompt(context.Background(), withBearer(&wdidv1.BuildCheckInPromptRequest{Id: adminID}, adminToken))
	if err != nil {
		t.Fatalf("build admin prompt: %v", err)
	}
	if !strings.Contains(adminPrompt.Msg.GetPrompt(), "administrator's blunt") ||
		!strings.HasSuffix(adminPrompt.Msg.GetPrompt(), "## Highlights\n- Shipped") {
		t.Fatalf("admin prompt = %q, want the custom body followed by the summary", adminPrompt.Msg.GetPrompt())
	}
	if adminPrompt.Msg.GetPromptVersion() != domain.PromptVersionCustom {
		t.Fatalf("admin prompt version = %q, want custom", adminPrompt.Msg.GetPromptVersion())
	}

	memberPrompt, err := checkIns.BuildCheckInPrompt(context.Background(), withBearer(&wdidv1.BuildCheckInPromptRequest{Id: memberID}, memberToken))
	if err != nil {
		t.Fatalf("build member prompt: %v", err)
	}
	if strings.Contains(memberPrompt.Msg.GetPrompt(), "administrator's blunt") ||
		!strings.Contains(memberPrompt.Msg.GetPrompt(), "1:1") {
		t.Fatalf("member prompt = %q, want the built-in body", memberPrompt.Msg.GetPrompt())
	}
	if memberPrompt.Msg.GetPromptVersion() != domain.PromptVersion {
		t.Fatalf("member prompt version = %q, want %q", memberPrompt.Msg.GetPromptVersion(), domain.PromptVersion)
	}
}
