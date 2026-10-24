package rpc_test

import (
	"context"
	"net/http/httptest"
	"testing"
	"time"

	"connectrpc.com/connect"

	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
)

func noteClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.NoteServiceClient {
	return wdidv1connect.NewNoteServiceClient(server.Client(), server.URL, options...)
}

// createNoteProject creates an initiative-role category and one subcategory,
// returning the project's id. Both note contexts need a real project.
func createNoteProject(t *testing.T, server *httptest.Server, token string) string {
	t.Helper()

	categoryResponse, err := categoryClient(server).CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Notes",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
	}, token))
	if err != nil {
		t.Fatalf("create note category: %v", err)
	}
	subcategoryResponse, err := categoryClient(server).CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: categoryResponse.Msg.GetCategory().GetId(),
		Name:       "Billing migration",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("create note project: %v", err)
	}
	return subcategoryResponse.Msg.GetSubcategory().GetId()
}

func TestNoteServiceRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)

	_, err := noteClient(server).ListNotes(context.Background(), connect.NewRequest(&wdidv1.ListNotesRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

func TestNoteServiceCreatesListsUpdatesAndDeletesBothContexts(t *testing.T) {
	server, database := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := noteClient(server)
	projectID := createNoteProject(t, server, token)

	create := func(date, subcategoryID, text string) *wdidv1.Note {
		t.Helper()
		response, err := client.CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
			Date:          date,
			SubcategoryId: subcategoryID,
			Text:          text,
		}, token))
		if err != nil {
			t.Fatalf("create note %q: %v", text, err)
		}
		return response.Msg.GetNote()
	}

	dayNote := create("2026-10-20", "", "  End of day context.  ")
	if dayNote.GetId() == "" {
		t.Fatal("created day note has no id")
	}
	if dayNote.GetText() != "End of day context." {
		t.Fatalf("text = %q, want the trimmed note", dayNote.GetText())
	}
	if dayNote.GetDate() != "2026-10-20" || dayNote.GetSubcategoryId() != "" {
		t.Fatalf("day note = %+v", dayNote)
	}

	// A project note needs only the subcategory; the date may be empty.
	time.Sleep(2 * time.Millisecond)
	projectNote := create("", projectID, "Rollback rehearsal is still pending.")
	if projectNote.GetSubcategoryId() != projectID || projectNote.GetDate() != "" {
		t.Fatalf("project note = %+v", projectNote)
	}

	// A note may carry both contexts.
	time.Sleep(2 * time.Millisecond)
	datedProjectNote := create("2026-10-21", projectID, "Decision recorded.")

	dayListing, err := client.ListNotes(context.Background(), withBearer(&wdidv1.ListNotesRequest{Date: "2026-10-20"}, token))
	if err != nil {
		t.Fatalf("list day notes: %v", err)
	}
	if len(dayListing.Msg.GetNotes()) != 1 || dayListing.Msg.GetNotes()[0].GetId() != dayNote.GetId() {
		t.Fatalf("day notes = %+v, want the day note", dayListing.Msg.GetNotes())
	}

	projectListing, err := client.ListNotes(context.Background(), withBearer(&wdidv1.ListNotesRequest{SubcategoryId: projectID}, token))
	if err != nil {
		t.Fatalf("list project notes: %v", err)
	}
	if len(projectListing.Msg.GetNotes()) != 2 {
		t.Fatalf("project notes = %+v, want both project notes", projectListing.Msg.GetNotes())
	}
	// Newest first.
	if projectListing.Msg.GetNotes()[0].GetId() != datedProjectNote.GetId() ||
		projectListing.Msg.GetNotes()[1].GetId() != projectNote.GetId() {
		t.Fatalf("project notes order = %+v, want newest first", projectListing.Msg.GetNotes())
	}

	allListing, err := client.ListNotes(context.Background(), withBearer(&wdidv1.ListNotesRequest{}, token))
	if err != nil {
		t.Fatalf("list all notes: %v", err)
	}
	if len(allListing.Msg.GetNotes()) != 3 {
		t.Fatalf("all notes = %d, want 3", len(allListing.Msg.GetNotes()))
	}
	if allListing.Msg.GetNotes()[0].GetId() != datedProjectNote.GetId() ||
		allListing.Msg.GetNotes()[2].GetId() != dayNote.GetId() {
		t.Fatalf("all notes order = %+v, want the newest note first", allListing.Msg.GetNotes())
	}

	updated, err := client.UpdateNote(context.Background(), withBearer(&wdidv1.UpdateNoteRequest{
		Id:   dayNote.GetId(),
		Date: "2026-10-20",
		Text: "Rewritten at the end of the day.",
	}, token))
	if err != nil {
		t.Fatalf("update day note: %v", err)
	}
	if updated.Msg.GetNote().GetText() != "Rewritten at the end of the day." {
		t.Fatalf("updated text = %q", updated.Msg.GetNote().GetText())
	}
	if !updated.Msg.GetNote().GetCreatedAt().AsTime().Equal(dayNote.GetCreatedAt().AsTime()) {
		t.Fatal("update changed the note's creation time")
	}

	if _, err := client.UpdateNote(context.Background(), withBearer(&wdidv1.UpdateNoteRequest{
		Id:            projectNote.GetId(),
		SubcategoryId: projectID,
		Text:          "Rehearsal booked.",
	}, token)); err != nil {
		t.Fatalf("update project note: %v", err)
	}

	if _, err := client.DeleteNote(context.Background(), withBearer(&wdidv1.DeleteNoteRequest{Id: projectNote.GetId()}, token)); err != nil {
		t.Fatalf("delete project note: %v", err)
	}
	remaining, err := client.ListNotes(context.Background(), withBearer(&wdidv1.ListNotesRequest{SubcategoryId: projectID}, token))
	if err != nil {
		t.Fatalf("list after delete: %v", err)
	}
	if len(remaining.Msg.GetNotes()) != 1 || remaining.Msg.GetNotes()[0].GetId() != datedProjectNote.GetId() {
		t.Fatalf("notes after delete = %+v, want the other project note", remaining.Msg.GetNotes())
	}
	_, err = client.DeleteNote(context.Background(), withBearer(&wdidv1.DeleteNoteRequest{Id: projectNote.GetId()}, token))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("delete missing note code = %v, want not found", connect.CodeOf(err))
	}

	// The note is stored against the account that created it.
	user, err := database.UserByEmail("admin@example.com")
	if err != nil {
		t.Fatalf("read user: %v", err)
	}
	if _, err := database.Note(user.ID, dayNote.GetId()); err != nil {
		t.Fatalf("read stored day note: %v", err)
	}
}

