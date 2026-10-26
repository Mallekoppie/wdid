package rpc_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"
	"github.com/Mallekoppie/goslow/platform"
	"google.golang.org/genproto/googleapis/rpc/errdetails"
	"google.golang.org/protobuf/types/known/durationpb"

	"github.com/Mallekoppie/wdid/internal/ai"
	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/backup"
	"github.com/Mallekoppie/wdid/internal/config"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/rpc"
	"github.com/Mallekoppie/wdid/internal/store"
)

// newDomainHandlerForConfig builds an application handler with every service
// that owns a user's data core. Tests use it to exercise the public Connect
// surface exactly as the browser does.
func newDomainHandlerForConfig(t *testing.T, cfg config.Config) (http.Handler, *store.Store) {
	t.Helper()
	return newDomainHandlerWithTimerClock(t, cfg, nil)
}

// newDomainHandlerWithTimerClock lets a test control the timer's clock through
// the public RPC surface.
func newDomainHandlerWithTimerClock(t *testing.T, cfg config.Config, now func() time.Time) (http.Handler, *store.Store) {
	t.Helper()
	return newDomainHandlerWithClocks(t, cfg, now, nil, nil)
}

// newDomainHandlerWithClocks controls the timer, summary and check-in clocks,
// so tests can pin the meaning of "now" for every server-owned lifecycle.
func newDomainHandlerWithClocks(t *testing.T, cfg config.Config, timerNow, summaryNow, checkInNow func() time.Time) (http.Handler, *store.Store) {
	t.Helper()
	return newDomainHandlerWithSummaryOptions(t, cfg, timerNow, summaryNow, checkInNow)
}

// newDomainHandlerWithSummaryOptions also accepts summary options, which lets a
// test inject a fake AI provider and key without reaching the network.
func newDomainHandlerWithSummaryOptions(t *testing.T, cfg config.Config, timerNow, summaryNow, checkInNow func() time.Time, extraSummary ...rpc.SummaryServiceOption) (http.Handler, *store.Store) {
	t.Helper()

	database, err := store.Open(cfg)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		_ = database.Close()
	})

	timerOptions := make([]rpc.TimerServiceOption, 0, 1)
	if timerNow != nil {
		timerOptions = append(timerOptions, rpc.WithTimerClock(timerNow))
	}
	summaryOptions := make([]rpc.SummaryServiceOption, 0, 1+len(extraSummary))
	if summaryNow != nil {
		summaryOptions = append(summaryOptions, rpc.WithSummaryClock(summaryNow))
	}
	summaryOptions = append(summaryOptions, extraSummary...)
	checkInOptions := make([]rpc.CheckInServiceOption, 0, 1)
	if checkInNow != nil {
		checkInOptions = append(checkInOptions, rpc.WithCheckInClock(checkInNow))
	}

	authService := auth.NewService(database, cfg)
	backupManager := backup.New(database, backup.Config{
		Dir: filepath.Join(filepath.Dir(cfg.DBPath), "backups"),
	})
	application, err := platform.NewApplicationHandler(platform.ApplicationServerOptions{
		Services: []platform.ConnectService{
			rpc.NewAuthService(database, authService, cfg),
			rpc.NewCategoryService(database, authService),
			rpc.NewEntryService(database, authService),
			rpc.NewTimerService(database, authService, timerOptions...),
			rpc.NewSettingsService(database, authService, rpc.WithBackupManager(backupManager)),
			rpc.NewSummaryService(database, authService, summaryOptions...),
			rpc.NewNoteService(database, authService),
			rpc.NewMilestoneService(database, authService),
			rpc.NewCheckInService(database, authService, checkInOptions...),
		},
		ServiceNames: []string{
			config.AuthServiceName,
			config.CategoryServiceName,
			config.EntryServiceName,
			config.TimerServiceName,
			config.SettingsServiceName,
			config.SummaryServiceName,
			config.NoteServiceName,
			config.MilestoneServiceName,
			config.CheckInServiceName,
		},
	})
	if err != nil {
		t.Fatalf("build application handler: %v", err)
	}
	return application, database
}

