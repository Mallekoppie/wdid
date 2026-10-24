package rpc_test

import (
	"context"
	"net/http/httptest"
	"testing"

	"connectrpc.com/connect"

	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
)

func milestoneClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.MilestoneServiceClient {
	return wdidv1connect.NewMilestoneServiceClient(server.Client(), server.URL, options...)
}

// createMilestoneProject creates an initiative-role category and one project,
// returning the project's id. Milestones always belong to a real project.
func createMilestoneProject(t *testing.T, server *httptest.Server, token, name string) string {
	t.Helper()

	categoryResponse, err := categoryClient(server).CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Milestone initiatives",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
	}, token))
	if err != nil {
		t.Fatalf("create milestone category: %v", err)
	}
	subcategoryResponse, err := categoryClient(server).CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: categoryResponse.Msg.GetCategory().GetId(),
		Name:       name,
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("create milestone project: %v", err)
	}
	return subcategoryResponse.Msg.GetSubcategory().GetId()
}

func TestMilestoneServiceRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)

	_, err := milestoneClient(server).ListMilestones(context.Background(), connect.NewRequest(&wdidv1.ListMilestonesRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

// TestMilestoneServiceServesConnectAndGRPCWeb exercises the project detail's
// milestone traffic over both the unary Connect protocol and gRPC-Web: create
// dated and undated milestones, edit one, mark one done and the other not done,
// delete one, and read the authoritative completion counts from the report.
func TestMilestoneServiceServesConnectAndGRPCWeb(t *testing.T) {
	transports := []struct {
		name    string
		options []connect.ClientOption
	}{
		{name: "connect"},
		{name: "grpc-web", options: []connect.ClientOption{connect.WithGRPCWeb()}},
	}
	for _, transport := range transports {
		t.Run(transport.name, func(t *testing.T) {
			runMilestoneFlow(t, transport.options...)
		})
	}
}

func runMilestoneFlow(t *testing.T, options ...connect.ClientOption) {
	t.Helper()

	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := milestoneClient(server, options...)
	projectID := createMilestoneProject(t, server, token, "Invoice pipeline")
	otherProjectID := createMilestoneProject(t, server, token, "Dependency spike")

	create := func(subcategoryID, title, dueDate string, done bool) *wdidv1.Milestone {
		t.Helper()
		response, err := client.CreateMilestone(context.Background(), withBearer(&wdidv1.CreateMilestoneRequest{
			SubcategoryId: subcategoryID,
			Title:         title,
			DueDate:       dueDate,
			Done:          done,
		}, token))
		if err != nil {
			t.Fatalf("CreateMilestone %q: %v", title, err)
		}
		return response.Msg.GetMilestone()
	}

	undated := create(projectID, "  Plan the backfill  ", "", false)
	if undated.GetId() == "" {
		t.Fatal("created milestone has no id")
	}
	if undated.GetTitle() != "Plan the backfill" {
		t.Fatalf("title = %q, want the trimmed title", undated.GetTitle())
	}
	if undated.GetSubcategoryId() != projectID {
		t.Fatalf("subcategory = %q, want %q", undated.GetSubcategoryId(), projectID)
	}
	if undated.GetDueDate() != "" || undated.GetDone() {
		t.Fatalf("undated milestone = %+v, want no due date and not done", undated)
	}

	dated := create(projectID, "Ship to production", "2026-11-15", true)
	if dated.GetDueDate() != "2026-11-15" || !dated.GetDone() {
		t.Fatalf("dated milestone = %+v, want the due date and done flag", dated)
	}
	other := create(otherProjectID, "Spike the dependency", "2026-10-25", false)

	listed, err := client.ListMilestones(context.Background(), withBearer(&wdidv1.ListMilestonesRequest{SubcategoryId: projectID}, token))
	if err != nil {
		t.Fatalf("ListMilestones: %v", err)
	}
	if len(listed.Msg.GetMilestones()) != 2 {
		t.Fatalf("project milestones = %+v, want two", listed.Msg.GetMilestones())
	}
	// Due date ascending, undated last.
	if listed.Msg.GetMilestones()[0].GetId() != dated.GetId() ||
		listed.Msg.GetMilestones()[1].GetId() != undated.GetId() {
		t.Fatalf("milestone order = %+v, want dated first and undated last", listed.Msg.GetMilestones())
	}

	updated, err := client.UpdateMilestone(context.Background(), withBearer(&wdidv1.UpdateMilestoneRequest{
		Id:      undated.GetId(),
		Title:   "Review the backfill plan",
		DueDate: "2026-10-30",
		Done:    true,
	}, token))
	if err != nil {
		t.Fatalf("UpdateMilestone: %v", err)
	}
	if updated.Msg.GetMilestone().GetTitle() != "Review the backfill plan" ||
		updated.Msg.GetMilestone().GetDueDate() != "2026-10-30" ||
		!updated.Msg.GetMilestone().GetDone() {
		t.Fatalf("updated milestone = %+v, want the new fields", updated.Msg.GetMilestone())
	}
	// The project is immutable through an update.
	if updated.Msg.GetMilestone().GetSubcategoryId() != projectID {
		t.Fatalf("updated subcategory = %q, want the original project", updated.Msg.GetMilestone().GetSubcategoryId())
	}

	// Marking a done milestone not done is the same update path.
	reopened, err := client.UpdateMilestone(context.Background(), withBearer(&wdidv1.UpdateMilestoneRequest{
		Id:      dated.GetId(),
		Title:   dated.GetTitle(),
		DueDate: dated.GetDueDate(),
		Done:    false,
	}, token))
	if err != nil {
		t.Fatalf("UpdateMilestone reopen: %v", err)
	}
	if reopened.Msg.GetMilestone().GetDone() {
		t.Fatal("reopened milestone is still done")
	}
	// Creation time is the record's, not the update's.
	if !reopened.Msg.GetMilestone().GetCreatedAt().AsTime().Equal(dated.GetCreatedAt().AsTime()) {
		t.Fatal("update changed the milestone's creation time")
	}

	// Completion counts are authoritative in the period report. No entries are
	// needed: completion belongs to the project, not the period.
	report, err := summaryClient(server, options...).GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-01",
		ToDate:   "2026-10-31",
	}, token))
	if err != nil {
		t.Fatalf("GetPeriodReport: %v", err)
	}
	progress := map[string]*wdidv1.MilestoneProgress{}
	for _, item := range report.Msg.GetReport().GetMilestoneProgress() {
		progress[item.GetSubcategoryId()] = item
	}
	projectProgress := progress[projectID]
	if projectProgress == nil || projectProgress.GetTotal() != 2 || projectProgress.GetDone() != 1 {
		t.Fatalf("project milestone progress = %+v, want 1 of 2 done", projectProgress)
	}
	otherProgress := progress[otherProjectID]
	if otherProgress == nil || otherProgress.GetTotal() != 1 || otherProgress.GetDone() != 0 {
		t.Fatalf("other milestone progress = %+v, want 0 of 1 done", otherProgress)
	}

	if _, err := client.DeleteMilestone(context.Background(), withBearer(&wdidv1.DeleteMilestoneRequest{Id: other.GetId()}, token)); err != nil {
		t.Fatalf("DeleteMilestone: %v", err)
	}
	remaining, err := client.ListMilestones(context.Background(), withBearer(&wdidv1.ListMilestonesRequest{SubcategoryId: otherProjectID}, token))
	if err != nil {
		t.Fatalf("ListMilestones after delete: %v", err)
	}
	if len(remaining.Msg.GetMilestones()) != 0 {
		t.Fatalf("milestones after delete = %+v, want none", remaining.Msg.GetMilestones())
	}
	_, err = client.DeleteMilestone(context.Background(), withBearer(&wdidv1.DeleteMilestoneRequest{Id: other.GetId()}, token))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("delete missing milestone code = %v, want not found", connect.CodeOf(err))
	}
}

