import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/checkin_api.dart';
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

CheckIn checkIn({
  String id = 'checkin-manager',
  CheckInKind kind = CheckInKind.manager,
  CheckInAudience? audience = CheckInAudience.oneOnOne,
  CheckInState state = CheckInState.draft,
  String focusNotes = 'Manager focus',
  String summaryMarkdown = '',
  DateTime? createdAt,
  DateTime? periodStart,
  DateTime? periodEnd,
}) {
  return CheckIn(
    id: id,
    kind: kind,
    audience: kind == CheckInKind.manager ? audience : null,
    state: state,
    focusNotes: focusNotes,
    summaryMarkdown: summaryMarkdown,
    periodStart: periodStart ?? DateTime(2026, 10, 1),
    periodEnd: periodEnd ?? DateTime(2026, 10, 20),
    createdAt: createdAt ?? DateTime.utc(2026, 10, 20, 12),
    updatedAt: DateTime.utc(2026, 10, 20, 12),
    totals: const CheckInTotals(minutes: 240, supportByPerson: {'Priya': 60}),
  );
}

const report = PeriodReport(
  fromDate: '2026-10-01',
  toDate: '2026-10-20',
  totalMinutes: 240,
  entryCount: 3,
  // Deliberately different from the 60m/2 per-person row so the detail stats
  // prove they read the authoritative totals.
  supportMinutes: 45,
  supportInteractions: 1,
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
      weekStartDate: '2026-09-28',
      minutes: 120,
      topCategoryId: 'cat-projects',
      topCategoryName: 'Projects',
    ),
    WeekRhythm(
      weekStartDate: '2026-10-05',
      minutes: 120,
      topCategoryId: 'cat-support',
      topCategoryName: 'Support',
    ),
  ],
);