func newDomainServer(t *testing.T) (*httptest.Server, *store.Store) {
	t.Helper()
	return newDomainServerWithConfig(t, testConfig(t))
}

func newDomainServerWithConfig(t *testing.T, cfg config.Config) (*httptest.Server, *store.Store) {
	t.Helper()

	handler, database := newDomainHandlerForConfig(t, cfg)
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return server, database
}

func newDomainServerWithClock(t *testing.T, now func() time.Time) (*httptest.Server, *store.Store) {
	t.Helper()

	handler, database := newDomainHandlerWithTimerClock(t, testConfig(t), now)
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return server, database
}

func newDomainServerWithSummaryClock(t *testing.T, now func() time.Time) (*httptest.Server, *store.Store) {
	t.Helper()

	handler, database := newDomainHandlerWithClocks(t, testConfig(t), nil, now, nil)
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return server, database
}

func newDomainServerWithCheckInClock(t *testing.T, now func() time.Time) (*httptest.Server, *store.Store) {
	t.Helper()

	handler, database := newDomainHandlerWithClocks(t, testConfig(t), nil, nil, now)
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return server, database
}

// newDomainServerWithAI injects a fake provider. The provider key comes from
// the user's settings record, exactly as in production; no test reaches a real
// provider endpoint.
func newDomainServerWithAI(t *testing.T, provider ai.Provider) (*httptest.Server, *store.Store) {
	t.Helper()

	handler, database := newDomainHandlerWithSummaryOptions(
		t,
		testConfig(t),
		nil,
		nil,
		nil,
		rpc.WithSummaryProvider(provider),
	)
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return server, database
}

// setAIKey stores the caller's provider key through the public settings RPC.
func setAIKey(t *testing.T, server *httptest.Server, token, apiKey string) {
	t.Helper()

	if _, err := settingsClient(server).SetAIApiKey(context.Background(), withBearer(&wdidv1.SetAIApiKeyRequest{
		ApiKey: apiKey,
	}, token)); err != nil {
		t.Fatalf("set AI key: %v", err)
	}
}

func categoryClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.CategoryServiceClient {
	return wdidv1connect.NewCategoryServiceClient(server.Client(), server.URL, options...)
}

func settingsClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.SettingsServiceClient {
	return wdidv1connect.NewSettingsServiceClient(server.Client(), server.URL, options...)
}

// bootstrapToken creates the first account and returns its bearer token.
func bootstrapToken(t *testing.T, server *httptest.Server) string {
	t.Helper()
	return registerBootstrap(t, authClient(server)).GetToken()
}

var fieldPattern = regexp.MustCompile(`(?:^|: )([A-Za-z][A-Za-z0-9]*): `)

var connectCodes = map[string]bool{
	"invalid_argument":    true,
	"failed_precondition": true,
	"not_found":           true,
	"unauthenticated":     true,
	"permission_denied":   true,
	"internal":            true,
}

func minutes(value int) *durationpb.Duration {
	return durationpb.New(time.Duration(value) * time.Minute)
}

func fieldViolations(t *testing.T, err error) []string {
	t.Helper()

	var connectErr *connect.Error
	if !errors.As(err, &connectErr) {
		t.Fatalf("error = %v, want a connect error", err)
	}
	var fields []string
	for _, detail := range connectErr.Details() {
		value, detailErr := detail.Value()
		if detailErr != nil {
			continue
		}
		badRequest, ok := value.(*errdetails.BadRequest)
		if !ok {
			continue
		}
		for _, violation := range badRequest.GetFieldViolations() {
			fields = append(fields, violation.GetField())
		}
	}
	if len(fields) > 0 {
		return fields
	}

	// goslow's request-id interceptor re-wraps Connect errors, which drops the
	// typed BadRequest detail. The field still reaches every client in the
	// message ("<field>: <reason>"), so assert the wire-observable form too.
	for _, match := range fieldPattern.FindAllStringSubmatch(connectErr.Message(), -1) {
		if !connectCodes[match[1]] {
			fields = append(fields, match[1])
		}
	}
	return fields
}

func TestCategoryServiceRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)

	_, err := categoryClient(server).ListCategories(context.Background(), connect.NewRequest(&wdidv1.ListCategoriesRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

func TestCategoryServiceListsSeededTaxonomy(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := categoryClient(server)

	response, err := client.ListCategories(context.Background(), withBearer(&wdidv1.ListCategoriesRequest{}, token))
	if err != nil {
		t.Fatalf("list categories: %v", err)
	}

	roles := map[wdidv1.CategoryRole]bool{}
	for _, category := range response.Msg.GetCategories() {
		roles[category.GetRole()] = true
	}
	for _, role := range []wdidv1.CategoryRole{
		wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
		wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT,
		wdidv1.CategoryRole_CATEGORY_ROLE_OTHER,
	} {
		if !roles[role] {
			t.Fatalf("seeded categories = %v, want role %v", response.Msg.GetCategories(), role)
		}
	}
}

func TestCategoryServiceCreatesAndRenamesWithoutChangingRole(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := categoryClient(server)

	created, err := client.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name:      "  Deep work  ",
		Role:      wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT,
		Color:     "#00696D",
		SortOrder: 7,
	}, token))
	if err != nil {
		t.Fatalf("create category: %v", err)
	}
	category := created.Msg.GetCategory()
	if category.GetId() == "" {
		t.Fatal("created category has no id")
	}
	if category.GetName() != "Deep work" {
		t.Fatalf("name = %q, want trimmed name", category.GetName())
	}
	if category.GetRole() != wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT {
		t.Fatalf("role = %v, want support", category.GetRole())
	}

	updated, err := client.UpdateCategory(context.Background(), withBearer(&wdidv1.UpdateCategoryRequest{
		Id:        category.GetId(),
		Name:      "Deep support",
		Color:     "#112233",
		SortOrder: 8,
	}, token))
	if err != nil {
		t.Fatalf("update category: %v", err)
	}
	if updated.Msg.GetCategory().GetName() != "Deep support" {
		t.Fatalf("updated name = %q", updated.Msg.GetCategory().GetName())
	}
	if updated.Msg.GetCategory().GetRole() != wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT {
		t.Fatalf("updated role = %v, want the creation role", updated.Msg.GetCategory().GetRole())
	}
}

func TestCategoryServiceRejectsInvalidCategory(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := categoryClient(server)

	_, err := client.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "No role",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "role" {
		t.Fatalf("field violations = %v, want role", fields)
	}

	_, err = client.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name:  "Bad colour",
		Role:  wdidv1.CategoryRole_CATEGORY_ROLE_OTHER,
		Color: "teal",
	}, token))
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "color" {
		t.Fatalf("field violations = %v, want color", fields)
	}
}

