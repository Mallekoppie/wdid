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

// NoteService implements the generated NoteService handler. Day notes and
// project notes share one model; every RPC derives the account from the
// verified bearer token, so one user can never read or mutate another user's
// notes.
type NoteService struct {
	store *store.Store
	auth  *auth.Service
}

// NewNoteService builds the NoteService implementation.
func NewNoteService(database *store.Store, authService *auth.Service) *NoteService {
	return &NoteService{store: database, auth: authService}
}

// Register implements platform.ConnectService.
func (s *NoteService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewNoteServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// ListNotes returns the caller's notes matching the filter, newest first. A
// date selects day notes and a subcategory selects project notes; both
// filters combine with AND.
func (s *NoteService) ListNotes(ctx context.Context, request *connect.Request[wdidv1.ListNotesRequest]) (*connect.Response[wdidv1.ListNotesResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	notes, err := s.store.Notes(userID, store.NoteFilter{
		Date:          request.Msg.GetDate(),
		SubcategoryID: request.Msg.GetSubcategoryId(),
	})
	if err != nil {
		return nil, toConnectError(err)
	}

	page, nextPageToken, err := paginate(notes, request.Msg.GetPageSize(), request.Msg.GetPageToken())
	if err != nil {
		return nil, toConnectError(err)
	}

	response := &wdidv1.ListNotesResponse{
		Notes:         make([]*wdidv1.Note, 0, len(page)),
		NextPageToken: nextPageToken,
	}
	for _, note := range page {
		response.Notes = append(response.Notes, toProtoNote(note))
	}
	return connect.NewResponse(response), nil
}

// CreateNote attaches a note to a day, a subcategory, or both.
func (s *NoteService) CreateNote(ctx context.Context, request *connect.Request[wdidv1.CreateNoteRequest]) (*connect.Response[wdidv1.CreateNoteResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	note := domain.Note{
		ID:            domain.NewID(),
		UserID:        userID,
		Date:          request.Msg.GetDate(),
		SubcategoryID: request.Msg.GetSubcategoryId(),
		Text:          request.Msg.GetText(),
		CreatedAt:     time.Now().UTC(),
	}
	if err := s.store.SaveNote(note); err != nil {
		return nil, toConnectError(err)
	}

	stored, err := s.store.Note(userID, note.ID)
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.CreateNoteResponse{Note: toProtoNote(stored)}), nil
}

// UpdateNote replaces the mutable fields of a note. The owner and creation
// time always come from the stored record.
func (s *NoteService) UpdateNote(ctx context.Context, request *connect.Request[wdidv1.UpdateNoteRequest]) (*connect.Response[wdidv1.UpdateNoteResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	note, err := s.store.Note(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}
	note.Date = request.Msg.GetDate()
	note.SubcategoryID = request.Msg.GetSubcategoryId()
	note.Text = request.Msg.GetText()
	if err := s.store.SaveNote(note); err != nil {
		return nil, toConnectError(err)
	}

	stored, err := s.store.Note(userID, note.ID)
	if err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.UpdateNoteResponse{Note: toProtoNote(stored)}), nil
}

// DeleteNote removes one of the caller's notes.
func (s *NoteService) DeleteNote(ctx context.Context, request *connect.Request[wdidv1.DeleteNoteRequest]) (*connect.Response[wdidv1.DeleteNoteResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	if err := s.store.DeleteNote(userID, request.Msg.GetId()); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.DeleteNoteResponse{}), nil
}

func toProtoNote(note domain.Note) *wdidv1.Note {
	return &wdidv1.Note{
		Id:            note.ID,
		Date:          note.Date,
		SubcategoryId: note.SubcategoryID,
		Text:          note.Text,
		CreatedAt:     timestamppb.New(note.CreatedAt),
	}
}