void main() {
  Future<void> pumpCheckIns(
    WidgetTester tester, {
    required FakeCheckInApi checkInApi,
    required String route,
    FakeSummaryApi? summaryApi,
    bool hasAIKey = true,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
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
        settingsApiBuilder: (_) =>
            FakeSettingsApi(settings: AppSettings(hasAiApiKey: hasAIKey)),
        summaryApiBuilder: (_) => summaryApi ?? FakeSummaryApi(report: report),
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

  testWidgets('lists manager and personal check-ins and filters by kind', (
    tester,
  ) async {
    final api = FakeCheckInApi(
      checkIns: [
        checkIn(focusNotes: 'Manager focus'),
        checkIn(
          id: 'checkin-personal',
          kind: CheckInKind.personal,
          focusNotes: 'Personal focus',
        ),
      ],
    );
    await pumpCheckIns(tester, checkInApi: api, route: '/checkins');

    expect(find.text('Manager focus'), findsOneWidget);
    expect(find.text('Personal focus'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Manager'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Manager'));
    await tester.pumpAndSettle();

    expect(api.lastKind, CheckInKind.manager);
    expect(find.text('Manager focus'), findsOneWidget);
    expect(find.text('Personal focus'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Personal'));
    await tester.pumpAndSettle();

    expect(api.lastKind, CheckInKind.personal);
    expect(find.text('Manager focus'), findsNothing);
    expect(find.text('Personal focus'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();

    expect(api.lastKind, isNull);
    expect(find.text('Manager focus'), findsOneWidget);
    expect(find.text('Personal focus'), findsOneWidget);
  });

  testWidgets('create dialog prefills the server boundary and focus notes', (
    tester,
  ) async {
    final api = FakeCheckInApi(
      checkIns: [checkIn()],
      defaults: CheckInDefaults(
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 10, 22),
        lastFinalCheckInId: 'checkin-final',
      ),
    );
    await pumpCheckIns(tester, checkInApi: api, route: '/checkins');

    await tester.tap(find.widgetWithText(FilledButton, 'Create check-in'));
    await tester.pumpAndSettle();

    expect(find.text(formatFullDate(DateTime(2026, 9, 1))), findsOneWidget);
    expect(find.text(formatFullDate(DateTime(2026, 10, 22))), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'Ship the backfill and keep support small.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create check-in').last);
    await tester.pumpAndSettle();

    expect(api.createRequests, hasLength(1));
    final draft = api.createRequests.single;
    expect(draft.kind, CheckInKind.manager);
    expect(draft.audience, CheckInAudience.oneOnOne);
    expect(draft.periodStart, DateTime(2026, 9, 1));
    expect(draft.periodEnd, DateTime(2026, 10, 22));
    expect(draft.focusNotes, 'Ship the backfill and keep support small.');
  });

  testWidgets('create dialog shows a loading state for the boundary', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = FakeCheckInApi(checkIns: [checkIn()])..defaultsGate = gate;
    await pumpCheckIns(tester, checkInApi: api, route: '/checkins');

    await tester.tap(find.widgetWithText(FilledButton, 'Create check-in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Loading the next period…'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Loading the next period…'), findsNothing);
    expect(find.text(formatFullDate(DateTime(2026, 10, 1))), findsOneWidget);
  });

  testWidgets('create dialog reports a failed boundary and retries', (
    tester,
  ) async {
    final api = FakeCheckInApi(checkIns: [checkIn()])
      ..defaultsFailure = const CheckInFailure(
        'The service is unreachable. Check that the server is running.',
      );
    await pumpCheckIns(tester, checkInApi: api, route: '/checkins');

    await tester.tap(find.widgetWithText(FilledButton, 'Create check-in'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not work out the next period'),
      findsOneWidget,
    );

    api.defaultsFailure = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not work out the next period'),
      findsNothing,
    );
    expect(find.text(formatFullDate(DateTime(2026, 10, 1))), findsOneWidget);
  });

  testWidgets('detail renders every aggregate from the period report', (
    tester,
  ) async {
    final summaryApi = FakeSummaryApi(report: report);
    final api = FakeCheckInApi(checkIns: [checkIn()]);
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-manager',
      summaryApi: summaryApi,
    );

    expect(
      summaryApi.requests.any(
        (request) => request.from == '2026-10-01' && request.to == '2026-10-20',
      ),
      isTrue,
    );
    expect(find.text('Time by category'), findsOneWidget);
    expect(find.text('Time by project'), findsOneWidget);
    expect(find.text('Billing migration'), findsOneWidget);
    expect(find.text('Support by person'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Weekly rhythm'), findsOneWidget);
    expect(find.text('Week of 28 Sep'), findsOneWidget);
    expect(find.text('Week of 5 Oct'), findsOneWidget);
    // The report's total, not the stored snapshot or a local sum.
    expect(find.text('4h'), findsWidgets);
    // The support stat reads the authoritative 45m, not the per-person 60m.
    expect(find.text('45m'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });

  testWidgets('edits and saves the summary as Markdown, including empty', (
    tester,
  ) async {
    final api = FakeCheckInApi(
      checkIns: [checkIn(summaryMarkdown: '## Highlights\n- Old evidence')],
    );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-manager',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '## Highlights\n- Cut invoicing from 40 min to 3 min',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save summary'));
    await tester.pumpAndSettle();

    expect(api.updateRequests, hasLength(1));
    expect(
      api.updateRequests.single.summaryMarkdown,
      '## Highlights\n- Cut invoicing from 40 min to 3 min',
    );
    expect(api.updateSources.single, CheckInSummarySource.manual);
    expect(find.text('Summary saved'), findsOneWidget);

    // An empty summary is a valid state, not a validation error.
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save summary'));
    await tester.pumpAndSettle();

    expect(api.updateRequests, hasLength(2));
    expect(api.updateRequests.last.summaryMarkdown, '');
    expect(find.text('No summary yet'), findsOneWidget);
  });

  testWidgets('changes the audience and uses it to build the prompt', (
    tester,
  ) async {
    final api = FakeCheckInApi(
      checkIns: [checkIn(summaryMarkdown: '## Highlights\n- Evidence')],
    );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-manager',
    );

    expect(find.text('1:1'), findsWidgets);
    expect(find.textContaining('never changes the summary'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<CheckInAudience>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Performance review').last);
    await tester.pumpAndSettle();

    expect(api.updateRequests, hasLength(1));
    expect(
      api.updateRequests.single.audience,
      CheckInAudience.performanceReview,
    );
    // The audience changes the prompt only, never the summary.
    expect(
      api.updateRequests.single.summaryMarkdown,
      '## Highlights\n- Evidence',
    );
    expect(find.text('Audience set to Performance review'), findsOneWidget);
    // Let the audience SnackBar expire so the next message is not queued
    // behind it.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy prompt'));
    await tester.pumpAndSettle();

    expect(api.promptRequests, ['checkin-manager']);
    expect(find.text('Copy prompt · Performance review'), findsOneWidget);
    expect(
      find.textContaining('Performance review', findRichText: true),
      findsWidgets,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // A failed prompt build is reported without losing the check-in.
    api.promptFailure = const CheckInFailure(
      'The service is unreachable. Check that the server is running.',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy prompt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not build the prompt'), findsOneWidget);
  });

  testWidgets('a personal review has no audience selector', (tester) async {
    final api = FakeCheckInApi(
      checkIns: [checkIn(id: 'checkin-personal', kind: CheckInKind.personal)],
    );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-personal',
    );

    expect(find.byType(DropdownButton<CheckInAudience>), findsNothing);
  });

  testWidgets('regenerating asks before replacing a manual edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/checkins',
        settingsApiBuilder: (_) =>
            FakeSettingsApi(settings: const AppSettings(hasAiApiKey: true)),
        summaryApiBuilder: (_) => FakeSummaryApi(report: report),
        checkInApiBuilder: (_) => FakeCheckInApi(),
      ),
    );
    await tester.pumpAndSettle();

    // Create a check-in through the dialog, then generate a first summary.
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create check-in').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create check-in').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Generate with AI').first,
    );
    await tester.pumpAndSettle();

    // Replace the generated text with a manual edit.
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '## Manual\n- My own words');
    await tester.tap(find.widgetWithText(FilledButton, 'Save summary'));
    await tester.pumpAndSettle();
    expect(find.textContaining('My own words'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Regenerate'));
    await tester.pumpAndSettle();

    expect(find.text('Replace edited summary?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Replace edited summary?'), findsNothing);
    expect(find.textContaining('My own words'), findsWidgets);
  });

  testWidgets('marking final makes the check-in read-only', (tester) async {
    final api = FakeCheckInApi(checkIns: [checkIn()]);
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-manager',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Mark final'));
    await tester.pumpAndSettle();
    expect(find.text('Mark check-in as final?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Mark final').last);
    await tester.pumpAndSettle();

    expect(api.finalizeRequests, ['checkin-manager']);
    expect(
      find.text('Final check-in — read-only boundary for the next period.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Mark final'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
  });

  testWidgets('mark final cannot discard an open summary draft', (
    tester,
  ) async {
    final api = FakeCheckInApi(
      checkIns: [checkIn(summaryMarkdown: '## Existing\n- Evidence')],
    );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-manager',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '## Unsaved draft');

    final markFinal = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Mark final'),
    );
    expect(markFinal.onPressed, isNull);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Mark final'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Mark check-in as final?'), findsNothing);
    expect(api.finalizeRequests, isEmpty);
    // The draft is still in the editor rather than stranded behind a
    // read-only final check-in.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '## Unsaved draft',
    );
  });

  testWidgets('a final check-in hides the finalize action', (tester) async {
    final api = FakeCheckInApi(checkIns: [checkIn(state: CheckInState.final_)]);
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-manager',
    );

    expect(
      find.text('Final check-in — read-only boundary for the next period.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Mark final'), findsNothing);
  });

  testWidgets('a manager draft can be deleted from its detail screen', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    final api = FakeCheckInApi(
      checkIns: [
        checkIn(
          id: 'manager-draft',
          focusNotes: 'Draft focus',
          periodStart: addDays(today, -5),
          periodEnd: today,
          createdAt: DateTime.utc(today.year, today.month, today.day, 12),
        ),
        checkIn(
          id: 'manager-final',
          state: CheckInState.final_,
          focusNotes: 'Final focus',
          periodStart: DateTime(2026, 10, 1),
          periodEnd: addDays(today, -10),
          createdAt: DateTime.utc(2026, 10, 10, 12),
        ),
      ],
    );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/manager-draft',
    );

    // The draft is the latest check-in, so the pill counts from it.
    expect(find.text('Check-in due'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Delete draft check-in'),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Delete draft check-in'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete this draft check-in?'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete draft check-in').last,
    );
    await tester.pumpAndSettle();

    expect(api.deleteRequests, ['manager-draft']);
    expect(find.text('Check-ins'), findsWidgets);
    expect(find.text('Draft focus'), findsNothing);
    expect(find.text('Final focus'), findsOneWidget);
    // The pill now counts from the remaining final check-in.
    expect(find.textContaining('days since check-in'), findsOneWidget);
    // The list itself never offers a delete action.
    expect(
      find.widgetWithText(OutlinedButton, 'Delete draft check-in'),
      findsNothing,
    );
    expect(find.widgetWithText(OutlinedButton, 'Delete review'), findsNothing);
  });

  testWidgets('cancelling a draft delete leaves the draft untouched', (
    tester,
  ) async {
    final api = FakeCheckInApi(
      checkIns: [checkIn(id: 'manager-draft', focusNotes: 'Draft focus')],
    );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/manager-draft',
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Delete draft check-in'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete this draft check-in?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this draft check-in?'), findsNothing);
    expect(api.deleteRequests, isEmpty);
    expect(api.checkIns, hasLength(1));
    // Still on the detail screen, with the draft intact.
    expect(find.widgetWithText(FilledButton, 'Mark final'), findsOneWidget);
    expect(find.text('Draft focus'), findsOneWidget);
  });

  testWidgets('a final manager check-in has no delete action', (tester) async {
    final api = FakeCheckInApi(checkIns: [checkIn(state: CheckInState.final_)]);
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-manager',
    );

    expect(
      find.widgetWithText(OutlinedButton, 'Delete draft check-in'),
      findsNothing,
    );
    expect(find.widgetWithText(OutlinedButton, 'Delete review'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
  });

  testWidgets('list failure shows a retry that reloads', (tester) async {
    final api = FakeCheckInApi(checkIns: [checkIn()])
      ..failure = const CheckInFailure(
        'The service is unreachable. Check that the server is running.',
      );
    await pumpCheckIns(tester, checkInApi: api, route: '/checkins');

    expect(find.text('Could not load check-ins'), findsOneWidget);
    expect(find.textContaining('unreachable'), findsWidgets);

    api.failure = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load check-ins'), findsNothing);
    expect(find.text('Manager focus'), findsOneWidget);
  });

  testWidgets('detail failure shows a retry that reloads', (tester) async {
    final api = FakeCheckInApi(checkIns: [checkIn()])
      ..detailFailure = const CheckInFailure(
        'The service is unreachable. Check that the server is running.',
      );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      route: '/checkins/checkin-manager',
    );

    expect(find.text('Could not load the check-in'), findsOneWidget);

    api.detailFailure = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load the check-in'), findsNothing);
    expect(find.text('Time by category'), findsOneWidget);
  });
  testWidgets('AI generation is disabled until the account adds a key', (
    tester,
  ) async {
    final api = FakeCheckInApi(checkIns: [checkIn()]);
    final summaryApi = FakeSummaryApi(report: report);
    await pumpCheckIns(
      tester,
      checkInApi: api,
      summaryApi: summaryApi,
      route: '/checkins/checkin-manager',
      hasAIKey: false,
    );

    expect(find.widgetWithText(FilledButton, 'Generate with AI'), findsNothing);
    expect(
      find.textContaining('Add your AI provider key in Settings'),
      findsOneWidget,
    );
    expect(summaryApi.generateCalls, 0);
  });

  testWidgets('an existing summary still explains a missing AI key', (
    tester,
  ) async {
    final api = FakeCheckInApi(
      checkIns: [checkIn(summaryMarkdown: '## Existing\n- Evidence')],
    );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      summaryApi: FakeSummaryApi(report: report),
      route: '/checkins/checkin-manager',
      hasAIKey: false,
    );

    // With no key the Regenerate action disappears, but the explanation must
    // still be visible next to the existing summary.
    expect(find.widgetWithText(FilledButton, 'Regenerate'), findsNothing);
    expect(
      find.textContaining('Add your AI provider key in Settings'),
      findsOneWidget,
    );
    expect(find.textContaining('Existing'), findsWidgets);
  });

  testWidgets('streams generation into the summary and shows the model', (
    tester,
  ) async {
    final api = FakeCheckInApi(checkIns: [checkIn()]);
    final summaryApi = FakeSummaryApi(report: report)
      ..generationDeltas = [
        const SummaryDelta(text: '## Highlights\n'),
        const SummaryDelta(text: '- Shipped the backfill'),
        SummaryDelta(
          checkIn: checkIn().generatedWith(
            '## Highlights\n- Shipped the backfill',
          ),
          model: 'provider-model',
          promptVersion: 'v1',
        ),
      ];
    await pumpCheckIns(
      tester,
      checkInApi: api,
      summaryApi: summaryApi,
      route: '/checkins/checkin-manager',
    );

    await tester.tap(
      find.widgetWithText(FilledButton, 'Generate with AI').first,
    );
    await tester.pumpAndSettle();

    expect(summaryApi.generateCalls, 1);
    expect(summaryApi.lastGenerateCheckInId, 'checkin-manager');
    expect(summaryApi.lastOverwriteManualEdits, isTrue);
    expect(find.text('Summary generated'), findsOneWidget);
    expect(
      find.textContaining('Model: provider-model · prompt v1'),
      findsOneWidget,
    );
    expect(find.textContaining('Shipped the backfill'), findsWidgets);
  });

  testWidgets('a failed generation keeps the summary and offers a retry', (
    tester,
  ) async {
    final api = FakeCheckInApi(
      checkIns: [checkIn(summaryMarkdown: '## Existing\n- My own words')],
    );
    final summaryApi = FakeSummaryApi(report: report)
      ..generationDeltas = [const SummaryDelta(text: '## Partial')]
      ..generationFailure = const SummaryFailure(
        'The AI provider could not complete the summary.',
      );
    await pumpCheckIns(
      tester,
      checkInApi: api,
      summaryApi: summaryApi,
      route: '/checkins/checkin-manager',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Regenerate'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('My own words'), findsWidgets);
    expect(find.textContaining('## Partial'), findsNothing);

    summaryApi.generationFailure = null;
    summaryApi.generationDeltas = [
      const SummaryDelta(text: '## New\n- Generated after retry'),
      SummaryDelta(
        checkIn: checkIn().generatedWith(
          '## New\n- Generated after retry',
          model: 'retry-model',
        ),
        model: 'retry-model',
        promptVersion: 'v1',
      ),
    ];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing);
    expect(find.text('Summary generated'), findsOneWidget);
    expect(find.textContaining('Generated after retry'), findsWidgets);
    expect(find.textContaining('My own words'), findsNothing);
  });
}

extension on CheckIn {
  CheckIn generatedWith(String summary, {String model = 'provider-model'}) =>
      copyWith(
        summaryMarkdown: summary,
        summaryModel: model,
        promptVersion: 'v1',
        state: CheckInState.generated,
      );
}