func TestCategoryServiceManagesSubcategories(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := categoryClient(server)

	categoryResponse, err := client.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Initiatives",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
	}, token))
	if err != nil {
		t.Fatalf("create category: %v", err)
	}
	categoryID := categoryResponse.Msg.GetCategory().GetId()

	created, err := client.CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: categoryID,
		Name:       "Billing migration",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
		Progress:   25,
		Links:      []*wdidv1.Link{{Label: "Epic", Url: "https://example.com/epic"}},
	}, token))
	if err != nil {
		t.Fatalf("create subcategory: %v", err)
	}
	subcategory := created.Msg.GetSubcategory()
	if subcategory.GetCategoryId() != categoryID || subcategory.GetProgress() != 25 {
		t.Fatalf("subcategory = %+v", subcategory)
	}
	if len(subcategory.GetLinks()) != 1 || subcategory.GetLinks()[0].GetLabel() != "Epic" {
		t.Fatalf("links = %+v, want the saved link", subcategory.GetLinks())
	}

	updated, err := client.UpdateSubcategory(context.Background(), withBearer(&wdidv1.UpdateSubcategoryRequest{
		Id:       subcategory.GetId(),
		Name:     "Billing migration v2",
		Status:   wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_BLOCKED,
		Progress: 60,
	}, token))
	if err != nil {
		t.Fatalf("update subcategory: %v", err)
	}
	if updated.Msg.GetSubcategory().GetName() != "Billing migration v2" {
		t.Fatalf("updated name = %q", updated.Msg.GetSubcategory().GetName())
	}

	archived, err := client.ArchiveSubcategory(context.Background(), withBearer(&wdidv1.ArchiveSubcategoryRequest{
		Id:       subcategory.GetId(),
		Archived: true,
	}, token))
	if err != nil {
		t.Fatalf("archive subcategory: %v", err)
	}
	if !archived.Msg.GetSubcategory().GetArchived() {
		t.Fatal("subcategory was not archived")
	}

	listed, err := client.ListSubcategories(context.Background(), withBearer(&wdidv1.ListSubcategoriesRequest{
		CategoryId: categoryID,
	}, token))
	if err != nil {
		t.Fatalf("list subcategories: %v", err)
	}
	if len(listed.Msg.GetSubcategories()) != 1 || listed.Msg.GetSubcategories()[0].GetArchived() != true {
		t.Fatalf("subcategories = %+v, want the archived subcategory", listed.Msg.GetSubcategories())
	}
}

func TestCategoryServiceArchivesReferencedRecordsInsteadOfDeleting(t *testing.T) {
	server, database := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := categoryClient(server)

	categoryResponse, err := client.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Initiatives",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE,
	}, token))
	if err != nil {
		t.Fatalf("create category: %v", err)
	}
	category := categoryResponse.Msg.GetCategory()

	subcategoryResponse, err := client.CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: category.GetId(),
		Name:       "Billing migration",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("create subcategory: %v", err)
	}
	subcategory := subcategoryResponse.Msg.GetSubcategory()

	user, err := database.UserByEmail("admin@example.com")
	if err != nil {
		t.Fatalf("read user: %v", err)
	}
	started := time.Now().UTC().Add(-time.Hour)
	entry := domain.WorkEntry{
		ID:            domain.NewID(),
		UserID:        user.ID,
		CategoryID:    category.GetId(),
		SubcategoryID: subcategory.GetId(),
		Description:   "Billing backfill",
		StartedAt:     started,
		EndedAt:       started.Add(45 * time.Minute),
		Minutes:       45,
		Source:        domain.EntrySourceManual,
		CreatedAt:     started,
		UpdatedAt:     started,
	}
	if err := database.SaveWorkEntry(entry); err != nil {
		t.Fatalf("save referencing entry: %v", err)
	}

	_, err = client.DeleteCategory(context.Background(), withBearer(&wdidv1.DeleteCategoryRequest{Id: category.GetId()}, token))
	if connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("delete referenced category code = %v, want failed precondition", connect.CodeOf(err))
	}
	_, err = client.DeleteSubcategory(context.Background(), withBearer(&wdidv1.DeleteSubcategoryRequest{Id: subcategory.GetId()}, token))
	if connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("delete referenced subcategory code = %v, want failed precondition", connect.CodeOf(err))
	}

	archived, err := client.ArchiveCategory(context.Background(), withBearer(&wdidv1.ArchiveCategoryRequest{
		Id:       category.GetId(),
		Archived: true,
	}, token))
	if err != nil {
		t.Fatalf("archive referenced category: %v", err)
	}
	if !archived.Msg.GetCategory().GetArchived() {
		t.Fatal("category was not archived")
	}

	// An unreferenced category can still be deleted.
	unused, err := client.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Temporary",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_OTHER,
	}, token))
	if err != nil {
		t.Fatalf("create unused category: %v", err)
	}
	if _, err := client.DeleteCategory(context.Background(), withBearer(&wdidv1.DeleteCategoryRequest{Id: unused.Msg.GetCategory().GetId()}, token)); err != nil {
		t.Fatalf("delete unused category: %v", err)
	}
}