func TestNoteServiceRejectsInvalidNotes(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := noteClient(server)

	_, err := client.CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
		Date: "2026-10-20",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("empty text code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "text" {
		t.Fatalf("empty text field violations = %v, want text", fields)
	}

	_, err = client.CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
		Text: "Orphan note",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("no context code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "date" {
		t.Fatalf("no context field violations = %v, want date", fields)
	}

	created, err := client.CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
		Date: "2026-10-20",
		Text: "Valid",
	}, token))
	if err != nil {
		t.Fatalf("create valid note: %v", err)
	}
	_, err = client.UpdateNote(context.Background(), withBearer(&wdidv1.UpdateNoteRequest{
		Id:   created.Msg.GetNote().GetId(),
		Date: "20-10-2026",
		Text: "Bad date",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("bad date code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "date" {
		t.Fatalf("bad date field violations = %v, want date", fields)
	}
}

func TestNoteServiceIsolatesAccounts(t *testing.T) {
	server, database := newDomainServer(t)
	firstToken := bootstrapToken(t, server)
	note := func() *wdidv1.Note {
		response, err := noteClient(server).CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
			Date: "2026-10-20",
			Text: "Private note",
		}, firstToken))
		if err != nil {
			t.Fatalf("create note: %v", err)
		}
		return response.Msg.GetNote()
	}()
	_ = note

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

	listed, err := noteClient(server).ListNotes(context.Background(), withBearer(&wdidv1.ListNotesRequest{Date: "2026-10-20"}, secondToken))
	if err != nil {
		t.Fatalf("list second account notes: %v", err)
	}
	if len(listed.Msg.GetNotes()) != 0 {
		t.Fatalf("second account notes = %+v, want none", listed.Msg.GetNotes())
	}

	_, err = noteClient(server).UpdateNote(context.Background(), withBearer(&wdidv1.UpdateNoteRequest{
		Id:   note.GetId(),
		Date: "2026-10-20",
		Text: "Hijacked",
	}, secondToken))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("cross-user update code = %v, want not found", connect.CodeOf(err))
	}

	_, err = noteClient(server).DeleteNote(context.Background(), withBearer(&wdidv1.DeleteNoteRequest{Id: note.GetId()}, secondToken))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("cross-user delete code = %v, want not found", connect.CodeOf(err))
	}
}

