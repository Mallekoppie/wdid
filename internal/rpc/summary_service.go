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

// SummaryService implements the generated SummaryService handler. Its period
// report is the single authoritative aggregate: clients render these numbers
// instead of recomputing totals from entry listings.
type SummaryService struct {
	store *store.Store
	auth  *auth.Service
	now   func() time.Time
}

// SummaryServiceOption adjusts the service, which lets tests control the clock
// used to resolve "this week".
type SummaryServiceOption func(*SummaryService)

// WithSummaryClock replaces the service's clock.
func WithSummaryClock(now func() time.Time) SummaryServiceOption {
	return func(service *SummaryService) {
		if now != nil {
			service.now = now
		}
	}
}

// NewSummaryService builds the SummaryService implementation.
func NewSummaryService(database *store.Store, authService *auth.Service, options ...SummaryServiceOption) *SummaryService {
	service := &SummaryService{store: database, auth: authService, now: time.Now}
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

func toProtoPeriodReport(report domain.PeriodReport) *wdidv1.PeriodReport {
	response := &wdidv1.PeriodReport{
		FromDate:      report.FromDate,
		ToDate:        report.ToDate,
		Total:         minutesDuration(report.TotalMinutes),
		EntryCount:    int32(report.EntryCount),
		Categories:    make([]*wdidv1.CategoryAllocation, 0, len(report.Categories)),
		Subcategories: make([]*wdidv1.SubcategoryAllocation, 0, len(report.Subcategories)),
		SupportPeople: make([]*wdidv1.SupportPersonAllocation, 0, len(report.SupportPeople)),
		SupportModes:  make([]*wdidv1.SupportModeAllocation, 0, len(report.SupportModes)),
		Weeks:         make([]*wdidv1.WeekRhythm, 0, len(report.Weeks)),
		Notes:         make([]*wdidv1.PeriodNote, 0, len(report.Notes)),
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
			SubcategoryId: total.SubcategoryID,
			CategoryId:    total.CategoryID,
			Name:          total.Name,
			Duration:      minutesDuration(total.Minutes),
			EntryCount:    int32(total.EntryCount),
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

	return response
}