func TestCategoryServiceIsolatesAccounts(t *testing.T) {
	server, database := newDomainServer(t)
	firstToken := bootstrapToken(t, server)
	client := categoryClient(server)

	created, err := client.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Private",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_OTHER,
	}, firstToken))
	if err != nil {
		t.Fatalf("create category: %v", err)
	}
	categoryID := created.Msg.GetCategory().GetId()

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

	_, err = client.UpdateCategory(context.Background(), withBearer(&wdidv1.UpdateCategoryRequest{
		Id:   categoryID,
		Name: "Hijacked",
	}, secondToken))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("cross-user update code = %v, want not found", connect.CodeOf(err))
	}

	_, err = client.ArchiveCategory(context.Background(), withBearer(&wdidv1.ArchiveCategoryRequest{Id: categoryID, Archived: true}, secondToken))
	if connect.CodeOf(err) != connect.CodeNotFound {
		t.Fatalf("cross-user archive code = %v, want not found", connect.CodeOf(err))
	}

	listed, err := client.ListCategories(context.Background(), withBearer(&wdidv1.ListCategoriesRequest{}, secondToken))
	if err != nil {
		t.Fatalf("list second account categories: %v", err)
	}
	for _, category := range listed.Msg.GetCategories() {
		if category.GetId() == categoryID {
			t.Fatalf("second account saw %q", category.GetName())
		}
	}
}