func TestNoteServiceSurvivesRestart(t *testing.T) {
	cfg := testConfig(t)
	server, database := newDomainServerWithConfig(t, cfg)
	token := bootstrapToken(t, server)
	projectID := createNoteProject(t, server, token)

	dayNote, err := noteClient(server).CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
		Date: "2026-10-20",
		Text: "Day note before restart.",
	}, token))
	if err != nil {
		t.Fatalf("create day note: %v", err)
	}
	projectNote, err := noteClient(server).CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
		SubcategoryId: projectID,
		Text:          "Project note before restart.",
	}, token))
	if err != nil {
		t.Fatalf("create project note: %v", err)
	}

	if err := database.Close(); err != nil {
		t.Fatalf("close database: %v", err)
	}
	restarted, _ := newDomainServerWithConfig(t, cfg)

	dayNotes, err := noteClient(restarted).ListNotes(context.Background(), withBearer(&wdidv1.ListNotesRequest{Date: "2026-10-20"}, token))
	if err != nil {
		t.Fatalf("list day notes after restart: %v", err)
	}
	if len(dayNotes.Msg.GetNotes()) != 1 || dayNotes.Msg.GetNotes()[0].GetId() != dayNote.Msg.GetNote().GetId() {
		t.Fatalf("day notes after restart = %+v", dayNotes.Msg.GetNotes())
	}

	projectNotes, err := noteClient(restarted).ListNotes(context.Background(), withBearer(&wdidv1.ListNotesRequest{SubcategoryId: projectID}, token))
	if err != nil {
		t.Fatalf("list project notes after restart: %v", err)
	}
	if len(projectNotes.Msg.GetNotes()) != 1 || projectNotes.Msg.GetNotes()[0].GetId() != projectNote.Msg.GetNote().GetId() {
		t.Fatalf("project notes after restart = %+v", projectNotes.Msg.GetNotes())
	}
}

func TestNoteServiceServesGRPCWeb(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := noteClient(server, connect.WithGRPCWeb())
	projectID := createNoteProject(t, server, token)

	day, err := client.CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
		Date: "2026-10-20",
		Text: "Day note over gRPC-Web.",
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateNote day: %v", err)
	}
	project, err := client.CreateNote(context.Background(), withBearer(&wdidv1.CreateNoteRequest{
		SubcategoryId: projectID,
		Text:          "Project note over gRPC-Web.",
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateNote project: %v", err)
	}

	updated, err := client.UpdateNote(context.Background(), withBearer(&wdidv1.UpdateNoteRequest{
		Id:   day.Msg.GetNote().GetId(),
		Date: "2026-10-20",
		Text: "Day note edited over gRPC-Web.",
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web UpdateNote: %v", err)
	}
	if updated.Msg.GetNote().GetText() != "Day note edited over gRPC-Web." {
		t.Fatalf("gRPC-Web update text = %q", updated.Msg.GetNote().GetText())
	}

	listed, err := client.ListNotes(context.Background(), withBearer(&wdidv1.ListNotesRequest{}, token))
	if err != nil {
		t.Fatalf("gRPC-Web ListNotes: %v", err)
	}
	if len(listed.Msg.GetNotes()) != 2 {
		t.Fatalf("gRPC-Web notes = %+v, want both contexts", listed.Msg.GetNotes())
	}

	if _, err := client.DeleteNote(context.Background(), withBearer(&wdidv1.DeleteNoteRequest{Id: project.Msg.GetNote().GetId()}, token)); err != nil {
		t.Fatalf("gRPC-Web DeleteNote: %v", err)
	}
}
