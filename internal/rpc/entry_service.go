package rpc

import (
	"context"
	"errors"
	"net/http"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
)

// EntryService implements the generated EntryService handler. Every RPC
// derives the account from the verified bearer token, so one user can never
// read or mutate another user's work entries.
type EntryService struct {
	store *store.Store
	auth  *auth.Service
}

// NewEntryService builds the EntryService implementation.
func NewEntryService(database *store.Store, authService *auth.Service) *EntryService {
	return &EntryService{store: database, auth: authService}
}

// Register implements platform.ConnectService.
func (s *EntryService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewEntryServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// ListEntries returns the caller's entries matching the filter, newest first.
func (s *EntryService) ListEntries(ctx context.Context, request *connect.Request[wdidv1.ListEntriesRequest]) (*connect.Response[wdidv1.ListEntriesResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	localDate := request.Msg.GetLocalDate()
	if request.Msg.GetToday() {
		localDate, err = s.store.LocalDate(userID, time.Now())
		if err != nil {
			return nil, toConnectError(err)
		}
	}

	filter := store.WorkEntryFilter{
		LocalDate:     localDate,
		CategoryID:    request.Msg.GetCategoryId(),
		SubcategoryID: request.Msg.GetSubcategoryId(),
		Person:        request.Msg.GetPerson(),
		Query:         request.Msg.GetQuery(),
	}
	if request.Msg.GetFromDate() != "" || request.Msg.GetToDate() != "" {
		// An explicit local date is resolved in the user's configured timezone,
		// so the device clock cannot move the day boundary.
		filter.From, filter.To, err = s.store.LocalDayRange(
			userID,
			request.Msg.GetFromDate(),
			request.Msg.GetToDate(),
		)
		if err != nil {
			return nil, toConnectError(err)
		}
	} else {
		if request.Msg.GetFrom() != nil {
			filter.From = request.Msg.GetFrom().AsTime()
		}
		if request.Msg.GetTo() != nil {
			filter.To = request.Msg.GetTo().AsTime()
		}
	}

	entries, err := s.store.WorkEntries(userID, filter)
	if err != nil {
		return nil, toConnectError(err)
	}

	// Overlaps are detected against every entry the user owns, so filtering
	// one side of an intersecting pair does not hide the marker. Only the
	// filtered entries are reported.
	allEntries, err := s.store.WorkEntries(userID, store.WorkEntryFilter{})
	if err != nil {
		return nil, toConnectError(err)
	}
	matching := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		matching[entry.ID] = struct{}{}
	}
	overlapping := make([]string, 0)
	for _, id := range domain.OverlappingEntryIDs(allEntries) {
		if _, ok := matching[id]; ok {
			overlapping = append(overlapping, id)
		}
	}

	page, nextPageToken, err := paginate(entries, request.Msg.GetPageSize(), request.Msg.GetPageToken())
	if err != nil {
		return nil, toConnectError(err)
	}

	response := &wdidv1.ListEntriesResponse{
		Entries:             make([]*wdidv1.WorkEntry, 0, len(page)),
		NextPageToken:       nextPageToken,
		OverlappingEntryIds: overlapping,
	}
	for _, entry := range page {
		response.Entries = append(response.Entries, toProtoWorkEntry(entry))
	}
	return connect.NewResponse(response), nil
}

// GetEntry returns one of the caller's entries.
func (s *EntryService) GetEntry(ctx context.Context, request *connect.Request[wdidv1.GetEntryRequest]) (*connect.Response[wdidv1.GetEntryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	entry, err := s.store.WorkEntry(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.GetEntryResponse{Entry: toProtoWorkEntry(entry)}), nil
}

// CreateEntry records a work entry. When the request omits a duration and an
// end time, the caller's default entry duration from Settings is used.
func (s *EntryService) CreateEntry(ctx context.Context, request *connect.Request[wdidv1.CreateEntryRequest]) (*connect.Response[wdidv1.CreateEntryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	now := time.Now().UTC()
	startedAt := now
	if request.Msg.GetStartedAt() != nil {
		startedAt = request.Msg.GetStartedAt().AsTime().UTC()
	}
	endedAt := time.Time{}
	if request.Msg.GetEndedAt() != nil {
		endedAt = request.Msg.GetEndedAt().AsTime().UTC()
	}

	duration := durationMinutes(request.Msg.GetDuration())
	if duration <= 0 && endedAt.IsZero() {
		duration, err = s.defaultDuration(userID)
		if err != nil {
			return nil, toConnectError(err)
		}
	}
	// Minutes are authoritative: an explicit duration decides the end instant,
	// so the two can never disagree.
	if duration > 0 {
		endedAt = startedAt.Add(time.Duration(duration) * time.Minute)
	}

	entry := domain.WorkEntry{
		ID:            domain.NewID(),
		UserID:        userID,
		CategoryID:    request.Msg.GetCategoryId(),
		SubcategoryID: request.Msg.GetSubcategoryId(),
		Description:   request.Msg.GetDescription(),
		Outcome:       request.Msg.GetOutcome(),
		StartedAt:     startedAt,
		EndedAt:       endedAt,
		Minutes:       duration,
		People:        request.Msg.GetPeople(),
		Team:          request.Msg.GetTeam(),
		Tags:          request.Msg.GetTags(),
		Links:         fromProtoLinks(request.Msg.GetLinks()),
		Source:        fromProtoEntrySource(request.Msg.GetSource()),
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	if entry.Source == "" {
		entry.Source = domain.EntrySourceManual
	}

	if err := s.store.SaveWorkEntry(entry); err != nil {
		return nil, entryConnectError(err)
	}

	stored, err := s.store.WorkEntry(userID, entry.ID)
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.CreateEntryResponse{Entry: toProtoWorkEntry(stored)}), nil
}

// UpdateEntry replaces the mutable fields of an entry. The account, source and
// creation time always come from the stored record.
func (s *EntryService) UpdateEntry(ctx context.Context, request *connect.Request[wdidv1.UpdateEntryRequest]) (*connect.Response[wdidv1.UpdateEntryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	entry, err := s.store.WorkEntry(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}

	startedAt := entry.StartedAt
	if request.Msg.GetStartedAt() != nil {
		startedAt = request.Msg.GetStartedAt().AsTime().UTC()
	}
	endedAt := entry.EndedAt
	if request.Msg.GetEndedAt() != nil {
		endedAt = request.Msg.GetEndedAt().AsTime().UTC()
	}
	duration := entry.Minutes
	if request.Msg.GetDuration() != nil {
		duration = durationMinutes(request.Msg.GetDuration())
	}
	if duration > 0 {
		endedAt = startedAt.Add(time.Duration(duration) * time.Minute)
	}

	entry.CategoryID = request.Msg.GetCategoryId()
	entry.SubcategoryID = request.Msg.GetSubcategoryId()
	entry.Description = request.Msg.GetDescription()
	entry.Outcome = request.Msg.GetOutcome()
	entry.StartedAt = startedAt
	entry.EndedAt = endedAt
	entry.Minutes = duration
	entry.People = request.Msg.GetPeople()
	entry.Team = request.Msg.GetTeam()
	entry.Tags = request.Msg.GetTags()
	entry.Links = fromProtoLinks(request.Msg.GetLinks())
	entry.UpdatedAt = time.Now().UTC()

	if err := s.store.SaveWorkEntry(entry); err != nil {
		return nil, entryConnectError(err)
	}

	stored, err := s.store.WorkEntry(userID, entry.ID)
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.UpdateEntryResponse{Entry: toProtoWorkEntry(stored)}), nil
}

// DeleteEntry removes one of the caller's entries.
func (s *EntryService) DeleteEntry(ctx context.Context, request *connect.Request[wdidv1.DeleteEntryRequest]) (*connect.Response[wdidv1.DeleteEntryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	if err := s.store.DeleteWorkEntry(userID, request.Msg.GetId()); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.DeleteEntryResponse{}), nil
}

// SplitEntry divides one of the caller's entries into two contiguous blocks at
// the requested minute offset.
func (s *EntryService) SplitEntry(ctx context.Context, request *connect.Request[wdidv1.SplitEntryRequest]) (*connect.Response[wdidv1.SplitEntryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	first, second, err := s.store.SplitWorkEntry(userID, request.Msg.GetId(), durationMinutes(request.Msg.GetAt()))
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.SplitEntryResponse{
		First:  toProtoWorkEntry(first),
		Second: toProtoWorkEntry(second),
	}), nil
}

// entryConnectError keeps a missing referenced category or subcategory on the
// field that caused it, because the request's attribution is invalid rather
// than the record being absent.
func entryConnectError(err error) error {
	switch {
	case errors.Is(err, store.ErrCategoryNotFound):
		return toConnectError(domain.ValidationError{Field: "categoryId", Message: "category does not exist"})
	case errors.Is(err, store.ErrSubcategoryNotFound):
		return toConnectError(domain.ValidationError{Field: "subcategoryId", Message: "subcategory does not exist"})
	default:
		return toConnectError(err)
	}
}

// defaultDuration reads the caller's default entry duration, falling back to
// the seeded defaults when the settings record predates seeding.
func (s *EntryService) defaultDuration(userID string) (int, error) {
	settings, err := s.store.Settings(userID)
	if errors.Is(err, store.ErrNotFound) {
		return domain.DefaultSettings(userID).DefaultDurationMinutes, nil
	}
	if err != nil {
		return 0, err
	}
	return settings.DefaultDurationMinutes, nil
}

func toProtoWorkEntry(entry domain.WorkEntry) *wdidv1.WorkEntry {
	var endedAt *timestamppb.Timestamp
	if !entry.EndedAt.IsZero() {
		endedAt = timestamppb.New(entry.EndedAt)
	}
	return &wdidv1.WorkEntry{
		Id:            entry.ID,
		CategoryId:    entry.CategoryID,
		SubcategoryId: entry.SubcategoryID,
		Description:   entry.Description,
		Outcome:       entry.Outcome,
		StartedAt:     timestamppb.New(entry.StartedAt),
		EndedAt:       endedAt,
		Duration:      minutesDuration(entry.DurationMinutes()),
		LocalDate:     entry.LocalDate,
		People:        entry.People,
		Team:          entry.Team,
		Tags:          entry.Tags,
		Links:         toProtoLinks(entry.Links),
		Source:        toProtoEntrySource(entry.Source),
		CreatedAt:     timestamppb.New(entry.CreatedAt),
		UpdatedAt:     timestamppb.New(entry.UpdatedAt),
	}
}

func toProtoEntrySource(source domain.EntrySource) wdidv1.EntrySource {
	switch source {
	case domain.EntrySourceManual:
		return wdidv1.EntrySource_ENTRY_SOURCE_MANUAL
	case domain.EntrySourceTimer:
		return wdidv1.EntrySource_ENTRY_SOURCE_TIMER
	default:
		return wdidv1.EntrySource_ENTRY_SOURCE_UNSPECIFIED
	}
}

func fromProtoEntrySource(source wdidv1.EntrySource) domain.EntrySource {
	switch source {
	case wdidv1.EntrySource_ENTRY_SOURCE_MANUAL:
		return domain.EntrySourceManual
	case wdidv1.EntrySource_ENTRY_SOURCE_TIMER:
		return domain.EntrySourceTimer
	default:
		return ""
	}
}
