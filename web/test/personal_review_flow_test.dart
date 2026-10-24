import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/checkin_api.dart';
import 'package:wdid_web/data/demo_repository.dart';
import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/check_in.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/utils/time_utils.dart';

import 'fake_auth_api.dart';
import 'fake_checkin_api.dart';
import 'fake_preferences_api.dart';
import 'fake_summary_api.dart';

Category category(String id, String name, CategoryRole role) => Category(
  id: id,
  name: name,
  role: role,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, 1),
);

Subcategory subcategory(String id, String categoryId, String name) =>
    Subcategory(
      id: id,
      categoryId: categoryId,
      name: name,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
    );

CheckIn personalReview({
  String id = 'personal-1',
  String focusNotes = 'Original focus',
  String summaryMarkdown = '',
}) => CheckIn(
  id: id,
  kind: CheckInKind.personal,
  state: CheckInState.draft,
  focusNotes: focusNotes,
  summaryMarkdown: summaryMarkdown,
  periodStart: DateTime(2026, 10, 17),
  periodEnd: DateTime(2026, 10, 23),
  createdAt: DateTime.utc(2026, 10, 23, 12),
  totals: const CheckInTotals(minutes: 240, supportByPerson: {'Priya': 60}),
);

CheckIn finalManager() => CheckIn(
  id: 'manager-final',
  kind: CheckInKind.manager,
  state: CheckInState.final_,
  audience: CheckInAudience.oneOnOne,
  focusNotes: 'Manager focus',
  periodStart: DateTime(2026, 10, 1),
  periodEnd: DateTime(2026, 10, 10),
  createdAt: DateTime.utc(2026, 10, 10, 12),
  totals: const CheckInTotals(minutes: 240),
);

PeriodReport aggregateReport() => const PeriodReport(
  fromDate: '1970-01-01',
  toDate: '1970-01-01',
  totalMinutes: 240,
  entryCount: 3,
  categories: [
    CategoryAllocation(
      categoryId: 'cat-projects',
      name: 'Projects',
      role: CategoryRole.initiative,
      minutes: 180,
      entryCount: 2,
    ),
    CategoryAllocation(
      categoryId: 'cat-support',
      name: 'Support',
      role: CategoryRole.support,
      minutes: 60,
      entryCount: 1,
    ),
  ],
  subcategories: [
    SubcategoryAllocation(
      subcategoryId: 'sub-1',
      categoryId: 'cat-projects',
      name: 'Billing migration',
      minutes: 180,
      entryCount: 2,
    ),
    SubcategoryAllocation(
      subcategoryId: 'mode-1',
      categoryId: 'cat-support',
      name: 'Unblock',
      minutes: 60,
      entryCount: 1,
    ),
  ],
  supportPeople: [
    SupportPersonAllocation(person: 'Priya', minutes: 60, interactions: 2),
  ],
  weeks: [
    WeekRhythm(
      weekStartDate: '2026-10-19',
      minutes: 240,
      topCategoryId: 'cat-projects',
      topCategoryName: 'Projects',
    ),
  ],
);

