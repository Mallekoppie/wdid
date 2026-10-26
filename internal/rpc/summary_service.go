package rpc

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/ai"
	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
)

// SummaryService implements the generated SummaryService handler. Its period
// report is the single authoritative aggregate: clients render these numbers
// instead of recomputing totals from entry listings.
type SummaryService struct {
	store    *store.Store
	auth     *auth.Service
	now      func() time.Time
	provider ai.Provider
}

// SummaryServiceOption adjusts the service, which lets tests control the clock
// used to resolve "this week" and inject a fake AI provider.
type SummaryServiceOption func(*SummaryService)

// WithSummaryClock replaces the service's clock.
func WithSummaryClock(now func() time.Time) SummaryServiceOption {
	return func(service *SummaryService) {
		if now != nil {
			service.now = now
		}
	}
}

// WithSummaryProvider replaces the AI provider. Tests use a fake so no network
// call is made.
func WithSummaryProvider(provider ai.Provider) SummaryServiceOption {
	return func(service *SummaryService) {
		if provider != nil {
			service.provider = provider
		}
	}
}

// NewSummaryService builds the SummaryService implementation.
func NewSummaryService(database *store.Store, authService *auth.Service, options ...SummaryServiceOption) *SummaryService {
	service := &SummaryService{
		store:    database,
		auth:     authService,
		now:      time.Now,
		provider: ai.NewAnthropicProvider(nil),
	}
	for _, option := range options {
		option(service)
	}
	return service
}