func TestCategoryServiceServesGRPCWeb(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := categoryClient(server, connect.WithGRPCWeb())

	response, err := client.ListCategories(context.Background(), withBearer(&wdidv1.ListCategoriesRequest{}, token))
	if err != nil {
		t.Fatalf("gRPC-Web ListCategories: %v", err)
	}
	if len(response.Msg.GetCategories()) == 0 {
		t.Fatal("gRPC-Web response returned no categories")
	}

	created, err := client.CreateCategory(context.Background(), withBearer(&wdidv1.CreateCategoryRequest{
		Name: "Web category",
		Role: wdidv1.CategoryRole_CATEGORY_ROLE_OTHER,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateCategory: %v", err)
	}

	renamed, err := client.UpdateCategory(context.Background(), withBearer(&wdidv1.UpdateCategoryRequest{
		Id:   created.Msg.GetCategory().GetId(),
		Name: "Web category renamed",
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web UpdateCategory: %v", err)
	}
	if renamed.Msg.GetCategory().GetName() != "Web category renamed" {
		t.Fatalf("gRPC-Web rename = %q", renamed.Msg.GetCategory().GetName())
	}

	archived, err := client.ArchiveCategory(context.Background(), withBearer(&wdidv1.ArchiveCategoryRequest{
		Id:       created.Msg.GetCategory().GetId(),
		Archived: true,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web ArchiveCategory: %v", err)
	}
	if !archived.Msg.GetCategory().GetArchived() {
		t.Fatal("gRPC-Web archive did not set the flag")
	}

	subcategory, err := client.CreateSubcategory(context.Background(), withBearer(&wdidv1.CreateSubcategoryRequest{
		CategoryId: created.Msg.GetCategory().GetId(),
		Name:       "Web subcategory",
		Status:     wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web CreateSubcategory: %v", err)
	}
	renamedSubcategory, err := client.UpdateSubcategory(context.Background(), withBearer(&wdidv1.UpdateSubcategoryRequest{
		Id:     subcategory.Msg.GetSubcategory().GetId(),
		Name:   "Web subcategory renamed",
		Status: wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_BLOCKED,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web UpdateSubcategory: %v", err)
	}
	if renamedSubcategory.Msg.GetSubcategory().GetName() != "Web subcategory renamed" {
		t.Fatalf("gRPC-Web subcategory rename = %q", renamedSubcategory.Msg.GetSubcategory().GetName())
	}
	archivedSubcategory, err := client.ArchiveSubcategory(context.Background(), withBearer(&wdidv1.ArchiveSubcategoryRequest{
		Id:       subcategory.Msg.GetSubcategory().GetId(),
		Archived: true,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web ArchiveSubcategory: %v", err)
	}
	if !archivedSubcategory.Msg.GetSubcategory().GetArchived() {
		t.Fatal("gRPC-Web subcategory archive did not set the flag")
	}

	if _, err := client.DeleteCategory(context.Background(), withBearer(&wdidv1.DeleteCategoryRequest{
		Id: created.Msg.GetCategory().GetId(),
	}, token)); err != nil {
		t.Fatalf("gRPC-Web DeleteCategory: %v", err)
	}
}

func TestCategoryServicePaginatesLists(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := categoryClient(server)

	var categories []*wdidv1.Category
	pageToken := ""
	for {
		response, err := client.ListCategories(context.Background(), withBearer(&wdidv1.ListCategoriesRequest{
			PageSize:  1,
			PageToken: pageToken,
		}, token))
		if err != nil {
			t.Fatalf("list categories page: %v", err)
		}
		if len(response.Msg.GetCategories()) > 1 {
			t.Fatalf("page returned %d categories, want at most 1", len(response.Msg.GetCategories()))
		}
		categories = append(categories, response.Msg.GetCategories()...)
		pageToken = response.Msg.GetNextPageToken()
		if pageToken == "" {
			break
		}
	}
	if len(categories) != 3 {
		t.Fatalf("paged categories = %d, want the three seeded categories", len(categories))
	}

	_, err := client.ListCategories(context.Background(), withBearer(&wdidv1.ListCategoriesRequest{
		PageToken: "not-a-number",
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("invalid page token code = %v, want invalid argument", connect.CodeOf(err))
	}
}

func TestSettingsServiceRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)

	_, err := settingsClient(server).GetSettings(context.Background(), connect.NewRequest(&wdidv1.GetSettingsRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

func TestSettingsServiceReturnsDefaultsAndAbout(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)

	response, err := settingsClient(server).GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, token))
	if err != nil {
		t.Fatalf("get settings: %v", err)
	}
	settings := response.Msg.GetSettings()
	if settings.GetTimezone() != "UTC" || settings.GetWeekStart() != 1 {
		t.Fatalf("settings = %+v, want UTC and Monday", settings)
	}
	if settings.GetDailyTarget().AsDuration().Minutes() != 450 || settings.GetDefaultEntryDuration().AsDuration().Minutes() != 30 {
		t.Fatalf("settings = %+v, want the seeded targets", settings)
	}
	if settings.GetTheme() != wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM {
		t.Fatalf("theme = %v, want system", settings.GetTheme())
	}
	about := response.Msg.GetAbout()
	if about.GetVersion() == "" || about.GetSchemaVersion() != 1 || about.GetLicense() == "" {
		t.Fatalf("about = %+v, want version, schema 1, license", about)
	}
}

func TestSettingsServiceUpdatesAndPersists(t *testing.T) {
	cfg := testConfig(t)
	server, database := newDomainServerWithConfig(t, cfg)
	token := bootstrapToken(t, server)
	client := settingsClient(server)

	update := func(client wdidv1connect.SettingsServiceClient, token string) *wdidv1.Settings {
		t.Helper()
		response, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
			Settings: &wdidv1.Settings{
				Timezone:             "Europe/Amsterdam",
				WeekStart:            4,
				DailyTarget:          minutes(360),
				ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_WEEKLY,
				LongTimerThreshold:   minutes(180),
				DefaultEntryDuration: minutes(45),
				BackupInterval:       minutes(360),
				BackupRetention:      30,
				Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_DARK,
				Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMPACT,
			},
		}, token))
		if err != nil {
			t.Fatalf("update settings: %v", err)
		}
		return response.Msg.GetSettings()
	}

	settings := update(client, token)
	if settings.GetTimezone() != "Europe/Amsterdam" || settings.GetWeekStart() != 4 {
		t.Fatalf("settings = %+v, want the updated time settings", settings)
	}
	if settings.GetTheme() != wdidv1.ThemePreference_THEME_PREFERENCE_DARK ||
		settings.GetDensity() != wdidv1.DensityPreference_DENSITY_PREFERENCE_COMPACT {
		t.Fatalf("settings = %+v, want the updated appearance", settings)
	}
	if settings.GetReviewCadence() != wdidv1.ReviewCadence_REVIEW_CADENCE_WEEKLY {
		t.Fatalf("review cadence = %v, want weekly", settings.GetReviewCadence())
	}

	// Restart the service on the same database and read the same account back.
	if err := database.Close(); err != nil {
		t.Fatalf("close database: %v", err)
	}
	restarted, _ := newDomainServerWithConfig(t, cfg)
	response, err := settingsClient(restarted).GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, token))
	if err != nil {
		t.Fatalf("get settings after restart: %v", err)
	}
	if response.Msg.GetSettings().GetTimezone() != "Europe/Amsterdam" ||
		response.Msg.GetSettings().GetTheme() != wdidv1.ThemePreference_THEME_PREFERENCE_DARK {
		t.Fatalf("settings after restart = %+v, want persisted values", response.Msg.GetSettings())
	}
}

func TestSettingsServiceRejectsInvalidValues(t *testing.T) {
	server, _ := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := settingsClient(server)

	valid := func() *wdidv1.Settings {
		return &wdidv1.Settings{
			Timezone:             "UTC",
			WeekStart:            1,
			DailyTarget:          minutes(450),
			ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_OFF,
			LongTimerThreshold:   minutes(240),
			DefaultEntryDuration: minutes(30),
			BackupInterval:       minutes(360),
			BackupRetention:      30,
			Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM,
			Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMFORTABLE,
		}
	}

	cases := []struct {
		name   string
		mutate func(*wdidv1.Settings)
		field  string
	}{
		{"unspecified theme", func(s *wdidv1.Settings) { s.Theme = wdidv1.ThemePreference_THEME_PREFERENCE_UNSPECIFIED }, "theme"},
		{"unspecified cadence", func(s *wdidv1.Settings) { s.ReviewCadence = wdidv1.ReviewCadence_REVIEW_CADENCE_UNSPECIFIED }, "reviewCadence"},
		{"bad week start", func(s *wdidv1.Settings) { s.WeekStart = 9 }, "weekStart"},
		{"target out of range", func(s *wdidv1.Settings) { s.DailyTarget = minutes(2000) }, "dailyTargetMinutes"},
		{"bad timezone", func(s *wdidv1.Settings) { s.Timezone = "Mars/Olympus" }, "timezone"},
		{"zero long timer", func(s *wdidv1.Settings) { s.LongTimerThreshold = minutes(0) }, "longTimerMinutes"},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			input := valid()
			testCase.mutate(input)
			_, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{Settings: input}, token))
			if connect.CodeOf(err) != connect.CodeInvalidArgument {
				t.Fatalf("code = %v, want invalid argument", connect.CodeOf(err))
			}
			if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != testCase.field {
				t.Fatalf("field violations = %v, want %s", fields, testCase.field)
			}
		})
	}
}

func TestSettingsServiceIsolatesAccounts(t *testing.T) {
	server, database := newDomainServer(t)
	firstToken := bootstrapToken(t, server)

	_, err := settingsClient(server).UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: &wdidv1.Settings{
			Timezone:             "Europe/Amsterdam",
			WeekStart:            1,
			DailyTarget:          minutes(480),
			ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_MONTHLY,
			LongTimerThreshold:   minutes(120),
			DefaultEntryDuration: minutes(15),
			BackupInterval:       minutes(360),
			BackupRetention:      30,
			Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_DARK,
			Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMPACT,
		},
	}, firstToken))
	if err != nil {
		t.Fatalf("update first account settings: %v", err)
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

	response, err := settingsClient(server).GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, second.Msg.GetToken()))
	if err != nil {
		t.Fatalf("get second account settings: %v", err)
	}
	if response.Msg.GetSettings().GetTimezone() != "UTC" ||
		response.Msg.GetSettings().GetTheme() != wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM {
		t.Fatalf("second account settings = %+v, want its own defaults", response.Msg.GetSettings())
	}
}

