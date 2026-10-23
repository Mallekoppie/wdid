package rpc_test

import (
	"context"
	"testing"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
)

// TestProjectDetailServesConnect follows the project detail screen's traffic
// over both the unary Connect protocol and gRPC-Web: create a project, read
// its header fields, log entries against it, read its scoped timeline and
// report allocation, then archive and restore it.
func TestProjectDetailServesConnect(t *testing.T) {
	transports := []struct {
		name    string
		options []connect.ClientOption
	}{
		{name: "connect"},
		{name: "grpc-web", options: []connect.ClientOption{connect.WithGRPCWeb()}},
	}
	for _, transport := range transports {
		t.Run(transport.name, func(t *testing.T) {
			runProjectDetailFlow(t, transport.options...)
		})
	}
}

func runProjectDetailFlow(t *testing.T, options ...connect.ClientOption) {
	t.Helper()

	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	categories := categoryClient(server, options...)
	entries := entryClient(server, options...)
	summaries := summaryClient(server, options...)

	category, err := categories.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Initiatives",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
	}, token))
	if err != nil {
		t.Fatalf("CreateCategory: %v", err)
	}
	categoryID := category.Msg.GetCategory().GetId()

	project, err := categories.CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId:    categoryID,
		Name:          "Invoice pipeline",
		Description:   "Move invoicing to the new pipeline",
		Status:        wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
		Progress:      64,
		TargetOutcome: "Invoice generation under 5 minutes",
	}, token))
	if err != nil {
		t.Fatalf("CreateSubcategory: %v", err)
	}
	projectID := project.Msg.GetSubcategory().GetId()

	other, err := categories.CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: categoryID,
		Name:       "Dependency spike",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("CreateSubcategory: %v", err)
	}
	otherID := other.Msg.GetSubcategory().GetId()

	// The detail header reads the category and the project's project fields.
	listedCategories, err := categories.ListCategories(context.Background(), withBearer(&wdidv1.ListCategoriesRequest{}, token))
	if err != nil {
		t.Fatalf("ListCategories: %v", err)
	}
	var headerCategory *wdidv1.Category
	for _, candidate := range listedCategories.Msg.GetCategories() {
		if candidate.GetId() == categoryID {
			headerCategory = candidate
			break
		}
	}
	if headerCategory == nil || headerCategory.GetRole() != wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE {
		t.Fatalf("header category = %+v, want the initiative category", headerCategory)
	}
	listedProjects, err := categories.ListSubcategories(context.Background(), withBearer(&wdidv1.ListSubcategoriesRequest{
		CategoryId: categoryID,
	}, token))
	if err != nil {
		t.Fatalf("ListSubcategories: %v", err)
	}
	var headerProject *wdidv1.Subcategory
	for _, candidate := range listedProjects.Msg.GetSubcategories() {
		if candidate.GetId() == projectID {
			headerProject = candidate
			break
		}
	}
	if headerProject == nil {
		t.Fatal("header project is missing from ListSubcategories")
	}
	if headerProject.GetStatus() != wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE ||
		headerProject.GetProgress() != 64 ||
		headerProject.GetTargetOutcome() != "Invoice generation under 5 minutes" {
		t.Fatalf("header project = %+v, want status, progress and target outcome", headerProject)
	}

	create := func(subcategoryID, description string, started time.Time, minutes int) {
		t.Helper()
		if _, err := entries.CreateEntry(context.Background(), withBearer(&wdidv1.CreateEntryRequest{
			CategoryId:    categoryID,
			SubcategoryId: subcategoryID,
			Description:   description,
			StartedAt:     timestamppb.New(started),
			Duration:      durationpb.New(time.Duration(minutes) * time.Minute),
		}, token)); err != nil {
			t.Fatalf("CreateEntry: %v", err)
		}
	}
	create(projectID, "Backfill script", time.Date(2026, 10, 20, 9, 0, 0, 0, time.UTC), 60)
	create(projectID, "Backfill review", time.Date(2026, 10, 22, 9, 0, 0, 0, time.UTC), 30)
	create(otherID, "Spike notes", time.Date(2026, 10, 21, 9, 0, 0, 0, time.UTC), 15)

	// The timeline is the project's entries newest first, and the other
	// project's entry never leaks into it.
	timeline, err := entries.ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
		SubcategoryId: projectID,
	}, token))
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	got := timeline.Msg.GetEntries()
	if len(got) != 2 {
		t.Fatalf("timeline entries = %d, want 2", len(got))
	}
	if got[0].GetDescription() != "Backfill review" || got[1].GetDescription() != "Backfill script" {
		t.Fatalf("timeline order = %q, %q, want newest first", got[0].GetDescription(), got[1].GetDescription())
	}
	if got[0].GetSubcategoryId() != projectID || got[0].GetCategoryId() != categoryID {
		t.Fatalf("timeline attribution = %s/%s, want %s/%s", got[0].GetCategoryId(), got[0].GetSubcategoryId(), categoryID, projectID)
	}

	// The report owns the project-scoped totals the detail renders.
	report, err := summaries.GetPeriodReport(context.Background(), withBearer(&wdidv1.GetPeriodReportRequest{
		FromDate: "2026-10-01",
		ToDate:   "2026-10-31",
	}, token))
	if err != nil {
		t.Fatalf("GetPeriodReport: %v", err)
	}
	var allocation *wdidv1.SubcategoryAllocation
	for _, candidate := range report.Msg.GetReport().GetSubcategories() {
		if candidate.GetSubcategoryId() == projectID {
			allocation = candidate
			break
		}
	}
	if allocation == nil {
		t.Fatal("report has no allocation for the project")
	}
	if allocation.GetDuration().AsDuration() != 90*time.Minute {
		t.Fatalf("project minutes = %v, want 90m", allocation.GetDuration().AsDuration())
	}
	if allocation.GetEntryCount() != 2 {
		t.Fatalf("project entries = %d, want 2", allocation.GetEntryCount())
	}
	if allocation.GetLastActivityDate() != "2026-10-22" {
		t.Fatalf("last activity = %q, want 2026-10-22", allocation.GetLastActivityDate())
	}
	if allocation.GetLastActivityDescription() != "Backfill review" {
		t.Fatalf("last activity description = %q, want Backfill review", allocation.GetLastActivityDescription())
	}

	// Archiving is how the detail becomes read-only; restore re-enables it.
	archived, err := categories.ArchiveSubcategory(context.Background(), withBearer(&wdidv1.ArchiveSubcategoryRequest{
		Id:       projectID,
		Archived: true,
	}, token))
	if err != nil {
		t.Fatalf("ArchiveSubcategory: %v", err)
	}
	if !archived.Msg.GetSubcategory().GetArchived() {
		t.Fatal("archive did not set the flag")
	}
	restored, err := categories.ArchiveSubcategory(context.Background(), withBearer(&wdidv1.ArchiveSubcategoryRequest{
		Id:       projectID,
		Archived: false,
	}, token))
	if err != nil {
		t.Fatalf("restore subcategory: %v", err)
	}
	if restored.Msg.GetSubcategory().GetArchived() {
		t.Fatal("restore did not clear the flag")
	}
}