// Register implements platform.ConnectService.
func (s *SummaryService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewSummaryServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// GetPeriodReport aggregates the caller's work for an inclusive range of local
// calendar dates. The dates are grouped in the user's configured timezone, so
// the report's boundaries and weekly rhythm always match the product's day
// boundaries. When current_week is set, the service resolves the period from
// the user's clock and week start instead.
func (s *SummaryService) GetPeriodReport(ctx context.Context, request *connect.Request[wdidv1.GetPeriodReportRequest]) (*connect.Response[wdidv1.GetPeriodReportResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	fromDate, toDate := request.Msg.GetFromDate(), request.Msg.GetToDate()
	if request.Msg.GetCurrentWeek() {
		// The server resolves "this week" from the user's timezone and week
		// start, so a device in another timezone cannot shift the period.
		fromDate, toDate, err = s.store.CurrentWeekRange(userID, s.now())
		if err != nil {
			return nil, toConnectError(err)
		}
	}

	report, err := s.store.PeriodReport(userID, fromDate, toDate)
	if err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.GetPeriodReportResponse{
		Report: toProtoPeriodReport(report),
	}), nil
}

// BuildExport renders the on-demand export bundle for a period or a saved
// check-in. The files are returned to the caller; nothing is written to the
// database directory or anywhere else on disk.
func (s *SummaryService) BuildExport(ctx context.Context, request *connect.Request[wdidv1.BuildExportRequest]) (*connect.Response[wdidv1.BuildExportResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	checkIn, fromDate, toDate, err := s.resolveExportScope(userID, request.Msg.GetCheckInId(), request.Msg.GetFromDate(), request.Msg.GetToDate())
	if err != nil {
		return nil, toConnectError(err)
	}
	input, err := s.exportInput(userID, fromDate, toDate, checkIn)
	if err != nil {
		return nil, toConnectError(err)
	}
	bundle, err := domain.BuildExportBundle(input)
	if err != nil {
		return nil, toConnectError(err)
	}

	files := make([]*wdidv1.ExportFile, 0, len(bundle.Files))
	for _, file := range bundle.Files {
		files = append(files, &wdidv1.ExportFile{Name: file.Name, Content: file.Content})
	}
	return connect.NewResponse(&wdidv1.BuildExportResponse{
		Directory: bundle.Directory,
		Files:     files,
	}), nil
}

// BuildPrompt returns the versioned instruction followed by the same
// summary.md the bundle carries. The template text is the one owned by the
// check-in prompt package, so this RPC never duplicates prompt copy.
func (s *SummaryService) BuildPrompt(ctx context.Context, request *connect.Request[wdidv1.BuildPromptRequest]) (*connect.Response[wdidv1.BuildPromptResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	checkIn, fromDate, toDate, err := s.resolveExportScope(userID, request.Msg.GetCheckInId(), request.Msg.GetFromDate(), request.Msg.GetToDate())
	if err != nil {
		return nil, toConnectError(err)
	}
	input, err := s.exportInput(userID, fromDate, toDate, checkIn)
	if err != nil {
		return nil, toConnectError(err)
	}

	promptCheckIn := domain.CheckIn{}
	switch request.Msg.GetVariant() {
	case wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_UNSPECIFIED:
		if checkIn != nil {
			promptCheckIn.Kind = checkIn.Kind
			promptCheckIn.Audience = checkIn.Audience
		} else {
			promptCheckIn.Kind = domain.CheckInKindManager
		}
	case wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE:
		promptCheckIn.Kind = domain.CheckInKindManager
	case wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW:
		promptCheckIn.Kind = domain.CheckInKindManager
		promptCheckIn.Audience = domain.AudiencePerformanceReview
	case wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW:
		promptCheckIn.Kind = domain.CheckInKindPersonal
	default:
		return nil, toConnectError(domain.ValidationError{
			Field:   "variant",
			Message: "must be a known prompt variant",
		})
	}
	promptCheckIn.SummaryMarkdown = domain.BuildExportSummary(input)

	return connect.NewResponse(&wdidv1.BuildPromptResponse{
		Prompt:        domain.BuildPrompt(promptCheckIn),
		PromptVersion: domain.PromptVersion,
		Variant:       toProtoPromptVariant(domain.PromptVariantFor(promptCheckIn)),
	}), nil
}

// GetPromptTemplate returns the versioned instruction alone. Settings → AI
// previews this text, so the client never duplicates prompt copy.
func (s *SummaryService) GetPromptTemplate(ctx context.Context, request *connect.Request[wdidv1.GetPromptTemplateRequest]) (*connect.Response[wdidv1.GetPromptTemplateResponse], error) {
	if _, err := userIDFromContext(ctx, s.auth); err != nil {
		return nil, toConnectError(err)
	}

	variant, err := promptVariantFromProto(request.Msg.GetVariant())
	if err != nil {
		return nil, toConnectError(err)
	}
	template, ok := domain.PromptTemplate(variant)
	if !ok {
		return nil, connect.NewError(connect.CodeInternal, errors.New("the prompt template is missing"))
	}

	return connect.NewResponse(&wdidv1.GetPromptTemplateResponse{
		Template:      template,
		PromptVersion: domain.PromptVersion,
		Variant:       toProtoPromptVariant(variant),
	}), nil
}

// GenerateSummary streams an Anthropic Messages provider's response into a
// check-in's summary. Deltas reach the client as they arrive; the stored
// summary, model name and prompt version are written only after the provider
// finishes successfully. A failure therefore leaves the existing summary
// untouched.
func (s *SummaryService) GenerateSummary(ctx context.Context, request *connect.Request[wdidv1.GenerateSummaryRequest], stream *connect.ServerStream[wdidv1.GenerateSummaryDelta]) error {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return toConnectError(err)
	}

	checkIn, err := s.store.CheckIn(userID, request.Msg.GetCheckInId())
	if err != nil {
		return toConnectError(err)
	}
	if checkIn.Kind == domain.CheckInKindManager && checkIn.State == domain.CheckInStateFinal {
		return connect.NewError(connect.CodeFailedPrecondition, errors.New("a final check-in is read-only"))
	}
	if checkIn.State == domain.CheckInStateEdited &&
		strings.TrimSpace(checkIn.SummaryMarkdown) != "" &&
		!request.Msg.GetOverwriteManualEdits() {
		return connect.NewError(connect.CodeFailedPrecondition, errors.New("the summary was edited by hand; confirm overwriting it"))
	}

	input, err := s.exportInput(userID, checkIn.PeriodStart, checkIn.PeriodEnd, &checkIn)
	if err != nil {
		return toConnectError(err)
	}
	apiKey := strings.TrimSpace(input.Settings.AIAPIKey)
	if apiKey == "" {
		return connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("no AI API key is configured; add your key in Settings → AI"),
		)
	}
	if input.Settings.AIRedact {
		input = domain.RedactExportInput(input)
	}
	baseURL, modelName := aiSettingsDefaults(input.Settings)

	// Only the selected period is sent. The prompt text comes from the same
	// versioned template the copy-prompt path uses.
	promptCheckIn := checkIn
	promptCheckIn.SummaryMarkdown = domain.BuildExportSummary(input)

	var generated strings.Builder
	response, err := s.provider.Stream(ctx, ai.Request{
		BaseURL: baseURL,
		APIKey:  apiKey,
		Model:   modelName,
		Prompt:  domain.BuildPrompt(promptCheckIn),
	}, func(delta string) error {
		generated.WriteString(delta)
		return stream.Send(&wdidv1.GenerateSummaryDelta{Text: delta})
	})
	if err != nil {
		return connect.NewError(
			connect.CodeUnavailable,
			fmt.Errorf("AI generation failed; the existing summary is unchanged: %w", err),
		)
	}

	summary := strings.TrimSpace(generated.String())
	if summary == "" {
		return connect.NewError(
			connect.CodeUnavailable,
			errors.New("the AI provider returned no text; the existing summary is unchanged"),
		)
	}

	model := strings.TrimSpace(response.Model)
	if model == "" {
		model = modelName
	}
	checkIn.SummaryMarkdown = summary
	checkIn.SummaryModel = model
	checkIn.PromptVersion = domain.PromptVersion
	checkIn.State = domain.CheckInStateGenerated
	checkIn.UpdatedAt = s.now().UTC()
	if err := s.store.SaveCheckIn(checkIn); err != nil {
		return toConnectError(err)
	}

	return stream.Send(&wdidv1.GenerateSummaryDelta{
		CheckIn:       toProtoCheckIn(checkIn),
		Model:         model,
		PromptVersion: domain.PromptVersion,
	})
}

// aiSettingsDefaults keeps generation usable when an account never opened
// Settings → AI and therefore has empty AI fields.
func aiSettingsDefaults(settings domain.Settings) (baseURL, model string) {
	defaults := domain.DefaultSettings(settings.UserID)
	baseURL = strings.TrimSpace(settings.AIBaseURL)
	if baseURL == "" {
		baseURL = defaults.AIBaseURL
	}
	model = strings.TrimSpace(settings.AIModel)
	if model == "" {
		model = defaults.AIModel
	}
	return baseURL, model
}

func promptVariantFromProto(value wdidv1.CheckInPromptVariant) (domain.PromptVariant, error) {
	switch value {
	case wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_UNSPECIFIED:
		return domain.PromptVariantManagerOneOnOne, nil
	case wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE:
		return domain.PromptVariantManagerOneOnOne, nil
	case wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW:
		return domain.PromptVariantManagerPerformanceReview, nil
	case wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW:
		return domain.PromptVariantPersonalReview, nil
	default:
		return "", domain.ValidationError{Field: "variant", Message: "must be a known prompt variant"}
	}
}

// resolveExportScope turns either a check-in id or an explicit period into the
// dates the bundle covers. A check-in's stored period always wins so the
// bundle cannot disagree with the artifact it belongs to.
func (s *SummaryService) resolveExportScope(userID, checkInID, fromDate, toDate string) (*domain.CheckIn, string, string, error) {
	if checkInID == "" {
		return nil, fromDate, toDate, nil
	}
	checkIn, err := s.store.CheckIn(userID, checkInID)
	if err != nil {
		return nil, "", "", err
	}
	return &checkIn, checkIn.PeriodStart, checkIn.PeriodEnd, nil
}

// exportInput gathers one consistent view of the scoped period. Aggregates come
// from the authoritative report; the raw rows supply the CSV sheets and the
// structured payload. Every read happens inside one store transaction so the
// report, rows, taxonomy, milestones, check-ins and settings cannot disagree.
func (s *SummaryService) exportInput(userID, fromDate, toDate string, checkIn *domain.CheckIn) (domain.ExportInput, error) {
	checkInID := ""
	if checkIn != nil {
		checkInID = checkIn.ID
	}
	snapshot, err := s.store.ExportSnapshot(userID, fromDate, toDate, checkInID)
	if err != nil {
		return domain.ExportInput{}, err
	}

	var checkIns []domain.CheckIn
	focusNotes := ""
	if checkIn != nil {
		scoped := snapshot.ScopedCheckIn
		if scoped == nil || scoped.ID != checkIn.ID {
			return domain.ExportInput{}, store.ErrNotFound
		}
		checkIns = []domain.CheckIn{*scoped}
		focusNotes = scoped.FocusNotes
	} else {
		checkIns = checkInsInPeriod(snapshot.CheckIns, snapshot.Report.FromDate, snapshot.Report.ToDate)
	}

	return domain.ExportInput{
		Report:        snapshot.Report,
		Entries:       snapshot.Entries,
		Categories:    snapshot.Categories,
		Subcategories: snapshot.Subcategories,
		Milestones:    snapshot.Milestones,
		CheckIns:      checkIns,
		Settings:      snapshot.Settings,
		FocusNotes:    focusNotes,
		GeneratedAt:   s.now().UTC(),
	}, nil
}

// checkInsInPeriod keeps the check-ins that overlap the bundle period.
func checkInsInPeriod(checkIns []domain.CheckIn, fromDate, toDate string) []domain.CheckIn {
	result := make([]domain.CheckIn, 0)
	for _, checkIn := range checkIns {
		if checkIn.PeriodEnd < fromDate || checkIn.PeriodStart > toDate {
			continue
		}
		result = append(result, checkIn)
	}
	return result
}

func toProtoPeriodReport(report domain.PeriodReport) *wdidv1.PeriodReport {
	response := &wdidv1.PeriodReport{
		FromDate:            report.FromDate,
		ToDate:              report.ToDate,
		Total:               minutesDuration(report.TotalMinutes),
		EntryCount:          int32(report.EntryCount),
		SupportDuration:     minutesDuration(report.SupportMinutes),
		SupportInteractions: int32(report.SupportInteractions),
		Categories:          make([]*wdidv1.CategoryAllocation, 0, len(report.Categories)),
		Subcategories:       make([]*wdidv1.SubcategoryAllocation, 0, len(report.Subcategories)),
		SupportPeople:       make([]*wdidv1.SupportPersonAllocation, 0, len(report.SupportPeople)),
		SupportModes:        make([]*wdidv1.SupportModeAllocation, 0, len(report.SupportModes)),
		Weeks:               make([]*wdidv1.WeekRhythm, 0, len(report.Weeks)),
		Notes:               make([]*wdidv1.PeriodNote, 0, len(report.Notes)),
		MilestoneProgress: make(
			[]*wdidv1.MilestoneProgress, 0, len(report.Milestones),
		),
	}

	for _, total := range report.Categories {
		response.Categories = append(response.Categories, &wdidv1.CategoryAllocation{
			CategoryId: total.CategoryID,
			Name:       total.Name,
			Role:       toProtoCategoryRole(total.Role),
			Duration:   minutesDuration(total.Minutes),
			EntryCount: int32(total.EntryCount),
		})
	}
	for _, total := range report.Subcategories {
		response.Subcategories = append(response.Subcategories, &wdidv1.SubcategoryAllocation{
			SubcategoryId:           total.SubcategoryID,
			CategoryId:              total.CategoryID,
			Name:                    total.Name,
			Duration:                minutesDuration(total.Minutes),
			EntryCount:              int32(total.EntryCount),
			LastActivityDate:        total.LastActivityDate,
			LastActivityDescription: total.LastActivityDescription,
		})
	}
	for _, total := range report.SupportPeople {
		response.SupportPeople = append(response.SupportPeople, &wdidv1.SupportPersonAllocation{
			Person:       total.Person,
			Duration:     minutesDuration(total.Minutes),
			Interactions: int32(total.Interactions),
		})
	}
	for _, total := range report.SupportModes {
		response.SupportModes = append(response.SupportModes, &wdidv1.SupportModeAllocation{
			SubcategoryId: total.SubcategoryID,
			Name:          total.Name,
			Duration:      minutesDuration(total.Minutes),
			Interactions:  int32(total.Interactions),
		})
	}
	for _, week := range report.Weeks {
		response.Weeks = append(response.Weeks, &wdidv1.WeekRhythm{
			WeekStartDate:   week.WeekStartDate,
			Duration:        minutesDuration(week.Minutes),
			TopCategoryId:   week.TopCategoryID,
			TopCategoryName: week.TopCategoryName,
		})
	}
	for _, note := range report.Notes {
		response.Notes = append(response.Notes, &wdidv1.PeriodNote{
			Id:            note.ID,
			Date:          note.Date,
			SubcategoryId: note.SubcategoryID,
			Text:          note.Text,
			CreatedAt:     timestamppb.New(note.CreatedAt),
		})
	}
	for _, progress := range report.Milestones {
		response.MilestoneProgress = append(response.MilestoneProgress, &wdidv1.MilestoneProgress{
			SubcategoryId: progress.SubcategoryID,
			Total:         int32(progress.Total),
			Done:          int32(progress.Done),
		})
	}

	return response
}
