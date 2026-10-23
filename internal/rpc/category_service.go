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

// CategoryService implements the generated CategoryService handler. Every RPC
// derives the account from the verified bearer token, so one user can never
// read or mutate another user's taxonomy.
type CategoryService struct {
	store *store.Store
	auth  *auth.Service
}

// NewCategoryService builds the CategoryService implementation.
func NewCategoryService(database *store.Store, authService *auth.Service) *CategoryService {
	return &CategoryService{store: database, auth: authService}
}

// Register implements platform.ConnectService.
func (s *CategoryService) Register(mux *http.ServeMux, options ...connect.HandlerOption) {
	prefix, handler := wdidv1connect.NewCategoryServiceHandler(s, options...)
	mux.Handle(prefix, handler)
}

// ListCategories returns the caller's taxonomy in sort order.
func (s *CategoryService) ListCategories(ctx context.Context, request *connect.Request[wdidv1.ListCategoriesRequest]) (*connect.Response[wdidv1.ListCategoriesResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	categories, err := s.store.Categories(userID)
	if err != nil {
		return nil, toConnectError(err)
	}

	page, nextPageToken, err := paginate(categories, request.Msg.GetPageSize(), request.Msg.GetPageToken())
	if err != nil {
		return nil, toConnectError(err)
	}

	response := &wdidv1.ListCategoriesResponse{
		Categories:    make([]*wdidv1.Category, 0, len(page)),
		NextPageToken: nextPageToken,
	}
	for _, category := range page {
		response.Categories = append(response.Categories, toProtoCategory(category))
	}
	return connect.NewResponse(response), nil
}

// CreateCategory records a category with an immutable reporting role.
func (s *CategoryService) CreateCategory(ctx context.Context, request *connect.Request[wdidv1.CreateCategoryRequest]) (*connect.Response[wdidv1.CreateCategoryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	now := time.Now().UTC()
	category := domain.Category{
		ID:        domain.NewID(),
		UserID:    userID,
		Name:      request.Msg.GetName(),
		Role:      fromProtoCategoryRole(request.Msg.GetRole()),
		Color:     request.Msg.GetColor(),
		SortOrder: int(request.Msg.GetSortOrder()),
		CreatedAt: now,
		UpdatedAt: now,
	}
	category.Normalize()
	if err := s.store.SaveCategory(category); err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.CreateCategoryResponse{Category: toProtoCategory(category)}), nil
}

// UpdateCategory changes the name, colour and sort order. The reporting role is
// not part of the request and therefore cannot change.
func (s *CategoryService) UpdateCategory(ctx context.Context, request *connect.Request[wdidv1.UpdateCategoryRequest]) (*connect.Response[wdidv1.UpdateCategoryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	category, err := s.store.Category(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}

	category.Name = request.Msg.GetName()
	category.Color = request.Msg.GetColor()
	category.SortOrder = int(request.Msg.GetSortOrder())
	category.UpdatedAt = time.Now().UTC()
	category.Normalize()
	if err := s.store.SaveCategory(category); err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.UpdateCategoryResponse{Category: toProtoCategory(category)}), nil
}

// ArchiveCategory hides a category from entry selectors while keeping it in
// historical reporting.
func (s *CategoryService) ArchiveCategory(ctx context.Context, request *connect.Request[wdidv1.ArchiveCategoryRequest]) (*connect.Response[wdidv1.ArchiveCategoryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	category, err := s.store.Category(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}

	category.Archived = request.Msg.GetArchived()
	category.UpdatedAt = time.Now().UTC()
	if err := s.store.SaveCategory(category); err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.ArchiveCategoryResponse{Category: toProtoCategory(category)}), nil
}

// DeleteCategory removes an unreferenced category. Referenced categories fail
// with CodeFailedPrecondition and must be archived instead.
func (s *CategoryService) DeleteCategory(ctx context.Context, request *connect.Request[wdidv1.DeleteCategoryRequest]) (*connect.Response[wdidv1.DeleteCategoryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	if err := s.store.DeleteCategory(userID, request.Msg.GetId()); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.DeleteCategoryResponse{}), nil
}

// ListSubcategories returns the caller's subcategories, optionally narrowed to
// one category.
func (s *CategoryService) ListSubcategories(ctx context.Context, request *connect.Request[wdidv1.ListSubcategoriesRequest]) (*connect.Response[wdidv1.ListSubcategoriesResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	subcategories, err := s.store.Subcategories(userID, request.Msg.GetCategoryId())
	if err != nil {
		return nil, toConnectError(err)
	}

	page, nextPageToken, err := paginate(subcategories, request.Msg.GetPageSize(), request.Msg.GetPageToken())
	if err != nil {
		return nil, toConnectError(err)
	}

	response := &wdidv1.ListSubcategoriesResponse{
		Subcategories: make([]*wdidv1.Subcategory, 0, len(page)),
		NextPageToken: nextPageToken,
	}
	for _, subcategory := range page {
		response.Subcategories = append(response.Subcategories, toProtoSubcategory(subcategory))
	}
	return connect.NewResponse(response), nil
}

// CreateSubcategory adds a subcategory under one of the caller's categories.
func (s *CategoryService) CreateSubcategory(ctx context.Context, request *connect.Request[wdidv1.CreateSubcategoryRequest]) (*connect.Response[wdidv1.CreateSubcategoryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	now := time.Now().UTC()
	subcategory := domain.Subcategory{
		ID:            domain.NewID(),
		UserID:        userID,
		CategoryID:    request.Msg.GetCategoryId(),
		Name:          request.Msg.GetName(),
		Description:   request.Msg.GetDescription(),
		Status:        fromProtoSubcategoryStatus(request.Msg.GetStatus()),
		Progress:      int(request.Msg.GetProgress()),
		TargetOutcome: request.Msg.GetTargetOutcome(),
		TargetDate:    request.Msg.GetTargetDate(),
		Links:         fromProtoLinks(request.Msg.GetLinks()),
		SortOrder:     int(request.Msg.GetSortOrder()),
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	subcategory.Normalize()
	if err := s.store.SaveSubcategory(subcategory); err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.CreateSubcategoryResponse{Subcategory: toProtoSubcategory(subcategory)}), nil
}

// UpdateSubcategory changes the mutable fields of a subcategory. Its category
// and user are preserved.
func (s *CategoryService) UpdateSubcategory(ctx context.Context, request *connect.Request[wdidv1.UpdateSubcategoryRequest]) (*connect.Response[wdidv1.UpdateSubcategoryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	subcategory, err := s.store.Subcategory(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}

	subcategory.Name = request.Msg.GetName()
	subcategory.Description = request.Msg.GetDescription()
	subcategory.Status = fromProtoSubcategoryStatus(request.Msg.GetStatus())
	subcategory.Progress = int(request.Msg.GetProgress())
	subcategory.TargetOutcome = request.Msg.GetTargetOutcome()
	subcategory.TargetDate = request.Msg.GetTargetDate()
	subcategory.Links = fromProtoLinks(request.Msg.GetLinks())
	subcategory.SortOrder = int(request.Msg.GetSortOrder())
	subcategory.UpdatedAt = time.Now().UTC()
	subcategory.Normalize()
	if err := s.store.SaveSubcategory(subcategory); err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.UpdateSubcategoryResponse{Subcategory: toProtoSubcategory(subcategory)}), nil
}

// ArchiveSubcategory hides a subcategory from entry selectors while keeping it
// in historical reporting.
func (s *CategoryService) ArchiveSubcategory(ctx context.Context, request *connect.Request[wdidv1.ArchiveSubcategoryRequest]) (*connect.Response[wdidv1.ArchiveSubcategoryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	subcategory, err := s.store.Subcategory(userID, request.Msg.GetId())
	if err != nil {
		return nil, toConnectError(err)
	}

	subcategory.Archived = request.Msg.GetArchived()
	subcategory.UpdatedAt = time.Now().UTC()
	if err := s.store.SaveSubcategory(subcategory); err != nil {
		return nil, toConnectError(err)
	}

	return connect.NewResponse(&wdidv1.ArchiveSubcategoryResponse{Subcategory: toProtoSubcategory(subcategory)}), nil
}

// DeleteSubcategory removes an unreferenced subcategory. Referenced
// subcategories fail with CodeFailedPrecondition and must be archived instead.
func (s *CategoryService) DeleteSubcategory(ctx context.Context, request *connect.Request[wdidv1.DeleteSubcategoryRequest]) (*connect.Response[wdidv1.DeleteSubcategoryResponse], error) {
	userID, err := userIDFromContext(ctx, s.auth)
	if err != nil {
		return nil, toConnectError(err)
	}

	if err := s.store.DeleteSubcategory(userID, request.Msg.GetId()); err != nil {
		return nil, toConnectError(err)
	}
	return connect.NewResponse(&wdidv1.DeleteSubcategoryResponse{}), nil
}

func toProtoCategory(category domain.Category) *wdidv1.Category {
	return &wdidv1.Category{
		Id:        category.ID,
		Name:      category.Name,
		Role:      toProtoCategoryRole(category.Role),
		Color:     category.Color,
		SortOrder: int32(category.SortOrder),
		Archived:  category.Archived,
		CreatedAt: timestamppb.New(category.CreatedAt),
		UpdatedAt: timestamppb.New(category.UpdatedAt),
	}
}

func toProtoSubcategory(subcategory domain.Subcategory) *wdidv1.Subcategory {
	return &wdidv1.Subcategory{
		Id:            subcategory.ID,
		CategoryId:    subcategory.CategoryID,
		Name:          subcategory.Name,
		Description:   subcategory.Description,
		Status:        toProtoSubcategoryStatus(subcategory.Status),
		Progress:      int32(subcategory.Progress),
		TargetOutcome: subcategory.TargetOutcome,
		TargetDate:    subcategory.TargetDate,
		Links:         toProtoLinks(subcategory.Links),
		SortOrder:     int32(subcategory.SortOrder),
		Archived:      subcategory.Archived,
		CreatedAt:     timestamppb.New(subcategory.CreatedAt),
		UpdatedAt:     timestamppb.New(subcategory.UpdatedAt),
	}
}

func toProtoCategoryRole(role domain.CategoryRole) wdidv1.CategoryRole {
	switch role {
	case domain.CategoryRoleInitiative:
		return wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE
	case domain.CategoryRoleSupport:
		return wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT
	case domain.CategoryRoleOther:
		return wdidv1.CategoryRole_CATEGORY_ROLE_OTHER
	default:
		return wdidv1.CategoryRole_CATEGORY_ROLE_UNSPECIFIED
	}
}

func fromProtoCategoryRole(role wdidv1.CategoryRole) domain.CategoryRole {
	switch role {
	case wdidv1.CategoryRole_CATEGORY_ROLE_INITIATIVE:
		return domain.CategoryRoleInitiative
	case wdidv1.CategoryRole_CATEGORY_ROLE_SUPPORT:
		return domain.CategoryRoleSupport
	case wdidv1.CategoryRole_CATEGORY_ROLE_OTHER:
		return domain.CategoryRoleOther
	default:
		return ""
	}
}

func toProtoSubcategoryStatus(status domain.SubcategoryStatus) wdidv1.SubcategoryStatus {
	switch status {
	case domain.SubcategoryPlanned:
		return wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_PLANNED
	case domain.SubcategoryActive:
		return wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE
	case domain.SubcategoryBlocked:
		return wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_BLOCKED
	case domain.SubcategoryDone:
		return wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_DONE
	case domain.SubcategoryArchived:
		return wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ARCHIVED
	default:
		return wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_UNSPECIFIED
	}
}

func fromProtoSubcategoryStatus(status wdidv1.SubcategoryStatus) domain.SubcategoryStatus {
	switch status {
	case wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_PLANNED:
		return domain.SubcategoryPlanned
	case wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ACTIVE:
		return domain.SubcategoryActive
	case wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_BLOCKED:
		return domain.SubcategoryBlocked
	case wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_DONE:
		return domain.SubcategoryDone
	case wdidv1.SubcategoryStatus_SUBCATEGORY_STATUS_ARCHIVED:
		return domain.SubcategoryArchived
	default:
		return ""
	}
}

func toProtoLinks(links []domain.Link) []*wdidv1.Link {
	if len(links) == 0 {
		return nil
	}
	result := make([]*wdidv1.Link, 0, len(links))
	for _, link := range links {
		result = append(result, &wdidv1.Link{Label: link.Label, Url: link.URL})
	}
	return result
}

func fromProtoLinks(links []*wdidv1.Link) []domain.Link {
	if len(links) == 0 {
		return nil
	}
	result := make([]domain.Link, 0, len(links))
	for _, link := range links {
		result = append(result, domain.Link{Label: link.GetLabel(), URL: link.GetUrl()})
	}
	return result
}
