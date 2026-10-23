package rpc

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/genproto/googleapis/rpc/errdetails"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/Mallekoppie/wdid/internal/auth"
	"github.com/Mallekoppie/wdid/internal/domain"
	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
	"github.com/Mallekoppie/wdid/internal/store"
)

// TimerService implements the generated TimerService handler. Timer state is
// server-owned: the client only renders snapshots and asks for transitions.
type TimerService struct {
	store *store.Store
	auth  *auth.Service
	now   func() time.Time
}

// TimerServiceOption customises a TimerService. Tests use it to control time.
type TimerServiceOption func(*TimerService)

// WithTimerClock replaces the clock used for transitions and elapsed values.
func WithTimerClock(now func() time.Time) TimerServiceOption {
	return func(service *TimerService) {
		service.now = now
	}
}

// NewTimerService builds the TimerService implementation.
func NewTimerService(database *store.Store, authService *auth.Service, options ...TimerServiceOption) *TimerService {
	service := &TimerService{store: database, auth: authService, now: time.Now}
	for _, option := range options {
		option(service)
	}
	return service
}

// Register implements platform.ConnectService.
func (s *TimerService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewTimerServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// StartTimer starts the caller's timer against a category and optional
// subcategory. At most one timer runs per user.
func (s *TimerService) StartTimer(ctx context.Context, request *connect.Request[wdidv1.StartTimerRequest]) (*connect.Response[wdidv1.StartTimerResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	now := s.now().UTC()
	timer := domain.ActiveTimer{
		UserID:           userID,
		CategoryID:       request.Msg.GetCategoryId(),
		SubcategoryID:    request.Msg.GetSubcategoryId(),
		Description:      request.Msg.GetDescription(),
		Person:           request.Msg.GetPerson(),
		StartedAt:        now,
		SegmentStartedAt: now,
	}
	// Normalize before both writing and responding so the snapshot the client
	// receives is exactly what the store holds.
	timer.Normalize()
	if err := s.store.StartTimer(timer); err != nil {
		return nil, timerConnectError(err)
	}
	return connect.NewResponse(&wdidv1.StartTimerResponse{
		Timer: toProtoActiveTimer(timer, now),
	}), nil
}

// PauseTimer stops the elapsed clock without ending the timer.
func (s *TimerService) PauseTimer(ctx context.Context, _ *connect.Request[wdidv1.PauseTimerRequest]) (*connect.Response[wdidv1.PauseTimerResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	now := s.now().UTC()
	timer, err := s.store.PauseTimer(userID, now)
	if err != nil {
		return nil, timerConnectError(err)
	}
	return connect.NewResponse(&wdidv1.PauseTimerResponse{
		Timer: toProtoActiveTimer(timer, now),
	}), nil
}

// ResumeTimer restarts the elapsed clock after a pause.
func (s *TimerService) ResumeTimer(ctx context.Context, _ *connect.Request[wdidv1.ResumeTimerRequest]) (*connect.Response[wdidv1.ResumeTimerResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	now := s.now().UTC()
	timer, err := s.store.ResumeTimer(userID, now)
	if err != nil {
		return nil, timerConnectError(err)
	}
	return connect.NewResponse(&wdidv1.ResumeTimerResponse{
		Timer: toProtoActiveTimer(timer, now),
	}), nil
}

// StopTimer ends the timer and saves a work entry unless the caller discards
// it. A stop under one minute, or above the block limit without a choice,
// returns a conflict the UI turns into a decision.
func (s *TimerService) StopTimer(ctx context.Context, request *connect.Request[wdidv1.StopTimerRequest]) (*connect.Response[wdidv1.StopTimerResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	blockLimit, err := s.blockLimit(userID)
	if err != nil {
		return nil, toConnectError(err)
	}

	entry, discarded, err := s.store.StopTimer(
		userID,
		s.now().UTC(),
		fromProtoTimerStopAction(request.Msg.GetAction()),
		blockLimit,
	)
	if err != nil {
		return nil, timerConnectError(err)
	}

	response := &wdidv1.StopTimerResponse{Discarded: discarded}
	if !discarded {
		response.Entry = toProtoWorkEntry(entry)
	}
	return connect.NewResponse(response), nil
}

// GetActiveTimer returns the caller's timer snapshot and block limit, or an
// absent timer when none is running. The client polls it to follow changes
// made in another tab.
func (s *TimerService) GetActiveTimer(ctx context.Context, _ *connect.Request[wdidv1.GetActiveTimerRequest]) (*connect.Response[wdidv1.GetActiveTimerResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	blockLimit, err := s.blockLimit(userID)
	if err != nil {
		return nil, toConnectError(err)
	}

	response := &wdidv1.GetActiveTimerResponse{
		BlockLimit: durationpb.New(time.Duration(blockLimit) * time.Minute),
	}
	timer, active, err := s.store.ActiveTimer(userID)
	if err != nil {
		return nil, toConnectError(err)
	}
	if active {
		response.Timer = toProtoActiveTimer(timer, s.now().UTC())
	}
	return connect.NewResponse(response), nil
}

func (s *TimerService) blockLimit(userID string) (int, error) {
	settings, err := s.store.Settings(userID)
	if errors.Is(err, store.ErrNotFound) {
		return domain.DefaultSettings(userID).LongTimerMinutes, nil
	}
	if err != nil {
		return 0, err
	}
	return settings.LongTimerMinutes, nil
}

func toProtoActiveTimer(timer domain.ActiveTimer, now time.Time) *wdidv1.ActiveTimer {
	result := &wdidv1.ActiveTimer{
		CategoryId:        timer.CategoryID,
		SubcategoryId:     timer.SubcategoryID,
		Description:       timer.Description,
		Person:            timer.Person,
		StartedAt:         timestamppb.New(timer.StartedAt),
		SegmentStartedAt:  timestamppb.New(timer.SegmentStartedAt),
		AccumulatedPaused: durationpb.New(time.Duration(timer.AccumulatedSeconds) * time.Second),
		Elapsed:           durationpb.New(timer.Elapsed(now)),
		Paused:            timer.Paused(),
	}
	if timer.PausedAt != nil {
		result.PausedAt = timestamppb.New(*timer.PausedAt)
	}
	return result
}

func fromProtoTimerStopAction(action wdidv1.TimerStopAction) domain.TimerStopAction {
	switch action {
	case wdidv1.TimerStopAction_TIMER_STOP_ACTION_KEEP:
		return domain.TimerStopKeep
	case wdidv1.TimerStopAction_TIMER_STOP_ACTION_TRIM:
		return domain.TimerStopTrim
	case wdidv1.TimerStopAction_TIMER_STOP_ACTION_DISCARD:
		return domain.TimerStopDiscard
	default:
		return domain.TimerStopSave
	}
}

// timerConnectError keeps attribution failures on their fields and carries a
// timer conflict's reason, so the client can offer the right choice.
func timerConnectError(err error) error {
	var conflict domain.TimerConflictError
	switch {
	case errors.As(err, &conflict):
		connectErr := connect.NewError(connect.CodeFailedPrecondition, err)
		detail, detailErr := connect.NewErrorDetail(&errdetails.ErrorInfo{
			Reason: string(conflict.Reason),
			Domain: "wdid.v1.TimerService",
			Metadata: map[string]string{
				"elapsedMinutes":    strconv.Itoa(conflict.ElapsedMinutes),
				"blockLimitMinutes": strconv.Itoa(conflict.BlockLimitMinutes),
			},
		})
		if detailErr == nil {
			connectErr.AddDetail(detail)
		}
		return connectErr
	case errors.Is(err, store.ErrCategoryNotFound):
		return toConnectError(domain.ValidationError{Field: "categoryId", Message: "category does not exist"})
	case errors.Is(err, store.ErrSubcategoryNotFound):
		return toConnectError(domain.ValidationError{Field: "subcategoryId", Message: "subcategory does not exist"})
	case errors.Is(err, store.ErrTimerRunning), errors.Is(err, store.ErrTimerNotRunning):
		return connect.NewError(connect.CodeFailedPrecondition, err)
	default:
		return toConnectError(err)
	}
}