func TestSettingsServiceServesGRPCWeb(t *testing.T) {
	server, database := newDomainServer(t)
	token := bootstrapToken(t, server)
	client := settingsClient(server, connect.WithGRPCWeb())

	response, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, token))
	if err != nil {
		t.Fatalf("gRPC-Web GetSettings: %v", err)
	}
	if !strings.EqualFold(response.Msg.GetSettings().GetTimezone(), "UTC") {
		t.Fatalf("timezone = %q, want UTC", response.Msg.GetSettings().GetTimezone())
	}

	updated, err := client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: &wdidv1.Settings{
			Timezone:             "Europe/Amsterdam",
			WeekStart:            1,
			DailyTarget:          minutes(450),
			ReviewCadence:        wdidv1.ReviewCadence_REVIEW_CADENCE_MONTHLY,
			LongTimerThreshold:   minutes(240),
			DefaultEntryDuration: minutes(30),
			BackupInterval:       minutes(360),
			BackupRetention:      30,
			Theme:                wdidv1.ThemePreference_THEME_PREFERENCE_LIGHT,
			Density:              wdidv1.DensityPreference_DENSITY_PREFERENCE_COMPACT,
		},
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web UpdateSettings: %v", err)
	}
	if updated.Msg.GetSettings().GetTimezone() != "Europe/Amsterdam" ||
		updated.Msg.GetSettings().GetTheme() != wdidv1.ThemePreference_THEME_PREFERENCE_LIGHT {
		t.Fatalf("gRPC-Web update = %+v", updated.Msg.GetSettings())
	}

	invalid := updated.Msg.GetSettings()
	invalid.Theme = wdidv1.ThemePreference_THEME_PREFERENCE_UNSPECIFIED
	_, err = client.UpdateSettings(context.Background(), withBearer(&wdidv1.UpdateSettingsRequest{
		Settings: invalid,
	}, token))
	if connect.CodeOf(err) != connect.CodeInvalidArgument {
		t.Fatalf("gRPC-Web validation code = %v, want invalid argument", connect.CodeOf(err))
	}
	if fields := fieldViolations(t, err); len(fields) != 1 || fields[0] != "theme" {
		t.Fatalf("gRPC-Web field violations = %v, want theme", fields)
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
	secondSettings, err := client.GetSettings(context.Background(), withBearer(&wdidv1.GetSettingsRequest{}, second.Msg.GetToken()))
	if err != nil {
		t.Fatalf("gRPC-Web second-account settings: %v", err)
	}
	if secondSettings.Msg.GetSettings().GetTimezone() != "UTC" ||
		secondSettings.Msg.GetSettings().GetTheme() != wdidv1.ThemePreference_THEME_PREFERENCE_SYSTEM {
		t.Fatalf("gRPC-Web second account = %+v, want its own defaults", secondSettings.Msg.GetSettings())
	}
}