func TestMilestoneServiceRejectsInvalidMilestones(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := milestoneClient(server)
	projectID := createMilestoneProject(t, server, token, "Invoice pipeline")

	cases := []struct {
		name   string
		create *wdidv1.CreateMilestoneRequest
		field  string
	}{
		{
			name:   "missing title",
			create: &wdidv1.CreateMilestoneRequest{SubcategoryId: projectID, DueDate: "2026-10-31"},
			field:  "title",
		},
		{
			name:   "missing project",
			create: &wdidv1.CreateMilestoneRequest{Title: "No project"},
			field:  "subcategoryId",
		},
		{
			name:   "bad due date",
			create: &wdidv1.CreateMilestoneRequest{SubcategoryId: projectID, Title: "Bad date", DueDate: "31/10/2026"},
			field:  "dueDate",
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := client.CreateMilestone(context.Background(), withBearer(testCase.create, token))
			if connect.CodeOf(err) != connect.CodeInvalidArgument {
				t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
			}
			if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != testCase.field {
				t.Fatalf("field violations = %v, want %s", fields, testCase.field)
			}
		})
	}

	created, err := client.CreateMilestone(context.Background(), withBearer(&wdidv1.CreateMilestoneRequest{
		SubcategoryId: projectID,
		Title:         "Valid",
	}, token))
	if err != nil {
		t.Fatalf("create valid milestone: %v", err)
	}
	_, err = client.UpdateMilestone(context.Background(), withBearer(&wdidv1.UpdateMilestoneRequest{
		Id:    created.Msg.GetMilestone().GetId(),
		Title: " ",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("empty update title code = %v, want invalid argument", connect.CodeOf(err))
	}

	// An unknown project is a not-found reference, not a validation failure.
	_, err = client.CreateMilestone(context.Background(), withBearer(&wdidv1.CreateMilestoneRequest{
		SubcategoryId: "missing-project",
		Title:         "Orphan",
	}, token))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("unknown project code = %v, want not found", connect.CodeOf(err))
	}
}

