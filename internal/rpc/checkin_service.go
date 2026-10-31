package rpc

import (
	"context"
	"errors"
	"net/http"
	"sort"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
)

// CheckInService implements the generated CheckInService handler. Its period
// snapshots come from the authoritative period report, and only a final
// manager check-in moves the boundary for the next one.
type CheckInService struct {
	store *store.Store
	auth  *auth.Service
	now   func() time.Time
}

// CheckInServiceOption adjusts the service, which lets tests pin "today" and
// the timestamps assigned to created and updated check-ins.
type CheckInServiceOption func(*CheckInService)

// WithCheckInClock replaces the service's clock.
func WithCheckInClock(now func() time.Time) CheckInServiceOption {
	return func(service *CheckInService) {
		if now != nil {
			service.now = now
		}
	}
}

// NewCheckInService builds the CheckInService implementation.
func NewCheckInService(database *store.Store, authService *auth.Service, options ...CheckInServiceOption) *CheckInService {
	service := &CheckInService{store: database, auth: authService, now: time.Now}
	for _, option := range options {
		option(service)
	}
	return service
}

// Register implements platform.ConnectService.
func (s *CheckInService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewCheckInServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// ListCheckIns returns the caller's check-ins, newest first. An unspecified
// kind lists both manager check-ins and personal reviews.
func (s *CheckInService) ListCheckIns(ctx context.Context, request *connect.Request[wdidv1.ListCheckInsRequest]) (*connect.Response[wdidv1.ListCheckInsResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	kind, err := domainCheckInKindOrEmpty(request.Msg.GetKind())
	if err != nil {
		return nil, toConnectError(err)
	}

	checkIns, err := s.store.CheckIns(userID, kind)
	if err != nil {
		return nil, toConnectError(err)
	}

	page, nextPageToken, err := paginate(checkIns, request.Msg.GetPageSize(), request.Msg.GetPageToken())
	if err != nil {
		return nil, toConnectError(err)
	}

	response := &wdidv1.ListCheckInsResponse{
		CheckIns:      make([]*wdidv1.CheckIn, 0, len(page)),
		NextPageToken: nextPageToken,
	}
	for _, checkIn := range page {
		protoCheckIn := toProtoCheckIn(checkIn)
		// The prompt snapshot and revert slot belong to the detail view; list
		// responses stay small by omitting them.
		protoCheckIn.GenerationPrompt = ""
		protoCheckIn.PreviousSummaryMarkdown = ""
		response.CheckIns = append(response.CheckIns, protoCheckIn)
	}
	return connect.NewResponse(response), nil
}

// GetCheckIn returns one of the caller's check-ins.
func (s *CheckInService) GetCheckIn(ctx context.Context, request *connect.Request[wdidv1.GetCheckInRequest]) (*connect.Response[wdidv1.GetCheckInResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	checkIn, err := s.store.CheckIn(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.GetCheckInResponse{CheckIn: toProtoCheckIn(checkIn)}), nil
}

// GetCheckInDefaults computes the prefilled period from the last final manager
// check-in, or the journal start date, through today in the user's timezone.
// The client may edit both dates before creating the check-in.
func (s *CheckInService) GetCheckInDefaults(ctx context.Context, request *connect.Request[wdidv1.GetCheckInDefaultsRequest]) (*connect.Response[wdidv1.GetCheckInDefaultsResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}
	if _, err := domainCheckInKindOrEmpty(request.Msg.GetKind()); err != nil {
		return nil, toConnectError(err)
	}

	settings := domain.DefaultSettings(userID)
	stored, settingsErr := s.store.Settings(userID)
	if settingsErr == nil {
		settings = stored
	} else if !errors.Is(settingsErr, store.ErrNotFound) {
		return nil, toConnectError(settingsErr)
	}

	location := time.UTC
	if parsed, loadErr := time.LoadLocation(settings.Timezone); loadErr == nil {
		location = parsed
	}
	today := s.now().In(location).Format(domain.DateLayout)

	last, found, err := s.store.LastFinalManagerCheckIn(userID)
	if err != nil {
		return nil, toConnectError(err)
	}

	periodStart := today
	lastID := ""
	if found {
		lastID = last.ID
		if next, nextErr := nextLocalDay(last.PeriodEnd, location); nextErr == nil {
			periodStart = next
		}
	} else if settings.JournalStartDate != "" {
		periodStart = settings.JournalStartDate
	}
	// A boundary already past today has nothing left to cover; keeping the
	// form valid is more useful than a period that starts tomorrow.
	if periodStart > today {
		periodStart = today
	}

	return connect.NewResponse(&wdidv1.GetCheckInDefaultsResponse{
		PeriodStart:        periodStart,
		PeriodEnd:          today,
		LastFinalCheckInId: lastID,
	}), nil
}

// CreateCheckIn opens a draft. The service snapshots the period's aggregates
// from the authoritative report, so the stored totals never come from the
// client.
func (s *CheckInService) CreateCheckIn(ctx context.Context, request *connect.Request[wdidv1.CreateCheckInRequest]) (*connect.Response[wdidv1.CreateCheckInResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	kind, err := requiredCheckInKind(request.Msg.GetKind())
	if err != nil {
		return nil, toConnectError(err)
	}
	audience, err := domainAudience(request.Msg.GetAudience())
	if err != nil {
		return nil, toConnectError(err)
	}

	now := s.now().UTC()
	checkIn := domain.CheckIn{
		ID:          domain.NewID(),
		UserID:      userID,
		Kind:        kind,
		PeriodStart: request.Msg.GetPeriodStart(),
		PeriodEnd:   request.Msg.GetPeriodEnd(),
		State:       domain.CheckInStateDraft,
		Audience:    audience,
		FocusNotes:  request.Msg.GetFocusNotes(),
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	checkIn.Normalize()
	if err := domain.ValidateCheckIn(checkIn); err != nil {
		return nil, toConnectError(err)
	}

	report, err := s.store.PeriodReport(userID, checkIn.PeriodStart, checkIn.PeriodEnd)
	if err != nil {
		return nil, toConnectError(err)
	}
	checkIn.Totals = domain.CheckInTotalsFromReport(report)

	if err := s.store.SaveCheckIn(checkIn); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.CreateCheckInResponse{CheckIn: toProtoCheckIn(checkIn)}), nil
}

// UpdateCheckIn replaces the mutable fields of a check-in. A final manager
// check-in rejects every update, and a summary edit moves a draft to edited.
func (s *CheckInService) UpdateCheckIn(ctx context.Context, request *connect.Request[wdidv1.UpdateCheckInRequest]) (*connect.Response[wdidv1.UpdateCheckInResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	checkIn, err := s.store.CheckIn(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}

	audience, err := domainAudience(request.Msg.GetAudience())
	if err != nil {
		return nil, toConnectError(err)
	}
	source, err := domainSummarySource(request.Msg.GetSummarySource())
	if err != nil {
		return nil, toConnectError(err)
	}

	previousSummary := checkIn.SummaryMarkdown
	previousState := checkIn.State
	previousStart, previousEnd := checkIn.PeriodStart, checkIn.PeriodEnd
	checkIn.PeriodStart = request.Msg.GetPeriodStart()
	checkIn.PeriodEnd = request.Msg.GetPeriodEnd()
	checkIn.Audience = audience
	checkIn.FocusNotes = request.Msg.GetFocusNotes()
	checkIn.SummaryMarkdown = request.Msg.GetSummaryMarkdown()
	checkIn.SummaryModel = request.Msg.GetSummaryModel()
	checkIn.PromptVersion = request.Msg.GetPromptVersion()
	// GenerationPrompt and PreviousSummaryMarkdown are server-owned provenance
	// fields, so a manual update never touches them. A context-only update keeps
	// the state because only a summary change advances the lifecycle below.
	checkIn.AdditionalContext = request.Msg.GetAdditionalContext()
	checkIn.UpdatedAt = s.now().UTC()
	checkIn.Normalize()

	if err := domain.ValidateCheckIn(checkIn); err != nil {
		return nil, toConnectError(err)
	}

	summaryChanged := checkIn.SummaryMarkdown != previousSummary
	// Generated output never replaces a summary the user edited by hand
	// without an explicit confirmation. A manual save is the user's own
	// action, so it needs no confirmation of its own text.
	if summaryChanged &&
		source == domain.SummarySourceGenerated &&
		previousState == domain.CheckInStateEdited &&
		previousSummary != "" &&
		!request.Msg.GetOverwriteManualEdits() {
		return nil, connect.NewError(
			connect.CodeFailedPrecondition,
			errors.New("the summary was edited by hand; confirm overwriting it"),
		)
	}

	// A personal review stays editable but still moves through the editing
	// lifecycle; it simply never reaches final. Generated text keeps the
	// generated state so a later manual save can be told apart from it.
	if checkIn.State != domain.CheckInStateFinal && summaryChanged {
		if source == domain.SummarySourceGenerated {
			checkIn.State = domain.CheckInStateGenerated
		} else {
			checkIn.State = domain.CheckInStateEdited
		}
	}
	// The stored totals describe the period, so an edited period refreshes
	// them from the authoritative report instead of keeping a stale snapshot.
	if checkIn.PeriodStart != previousStart || checkIn.PeriodEnd != previousEnd {
		report, reportErr := s.store.PeriodReport(userID, checkIn.PeriodStart, checkIn.PeriodEnd)
		if reportErr != nil {
			return nil, toConnectError(reportErr)
		}
		checkIn.Totals = domain.CheckInTotalsFromReport(report)
	}

	if err := s.store.SaveCheckIn(checkIn); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.UpdateCheckInResponse{CheckIn: toProtoCheckIn(checkIn)}), nil
}

// BuildCheckInPrompt returns the ready-to-paste prompt block for one check-in.
// The audience recorded on the check-in selects the variant, so switching
// between 1:1 and performance review changes the instruction, never the data.
func (s *CheckInService) BuildCheckInPrompt(ctx context.Context, request *connect.Request[wdidv1.BuildCheckInPromptRequest]) (*connect.Response[wdidv1.BuildCheckInPromptResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	checkIn, err := s.store.CheckIn(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}

	settings, err := s.store.EnsureSupportPeople(userID)
	if err != nil {
		return nil, toConnectError(err)
	}

	variant := domain.PromptVariantFor(checkIn)
	instruction := domain.ResolveInstruction(variant, settings)
	return connect.NewResponse(&wdidv1.BuildCheckInPromptResponse{
		Prompt:        composePrompt(instruction, checkIn.SummaryMarkdown),
		PromptVersion: domain.ResolvePromptVersion(variant, settings),
		Variant:       toProtoPromptVariant(variant),
	}), nil
}

// FinalizeCheckIn marks a manager check-in final. It becomes read-only and
// moves the boundary the next manager check-in starts from. Personal reviews
// never become final.
func (s *CheckInService) FinalizeCheckIn(ctx context.Context, request *connect.Request[wdidv1.FinalizeCheckInRequest]) (*connect.Response[wdidv1.FinalizeCheckInResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	checkIn, err := s.store.CheckIn(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}
	if checkIn.Kind != domain.CheckInKindManager {
		return nil, connect.NewError(connect.CodeFailedPrecondition, errors.New("only a manager check-in can be final"))
	}
	if checkIn.State == domain.CheckInStateFinal {
		return connect.NewResponse(&wdidv1.FinalizeCheckInResponse{CheckIn: toProtoCheckIn(checkIn)}), nil
	}

	checkIn.State = domain.CheckInStateFinal
	checkIn.UpdatedAt = s.now().UTC()
	if err := s.store.SaveCheckIn(checkIn); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.FinalizeCheckInResponse{CheckIn: toProtoCheckIn(checkIn)}), nil
}

// DeleteCheckIn removes a saved non-final check-in: a personal review or a
// manager draft. The store keeps a final manager check-in read-only, because it
// is the boundary for the next period.
func (s *CheckInService) DeleteCheckIn(ctx context.Context, request *connect.Request[wdidv1.DeleteCheckInRequest]) (*connect.Response[wdidv1.DeleteCheckInResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	if err := s.store.DeleteCheckIn(userID, request.Msg.GetId()); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.DeleteCheckInResponse{}), nil
}

// nextLocalDay returns the local calendar day after date.
func nextLocalDay(date string, location *time.Location) (string, error) {
	parsed, err := time.ParseInLocation(domain.DateLayout, date, location)
	if err != nil {
		return "", err
	}
	return parsed.AddDate(0, 0, 1).Format(domain.DateLayout), nil
}

// --- wire mapping ---------------------------------------------------------

func requiredCheckInKind(value wdidv1.CheckInKind) (domain.CheckInKind, error) {
	kind, err := domainCheckInKindOrEmpty(value)
	if err != nil {
		return "", err
	}
	if kind == "" {
		return "", domain.ValidationError{Field: "kind", Message: "must be manager or personal"}
	}
	return kind, nil
}

func domainCheckInKindOrEmpty(value wdidv1.CheckInKind) (domain.CheckInKind, error) {
	switch value {
	case wdidv1.CheckInKind_CHECK_IN_KIND_UNSPECIFIED:
		return "", nil
	case wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER:
		return domain.CheckInKindManager, nil
	case wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL:
		return domain.CheckInKindPersonal, nil
	default:
		return "", domain.ValidationError{Field: "kind", Message: "must be manager or personal"}
	}
}

func domainAudience(value wdidv1.CheckInAudience) (domain.Audience, error) {
	switch value {
	case wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_UNSPECIFIED:
		return "", nil
	case wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE:
		return domain.AudienceOneOnOne, nil
	case wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW:
		return domain.AudiencePerformanceReview, nil
	default:
		return "", domain.ValidationError{Field: "audience", Message: "must be one_on_one or performance_review"}
	}
}

func domainSummarySource(value wdidv1.CheckInSummarySource) (domain.SummarySource, error) {
	switch value {
	case wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_UNSPECIFIED:
		return "", nil
	case wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_MANUAL:
		return domain.SummarySourceManual, nil
	case wdidv1.CheckInSummarySource_CHECK_IN_SUMMARY_SOURCE_GENERATED:
		return domain.SummarySourceGenerated, nil
	default:
		return "", domain.ValidationError{Field: "summarySource", Message: "must be manual or generated"}
	}
}

func toProtoPromptVariant(variant domain.PromptVariant) wdidv1.CheckInPromptVariant {
	switch variant {
	case domain.PromptVariantManagerOneOnOne:
		return wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE
	case domain.PromptVariantManagerPerformanceReview:
		return wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW
	case domain.PromptVariantPersonalReview:
		return wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW
	default:
		return wdidv1.CheckInPromptVariant_CHECK_IN_PROMPT_VARIANT_UNSPECIFIED
	}
}

func toProtoCheckInKind(kind domain.CheckInKind) wdidv1.CheckInKind {
	switch kind {
	case domain.CheckInKindManager:
		return wdidv1.CheckInKind_CHECK_IN_KIND_MANAGER
	case domain.CheckInKindPersonal:
		return wdidv1.CheckInKind_CHECK_IN_KIND_PERSONAL
	default:
		return wdidv1.CheckInKind_CHECK_IN_KIND_UNSPECIFIED
	}
}

func toProtoCheckInState(state domain.CheckInState) wdidv1.CheckInState {
	switch state {
	case domain.CheckInStateDraft:
		return wdidv1.CheckInState_CHECK_IN_STATE_DRAFT
	case domain.CheckInStateGenerated:
		return wdidv1.CheckInState_CHECK_IN_STATE_GENERATED
	case domain.CheckInStateEdited:
		return wdidv1.CheckInState_CHECK_IN_STATE_EDITED
	case domain.CheckInStateFinal:
		return wdidv1.CheckInState_CHECK_IN_STATE_FINAL
	default:
		return wdidv1.CheckInState_CHECK_IN_STATE_UNSPECIFIED
	}
}

func toProtoAudience(audience domain.Audience) wdidv1.CheckInAudience {
	switch audience {
	case domain.AudienceOneOnOne:
		return wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_ONE_ON_ONE
	case domain.AudiencePerformanceReview:
		return wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW
	default:
		return wdidv1.CheckInAudience_CHECK_IN_AUDIENCE_UNSPECIFIED
	}
}

func toProtoCheckIn(checkIn domain.CheckIn) *wdidv1.CheckIn {
	return &wdidv1.CheckIn{
		Id:                      checkIn.ID,
		Kind:                    toProtoCheckInKind(checkIn.Kind),
		PeriodStart:             checkIn.PeriodStart,
		PeriodEnd:               checkIn.PeriodEnd,
		State:                   toProtoCheckInState(checkIn.State),
		Audience:                toProtoAudience(checkIn.Audience),
		FocusNotes:              checkIn.FocusNotes,
		SummaryMarkdown:         checkIn.SummaryMarkdown,
		SummaryModel:            checkIn.SummaryModel,
		PromptVersion:           checkIn.PromptVersion,
		AdditionalContext:       checkIn.AdditionalContext,
		GenerationPrompt:        checkIn.GenerationPrompt,
		PreviousSummaryMarkdown: checkIn.PreviousSummaryMarkdown,
		Totals:                  toProtoCheckInTotals(checkIn.Totals),
		CreatedAt:               timestamppb.New(checkIn.CreatedAt),
		UpdatedAt:               timestamppb.New(checkIn.UpdatedAt),
	}
}

func toProtoCheckInTotals(totals domain.CheckInTotals) *wdidv1.CheckInTotals {
	return &wdidv1.CheckInTotals{
		Total:               minutesDuration(totals.Minutes),
		ByCategory:          toProtoCheckInTotalsMap(totals.ByCategory),
		BySubcategory:       toProtoCheckInTotalsMap(totals.BySubcategory),
		SupportByPerson:     toProtoCheckInTotalsMap(totals.SupportByPerson),
		SupportDuration:     minutesDuration(totals.EffectiveSupportMinutes()),
		SupportInteractions: int32(totals.EffectiveSupportInteractions()),
	}
}

// toProtoCheckInTotalsMap sorts keys so the wire form is stable across reads.
func toProtoCheckInTotalsMap(values map[string]int) []*wdidv1.CheckInTotal {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	totals := make([]*wdidv1.CheckInTotal, 0, len(keys))
	for _, key := range keys {
		totals = append(totals, &wdidv1.CheckInTotal{
			Key:      key,
			Duration: minutesDuration(values[key]),
		})
	}
	return totals
}
