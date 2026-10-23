package rpc_test

import (
	"context"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"connectrpc.com/connect"

	wdidv1 "github.com/Mallekoppie/wdid/internal/gen/wdid/v1"
	"github.com/Mallekoppie/wdid/internal/gen/wdid/v1/wdidv1connect"
)

// testClock is a manually advanced clock for timer transitions.
type testClock struct {
	mu  sync.Mutex
	now time.Time
}

func newTestClock(start time.Time) *testClock {
	return &testClock{now: start}
}

func (c *testClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *testClock) Advance(duration time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(duration)
}

func timerClient(server *httptest.Server, options ...connect.ClientOption) wdidv1connect.TimerServiceClient {
	return wdidv1connect.NewTimerServiceClient(server.Client(), server.URL, options...)
}

func TestTimerServiceRequiresAuthentication(t *testing.T) {
	server, _ := newDomainServer(t)

	_, err := timerClient(server).GetActiveTimer(context.Background(), connect.NewRequest(&wdidv1.GetActiveTimerRequest{}))
	if connect.CodeOf(err) != connect.CodeUnauthenticated {
		t.Fatalf("code = %v, want unauthenticated", connect.CodeOf(err))
	}
}

func TestTimerServiceTransitionsAndSavedEntry(t *testing.T) {
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	clock := newTestClock(start)
	server, _ := newDomainServerWithClock(t, clock.Now)
	token := bootstrapToken(t, server)
	categoryID, subcategoryID := createEntryTaxonomy(t, server, token)
	client := timerClient(server)

	started, err := client.StartTimer(context.Background(), withBearer(&wdidv1.StartTimerRequest{
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   "Backfill script",
	}, token))
	if err != nil {
		t.Fatalf("start timer: %v", err)
	}
	timer := started.Msg.GetTimer()
	if timer.GetCategoryId() != categoryID || timer.GetSubcategoryId() != subcategoryID {
		t.Fatalf("timer attribution = %s/%s", timer.GetCategoryId(), timer.GetSubcategoryId())
	}
	if timer.GetPaused() {
		t.Fatal("new timer is paused")
	}
	if timer.GetElapsed().AsDuration() != 0 {
		t.Fatalf("initial elapsed = %v, want zero", timer.GetElapsed().AsDuration())
	}

	// A second start is rejected: one timer runs per user.
	_, err = client.StartTimer(context.Background(), withBearer(&wdidv1.StartTimerRequest{
		CategoryId: categoryID,
	}, token))
	if connect.CodeOf(err) != connect.CodeFailedPrecondition {
		t.Fatalf("second start code = %v, want failed precondition", connect.CodeOf(err))
	}

	clock.Advance(10 * time.Minute)
	paused, err := client.PauseTimer(context.Background(), withBearer(&wdidv1.PauseTimerRequest{}, token))
	if err != nil {
		t.Fatalf("pause timer: %v", err)
	}
	if !paused.Msg.GetTimer().GetPaused() {
		t.Fatal("timer is not paused")
	}

	// Paused time does not count.
	clock.Advance(20 * time.Minute)
	active, err := client.GetActiveTimer(context.Background(), withBearer(&wdidv1.GetActiveTimerRequest{}, token))
	if err != nil {
		t.Fatalf("get active timer: %v", err)
	}
	if got := active.Msg.GetTimer().GetElapsed().AsDuration(); got != 10*time.Minute {
		t.Fatalf("paused elapsed = %v, want 10m", got)
	}
	if got := active.Msg.GetBlockLimit().AsDuration(); got != 240*time.Minute {
		t.Fatalf("block limit = %v, want the seeded 240m", got)
	}

	resumed, err := client.ResumeTimer(context.Background(), withBearer(&wdidv1.ResumeTimerRequest{}, token))
	if err != nil {
		t.Fatalf("resume timer: %v", err)
	}
	if resumed.Msg.GetTimer().GetPaused() {
		t.Fatal("timer is still paused")
	}

	clock.Advance(15 * time.Minute)
	stopped, err := client.StopTimer(context.Background(), withBearer(&wdidv1.StopTimerRequest{
		Action: wdidv1.TimerStopAction_TIMER_STOP_ACTION_UNSPECIFIED,
	}, token))
	if err != nil {
		t.Fatalf("stop timer: %v", err)
	}
	entry := stopped.Msg.GetEntry()
	if stopped.Msg.GetDiscarded() {
		t.Fatal("stop discarded the timer")
	}
	if entry.GetDuration().AsDuration() != 25*time.Minute {
		t.Fatalf("entry duration = %v, want 25m with pauses excluded", entry.GetDuration().AsDuration())
	}
	if entry.GetSource() != wdidv1.EntrySource_ENTRY_SOURCE_TIMER {
		t.Fatalf("entry source = %v, want timer", entry.GetSource())
	}
	if entry.GetCategoryId() != categoryID || entry.GetSubcategoryId() != subcategoryID {
		t.Fatalf("entry attribution = %s/%s", entry.GetCategoryId(), entry.GetSubcategoryId())
	}
	if entry.GetDescription() != "Backfill script" {
		t.Fatalf("entry description = %q", entry.GetDescription())
	}

	listed, err := entryClient(server).ListEntries(context.Background(), withBearer(&wdidv1.ListEntriesRequest{
		LocalDate: entry.GetLocalDate(),
	}, token))
	if err != nil {
		t.Fatalf("list entries: %v", err)
	}
	if len(listed.Msg.GetEntries()) != 1 || listed.Msg.GetEntries()[0].GetId() != entry.GetId() {
		t.Fatalf("entries = %+v, want the timer entry", listed.Msg.GetEntries())
	}

	after, err := client.GetActiveTimer(context.Background(), withBearer(&wdidv1.GetActiveTimerRequest{}, token))
	if err != nil {
		t.Fatalf("get active timer after stop: %v", err)
	}
	if after.Msg.GetTimer() != nil {
		t.Fatalf("timer still active after stop: %+v", after.Msg.GetTimer())
	}
}