PeriodReport reportFor(DateTime start, DateTime end) {
  final base = aggregateReport();
  return PeriodReport(
    fromDate: isoDate(start),
    toDate: isoDate(end),
    totalMinutes: base.totalMinutes,
    entryCount: base.entryCount,
    categories: base.categories,
    subcategories: base.subcategories,
    supportPeople: base.supportPeople,
    weeks: base.weeks,
  );
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeCheckInApi checkInApi,
    required String route,
    FakeSummaryApi? summaryApi,
    AppSettings settings = const AppSettings(),
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        repository: DemoWdidRepository(latency: Duration.zero),
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: route,
        categoryApiBuilder: (_) => FakeCategoryApi(
          categories: [
            category('cat-projects', 'Projects', CategoryRole.initiative),
            category('cat-support', 'Support', CategoryRole.support),
          ],
          subcategories: [
            subcategory('sub-1', 'cat-projects', 'Billing migration'),
            subcategory('mode-1', 'cat-support', 'Unblock'),
          ],
        ),
        settingsApiBuilder: (_) => FakeSettingsApi(settings: settings),
        summaryApiBuilder: (_) =>
            summaryApi ?? FakeSummaryApi(report: aggregateReport(), echoDates: true),
        checkInApiBuilder: (_) => checkInApi,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var index = 0; index < 8; index++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }
  }

  String reviewRoute(DateTime start, DateTime end, String timeframe) =>
      '/checkins/review?start=${isoDate(start)}'
      '&end=${isoDate(end)}&timeframe=$timeframe';

  testWidgets('the timeframe picker offers every preset and opens live', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final api = FakeCheckInApi();
    final summary = FakeSummaryApi(
      report: aggregateReport(),
      echoDates: true,
    );
    await pumpApp(
      tester,
      checkInApi: api,
      summaryApi: summary,
      route: '/checkins',
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'New review'));
    await tester.pumpAndSettle();

    for (final label in [
      'Last 7 days',
      'Last 30 days',
      'This week',
      'This month',
      'Since last manager check-in',
      'Custom range',
    ]) {
      expect(
        find.widgetWithText(ChoiceChip, label),
        findsOneWidget,
        reason: 'missing timeframe $label',
      );
    }
    // Choosing a timeframe has not contacted the write path yet.
    expect(api.createRequests, isEmpty);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Last 30 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open review'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Personal review ·'), findsOneWidget);
    expect(find.text('Reflection'), findsOneWidget);
    expect(find.text('Time by category'), findsOneWidget);
    expect(find.text('Billing migration'), findsOneWidget);
    expect(
      summary.requests.any(
        (request) =>
            request.from == isoDate(addDays(today, -29)) &&
            request.to == isoDate(today),
      ),
      isTrue,
      reason: 'the live review must read the same period report as a check-in',
    );
    expect(api.createRequests, isEmpty);
  });

  testWidgets('saving a live review creates a personal review with its notes', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final api = FakeCheckInApi();
    await pumpApp(tester, checkInApi: api, route: '/checkins');

    await tester.tap(find.widgetWithText(OutlinedButton, 'New review'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Last 7 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open review'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).at(0),
      'What moved this week',
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      '## Highlights\n- Backfill shipped',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save review'));
    await tester.pumpAndSettle();

    expect(api.createRequests, hasLength(1));
    final draft = api.createRequests.single;
    expect(draft.kind, CheckInKind.personal);
    expect(draft.audience, isNull);
    expect(draft.periodStart, addDays(today, -6));
    expect(draft.periodEnd, today);
    expect(draft.focusNotes, 'What moved this week');
    expect(api.updateRequests.single.summaryMarkdown, contains('Backfill'));

    expect(
      find.text('Personal review — editable, and never moves the manager boundary.'),
      findsOneWidget,
    );
    expect(find.text('What moved this week'), findsOneWidget);
  });

  testWidgets('leaving a live review without saving discards it', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final api = FakeCheckInApi();
    await pumpApp(
      tester,
      checkInApi: api,
      route: reviewRoute(addDays(today, -6), today, 'last7Days'),
    );

    expect(find.text('Time by category'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Leave without saving'));
    await tester.pumpAndSettle();

    expect(api.createRequests, isEmpty);
    expect(find.text('Check-ins'), findsWidgets);
  });

  testWidgets('a saved personal review can be edited', (tester) async {
    final api = FakeCheckInApi(checkIns: [personalReview(), finalManager()]);
    await pumpApp(tester, checkInApi: api, route: '/checkins/personal-1');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit review'));
    await tester.pumpAndSettle();
    expect(find.text('Edit personal review'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Revised focus');
    await tester.tap(find.widgetWithText(FilledButton, 'Save review'));
    await tester.pumpAndSettle();

    expect(api.updateRequests, hasLength(1));
    expect(api.updateRequests.single.id, 'personal-1');
    expect(api.updateRequests.single.focusNotes, 'Revised focus');
    expect(find.text('Revised focus'), findsOneWidget);

    // The summary stays editable on a personal review.
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '## What changed\n- Focused on the backfill',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save summary'));
    await tester.pumpAndSettle();

    expect(api.updateRequests, hasLength(2));
    expect(
      api.updateRequests.last.summaryMarkdown,
      contains('Focused on the backfill'),
    );
  });

  testWidgets('a saved personal review can be deleted without touching the manager check-in', (
    tester,
  ) async {
    final api = FakeCheckInApi(checkIns: [personalReview(), finalManager()]);
    await pumpApp(tester, checkInApi: api, route: '/checkins/personal-1');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete review'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this personal review?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete review').last);
    await tester.pumpAndSettle();

    expect(api.deleteRequests, ['personal-1']);
    expect(find.text('Check-ins'), findsWidgets);
    // The final manager check-in is untouched, so the boundary is unchanged.
    expect(find.text('Manager focus'), findsOneWidget);
    expect(find.text('Original focus'), findsNothing);
  });

  testWidgets('the live review handles loading, error and empty states', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final route = reviewRoute(addDays(today, -6), today, 'last7Days');

    // Loading.
    final gate = Completer<PeriodReport>();
    final summary = FakeSummaryApi(report: aggregateReport(), echoDates: true)
      ..gate = gate;
    await pumpApp(
      tester,
      checkInApi: FakeCheckInApi(),
      summaryApi: summary,
      route: route,
      settle: false,
    );
    expect(find.text('Loading the period report…'), findsOneWidget);
    gate.complete(reportFor(addDays(today, -6), today));
    await tester.pumpAndSettle();
    expect(find.text('Time by category'), findsOneWidget);
  });

  testWidgets('the live review reports an aggregate failure and retries', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final summary = FakeSummaryApi(report: aggregateReport(), echoDates: true)
      ..failure = const SummaryFailure('The service is unreachable.');
    await pumpApp(
      tester,
      checkInApi: FakeCheckInApi(),
      summaryApi: summary,
      route: reviewRoute(addDays(today, -6), today, 'last7Days'),
      settle: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load the period report'), findsOneWidget);

    summary.failure = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load the period report'), findsNothing);
    expect(find.text('Time by category'), findsOneWidget);
  });

  testWidgets('an empty period is explained but can still be saved', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final api = FakeCheckInApi();
    await pumpApp(
      tester,
      checkInApi: api,
      summaryApi: FakeSummaryApi(
        report: const PeriodReport(
          fromDate: '1970-01-01',
          toDate: '1970-01-01',
          totalMinutes: 0,
          entryCount: 0,
        ),
        echoDates: true,
      ),
      route: reviewRoute(addDays(today, -6), today, 'last7Days'),
    );

    expect(find.text('Nothing logged in this period'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save empty review'));
    await tester.pumpAndSettle();

    expect(api.createRequests, hasLength(1));
    expect(api.createRequests.single.kind, CheckInKind.personal);
  });

  testWidgets('a save failure is shown without losing the review', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final api = FakeCheckInApi()
      ..failure = const CheckInFailure('The service is unreachable.');
    await pumpApp(
      tester,
      checkInApi: api,
      route: reviewRoute(addDays(today, -6), today, 'last7Days'),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save review'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save the review'), findsOneWidget);
    expect(find.text('Reflection'), findsOneWidget);
  });

  testWidgets('the weekly cadence shows a dismissible, non-blocking prompt', (
    tester,
  ) async {
    final api = FakeCheckInApi();
    await pumpApp(
      tester,
      checkInApi: api,
      settings: const AppSettings(reviewCadence: ReviewCadence.weekly),
      route: '/today',
    );

    expect(find.text('Last week is ready to review'), findsOneWidget);
    expect(find.text('Review now'), findsOneWidget);
    // The prompt never creates a draft on its own.
    expect(api.createRequests, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text('Last week is ready to review'), findsNothing);
    expect(api.createRequests, isEmpty);
  });

  testWidgets('the monthly cadence prompts and Review now opens a live review', (
    tester,
  ) async {
    final api = FakeCheckInApi();
    final summary = FakeSummaryApi(
      report: aggregateReport(),
      echoDates: true,
    );
    await pumpApp(
      tester,
      checkInApi: api,
      summaryApi: summary,
      settings: const AppSettings(reviewCadence: ReviewCadence.monthly),
      route: '/today',
    );

    expect(find.text('Last month is ready to review'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Review now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Personal review ·'), findsOneWidget);
    expect(find.text('Time by category'), findsOneWidget);
    expect(api.createRequests, isEmpty);
  });
}