func TestMilestoneServiceIsolatesAccounts(t *testing.T) {
	server, database := newDomainServer(t)
	firstToken := bootstrapToken(t, server)
	projectID := createMilestoneProject(t, server, firstToken, "Invoice pipeline")

	created, err := milestoneClient(server).CreateMilestone(context.Background(), withBearer(&wdidv1.CreateMilestoneRequest{
		SubcategoryId: projectID,
		Title:         "Private milestone",
	}, firstToken))
	if err != nil {
		t.Fatalf("create milestone: %v", err)
	}
	milestone := created.Msg.GetMilestone()

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
	secondToken := second.Msg.GetToken()

	listed, err := milestoneClient(server).ListMilestones(context.Background(), withBearer(&wdidv1.ListMilestonesRequest{}, secondToken))
	if err != nil {
		t.Fatalf("list second account milestones: %v", err)
	}
	if len(listed.Msg.GetMilestones()) != 0 {
		t.Fatalf("second account milestones = %+v, want none", listed.Msg.GetMilestones())
	}

	_, err = milestoneClient(server).UpdateMilestone(context.Background(), withBearer(&wdidv1.UpdateMilestoneRequest{
		Id:    milestone.GetId(),
		Title: "Hijacked",
		Done:  true,
	}, secondToken))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("cross-user update code = %v, want not found", connect.CodeOf(err))
	}

	_, err = milestoneClient(server).DeleteMilestone(context.Background(), withBearer(&wdidv1.DeleteMilestoneRequest{Id: milestone.GetId()}, secondToken))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("cross-user delete code = %v, want not found", connect.CodeOf(err))
	}
}

func TestMilestoneServiceSurvivesRestart(t *testing.T) {
	cfg := testConfig(t)
	server, database := newDomainServerWithConfig(t, cfg)
	token := bootstrapToken(t, server)
	projectID := createMilestoneProject(t, server, token, "Invoice pipeline")

	created, err := milestoneClient(server).CreateMilestone(context.Background(), withBearer(&wdidv1.CreateMilestoneRequest{
		SubcategoryId: projectID,
		Title:         "Ship before the restart",
		DueDate:       "2026-11-15",
		Done:          true,
	}, token))
	if err != nil {
		t.Fatalf("create milestone: %v", err)
	}
	milestone := created.Msg.GetMilestone()

	if err := database.Close(); err != nil {
		t.Fatalf("close database: %v", err)
	}
	restarted, _ := newDomainServerWithConfig(t, cfg)

	listed, err := milestoneClient(restarted).ListMilestones(context.Background(), withBearer(&wdidv1.ListMilestonesRequest{
		SubcategoryId: projectID,
	}, token))
	if err != nil {
		t.Fatalf("list milestones after restart: %v", err)
	}
	if len(listed.Msg.GetMilestones()) != 1 {
		t.Fatalf("milestones after restart = %+v, want the saved milestone", listed.Msg.GetMilestones())
	}
	restored := listed.Msg.GetMilestones()[0]
	if restored.GetId() != milestone.GetId() || !restored.GetDone() || restored.GetDueDate() != "2026-11-15" {
		t.Fatalf("restored milestone = %+v, want the saved fields", restored)
	}
}