func TestTimerServiceTransitionsOverGRPCWeb(t *testing.T) {
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	clock := newTestClock(start)
	server, _ := newDomainServerWithClock(t, clock.Now)
	token := bootstrapToken(t, server)
	categoryID, subcategoryID := createEntryTaxonomy(t, server, token)
	client := timerClient(server, connect.WithGRPCWeb())

	if _, err := client.StartTimer(context.Background(), withBearer(&wdidv1.StartTimerRequest{
		CategoryId:    categoryID,
		SubcategoryId: subcategoryID,
		Description:   "Web timer",
	}, token)); err != nil {
		t.Fatalf("gRPC-Web StartTimer: %v", err)
	}

	clock.Advance(time.Minute)
	if _, err := client.PauseTimer(context.Background(), withBearer(&wdidv1.PauseTimerRequest{}, token)); err != nil {
		t.Fatalf("gRPC-Web PauseTimer: %v", err)
	}

	// Paused time is excluded.
	clock.Advance(5 * time.Minute)
	active, err := client.GetActiveTimer(context.Background(), withBearer(&wdidv1.GetActiveTimerRequest{}, token))
	if err != nil {
		t.Fatalf("gRPC-Web GetActiveTimer: %v", err)
	}
	if got := active.Msg.GetTimer().GetElapsed().AsDuration(); got != time.Minute {
		t.Fatalf("paused elapsed = %v, want 1m", got)
	}

	if _, err := client.ResumeTimer(context.Background(), withBearer(&wdidv1.ResumeTimerRequest{}, token)); err != nil {
		t.Fatalf("gRPC-Web ResumeTimer: %v", err)
	}
	clock.Advance(time.Minute)

	stopped, err := client.StopTimer(context.Background(), withBearer(&wdidv1.StopTimerRequest{}, token))
	if err != nil {
		t.Fatalf("gRPC-Web StopTimer: %v", err)
	}
	if got := stopped.Msg.GetEntry().GetDuration().AsDuration(); got != 2*time.Minute {
		t.Fatalf("gRPC-Web entry = %v, want 2m", got)
	}
}

func TestTimerServiceRejectsShortStopsUnlessDiscarded(t *testing.T) {
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)

	for _, grpcWeb := range []bool{false, true} {
		name := "connect"
		if grpcWeb {
			name = "grpc-web"
		}
		t.Run(name, func(t *testing.T) {
			clock := newTestClock(start)
			server, _ := newDomainServerWithClock(t, clock.Now)
			token := bootstrapToken(t, server)
			categoryID, _ := createEntryTaxonomy(t, server, token)

			var options []connect.ClientOption
			if grpcWeb {
				options = append(options, connect.WithGRPCWeb())
			}
			client := timerClient(server, options...)

			if _, err := client.StartTimer(context.Background(), withBearer(&wdidv1.StartTimerRequest{
				CategoryId:  categoryID,
				Description: "Quick check",
			}, token)); err != nil {
				t.Fatalf("start timer: %v", err)
			}

			clock.Advance(30 * time.Second)
			_, err := client.StopTimer(context.Background(), withBearer(&wdidv1.StopTimerRequest{}, token))
			if connect.CodeOf(err) != connect.CodeFailedPrecondition {
				t.Fatalf("short stop code = %v, want failed precondition", connect.CodeOf(err))
			}
			if !strings.Contains(err.Error(), "timer_too_short") {
				t.Fatalf("short stop message = %q, want the timer_too_short reason", err.Error())
			}

			stopped, err := client.StopTimer(context.Background(), withBearer(&wdidv1.StopTimerRequest{
				Action: wdidv1.TimerStopAction_TIMER_STOP_ACTION_DISCARD,
			}, token))
			if err != nil {
				t.Fatalf("discard short timer: %v", err)
			}
			if !stopped.Msg.GetDiscarded() || stopped.Msg.GetEntry() != nil {
				t.Fatalf("discard response = %+v", stopped.Msg)
			}
		})
	}
}

