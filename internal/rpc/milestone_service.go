package rpc

import (
	"context"
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

// MilestoneService implements the generated MilestoneService handler. Every RPC
// derives the account from the verified bearer token, so one user can never
// read or mutate another user's milestones.
type MilestoneService struct {
	store *store.Store
	auth  *auth.Service
	now   func() time.Time
}

// MilestoneServiceOption adjusts the service, which lets tests control the
// timestamps assigned to created and updated milestones.
type MilestoneServiceOption func(*MilestoneService)

// WithMilestoneClock replaces the service's clock.
func WithMilestoneClock(now func() time.Time) MilestoneServiceOption {
	return func(service *MilestoneService) {
		if now != nil {
			service.now = now
		}
	}
}

// NewMilestoneService builds the MilestoneService implementation.
func NewMilestoneService(database *store.Store, authService *auth.Service, options ...MilestoneServiceOption) *MilestoneService {
	service := &MilestoneService{store: database, auth: authService, now: time.Now}
	for _, option := range options {
		option(service)
	}
	return service
}

// Register implements platform.ConnectService.
func (s *MilestoneService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewMilestoneServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// ListMilestones returns the caller's milestones, optionally narrowed to one
// project, ordered by due date with undated milestones last.
func (s *MilestoneService) ListMilestones(ctx context.Context, request *connect.Request[wdidv1.ListMilestonesRequest]) (*connect.Response[wdidv1.ListMilestonesResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	milestones, err := s.store.Milestones(userID, request.Msg.GetSubcategoryId())
	if err != nil {
		return nil, toConnectError(err)
	}

	page, nextPageToken, err := paginate(milestones, request.Msg.GetPageSize(), request.Msg.GetPageToken())
	if err != nil {
		return nil, toConnectError(err)
	}

	response := &wdidv1.ListMilestonesResponse{
		Milestones:    make([]*wdidv1.Milestone, 0, len(page)),
		NextPageToken: nextPageToken,
	}
	for _, milestone := range page {
		response.Milestones = append(response.Milestones, toProtoMilestone(milestone))
	}
	return connect.NewResponse(response), nil
}

// CreateMilestone creates a checkpoint on one of the caller's projects.
func (s *MilestoneService) CreateMilestone(ctx context.Context, request *connect.Request[wdidv1.CreateMilestoneRequest]) (*connect.Response[wdidv1.CreateMilestoneResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	now := s.now().UTC()
	milestone := domain.Milestone{
		ID:            domain.NewID(),
		UserID:        userID,
		SubcategoryID: request.Msg.GetSubcategoryId(),
		Title:         request.Msg.GetTitle(),
		DueDate:       request.Msg.GetDueDate(),
		Done:          request.Msg.GetDone(),
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	if err := s.store.SaveMilestone(milestone); err != nil {
		return nil, toConnectError(err)
	}

	stored, err := s.store.Milestone(userID, milestone.ID)
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.CreateMilestoneResponse{Milestone: toProtoMilestone(stored)}), nil
}

// UpdateMilestone replaces the mutable fields of a milestone. The project,
// owner and creation time always come from the stored record.
func (s *MilestoneService) UpdateMilestone(ctx context.Context, request *connect.Request[wdidv1.UpdateMilestoneRequest]) (*connect.Response[wdidv1.UpdateMilestoneResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	milestone, err := s.store.Milestone(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}
	milestone.Title = request.Msg.GetTitle()
	milestone.DueDate = request.Msg.GetDueDate()
	milestone.Done = request.Msg.GetDone()
	milestone.UpdatedAt = s.now().UTC()
	if err := s.store.SaveMilestone(milestone); err != nil {
		return nil, toConnectError(err)
	}

	stored, err := s.store.Milestone(userID, milestone.ID)
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.UpdateMilestoneResponse{Milestone: toProtoMilestone(stored)}), nil
}

// DeleteMilestone removes one of the caller's milestones.
func (s *MilestoneService) DeleteMilestone(ctx context.Context, request *connect.Request[wdidv1.DeleteMilestoneRequest]) (*connect.Response[wdidv1.DeleteMilestoneResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	if err := s.store.DeleteMilestone(userID, request.Msg.GetId()); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.DeleteMilestoneResponse{}), nil
}

func toProtoMilestone(milestone domain.Milestone) *wdidv1.Milestone {
	return &wdidv1.Milestone{
		Id:            milestone.ID,
		SubcategoryId: milestone.SubcategoryID,
		Title:         milestone.Title,
		DueDate:       milestone.DueDate,
		Done:          milestone.Done,
		CreatedAt:     timestamppb.New(milestone.CreatedAt),
		UpdatedAt:     timestamppb.New(milestone.UpdatedAt),
	}
}
