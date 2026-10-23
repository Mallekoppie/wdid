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