func TestTimerServiceBlockLimitOffersKeepTrimAndDiscard(t *testing.T) {
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)

	cases := []struct {
		name     string
		action   wdidv1.TimerStopAction
		minutes  time.Duration
		discard  bool
		conflict bool
	}{
		{"save conflicts", wdidv1.TimerStopAction_TIMER_STOP_ACTION_UNSPECIFIED, 0, false, true},
		{"keep saves everything", wdidv1.TimerStopAction_TIMER_STOP_ACTION_KEEP, 300 * time.Minute, false, false},
		{"trim saves the limit", wdidv1.TimerStopAction_TIMER_STOP_ACTION_TRIM, 240 * time.Minute, false, false},
		{"discard saves nothing", wdidv1.TimerStopAction_TIMER_STOP_ACTION_DISCARD, 0, true, false},
	}

	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			clock := newTestClock(start)
			server, _ := newDomainServerWithClock(t, clock.Now)
			token := bootstrapToken(t, server)
			categoryID, _ := createEntryTaxonomy(t, server, token)
			client := timerClient(server)

			if _, err := client.StartTimer(context.Background(), withBearer(&wdidv1.StartTimerRequest{
				CategoryId:  categoryID,
				Description: "Long migration",
			}, token)); err != nil {
				t.Fatalf("start timer: %v", err)
			}

			clock.Advance(5 * time.Hour)
			stopped, err := client.StopTimer(context.Background(), withBearer(&wdidv1.StopTimerRequest{
				Action: testCase.action,
			}, token))
			if testCase.conflict {
				if connect.CodeOf(err) != connect.CodeFailedPrecondition {
					t.Fatalf("code = %v, want failed precondition", connect.CodeOf(err))
				}
				if !strings.Contains(err.Error(), "timer_block_limit") {
					t.Fatalf("message = %q, want the timer_block_limit reason", err.Error())
				}
				return
			}
			if err != nil {
				t.Fatalf("stop timer: %v", err)
			}
			if stopped.Msg.GetDiscarded() != testCase.discard {
				t.Fatalf("discarded = %v, want %v", stopped.Msg.GetDiscarded(), testCase.discard)
			}
			if testCase.discard {
				if stopped.Msg.GetEntry() != nil {
					t.Fatalf("discard returned an entry: %+v", stopped.Msg.GetEntry())
				}
				return
			}
			if got := stopped.Msg.GetEntry().GetDuration().AsDuration(); got != testCase.minutes {
				t.Fatalf("entry duration = %v, want %v", got, testCase.minutes)
			}
		})
	}
}

func TestTimerServiceBlockLimitOverGRPCWeb(t *testing.T) {
	start := time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC)
	clock := newTestClock(start)
	server, _ := newDomainServerWithClock(t, clock.Now)
	token := bootstrapToken(t, server)
	categoryID, _ := createEntryTaxonomy(t, server, token)
	client := timerClient(server, connect.WithGRPCWeb())

	if _, err := client.StartTimer(context.Background(), withBearer(&wdidv1.StartTimerRequest{
		CategoryId:  categoryID,
		Description: "Web long timer",
	}, token)); err != nil {
		t.Fatalf("gRPC-Web StartTimer: %v", err)
	}

	clock.Advance(5 * time.Hour)
	_, err := client.StopTimer(context.Background(), withBearer(&wdidv1.StopTimerRequest{}, token))
	if connect.CodeOf(err) != connect.CodeFailedPrecondition ||
		!strings.Contains(err.Error(), "timer_block_limit") {
		t.Fatalf("gRPC-Web long stop = %v, want a block-limit conflict", err)
	}

	stopped, err := client.StopTimer(context.Background(), withBearer(&wdidv1.StopTimerRequest{
		Action: wdidv1.TimerStopAction_TIMER_STOP_ACTION_TRIM,
	}, token))
	if err != nil {
		t.Fatalf("gRPC-Web Trim: %v", err)
	}
	if got := stopped.Msg.GetEntry().GetDuration().AsDuration(); got != 240*time.Minute {
		t.Fatalf("gRPC-Web trimmed entry = %v, want 240m", got)
	}
}

func TestTimerServiceIsolatesAccounts(t *testing.T) {
	server, database := newDomainServer(t)
	firstToken := bootstrapToken(t, server)
	categoryID, _ := createEntryTaxonomy(t, server, firstToken)

	if _, err := timerClient(server).StartTimer(context.Background(), withBearer(&wdidv1.StartTimerRequest{
		CategoryId:  categoryID,
		Description: "Private work",
	}, firstToken)); err != nil {
		t.Fatalf("start timer: %v", err)
	}

	code := createInvite(t, database, "second-timer@example.com")
	second, err := authClient(server).RegisterAccount(context.Background(), connect.NewRequest(&wdidv1.RegisterAccountRequest{
		Email:       "second-timer@example.com",
		Password:    testPassword,
		DisplayName: "Second",
		InviteCode:  code,
	}))
	if err != nil {
		t.Fatalf("register second account: %v", err)
	}

	active, err := timerClient(server).GetActiveTimer(context.Background(), withBearer(&wdidv1.GetActiveTimerRequest{}, second.Msg.GetToken()))
	if err != nil {
		t.Fatalf("second account get timer: %v", err)
	}
	if active.Msg.GetTimer() != nil {
		t.Fatalf("second account sees the first account's timer: %+v", active.Msg.GetTimer())
	}
}
