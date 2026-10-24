import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/demo_repository.dart';
import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/models/initiative.dart' show LinkRef;
import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/utils/time_utils.dart';
import 'package:wdid_web/widgets/support_entry_row.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';
import 'fake_summary_api.dart';

Category category(
  String id,
  String name, {
  CategoryRole role = CategoryRole.initiative,
}) => Category(
  id: id,
  name: name,
  role: role,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

Subcategory subcategory(String id, String categoryId, String name) =>
    Subcategory(
      id: id,
      categoryId: categoryId,
      name: name,
      createdAt: DateTime.utc(2026, 10, 23),
      updatedAt: DateTime.utc(2026, 10, 23),
    );

WorkEntry supportEntry({
  required String id,
  String person = 'Priya',
  String team = '',
  String subcategoryId = 'mode-unblock',
  String description = 'Unblocked the migration',
  String outcome = '',
  int hour = 9,
  int minutes = 30,
  List<LinkRef> links = const [],
}) {
  final now = DateTime.now();
  final started = DateTime(now.year, now.month, now.day, hour);
  return WorkEntry(
    id: id,
    categoryId: 'cat-support',
    subcategoryId: subcategoryId,
    description: description,
    outcome: outcome,
    startedAt: started,
    endedAt: started.add(Duration(minutes: minutes)),
    minutes: minutes,
    localDate: isoDate(started),
    person: person,
    team: team,
    links: links,
    createdAt: started,
    updatedAt: started,
  );
}

Future<FakeEntryApi> pumpSupport(
  WidgetTester tester, {
  List<WorkEntry> entries = const [],
  EntryFailure? listFailure,
  Completer<List<WorkEntry>>? logGate,
  bool settle = true,
  FakeSummaryApi? summaryApi,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final entryApi = FakeEntryApi(entries: entries.toList())
    ..listFailure = listFailure
    ..logGate = logGate;

  await tester.pumpWidget(
    WdidApp(
      key: UniqueKey(),
      repository: DemoWdidRepository(latency: Duration.zero),
      authApi: FakeAuthApi(),
      initialSession: signedInSession(),
      initialRoute: '/support',
      categoryApiBuilder: (_) => FakeCategoryApi(
        categories: [
          category('cat-init', 'Initiatives'),
          category('cat-support', 'Support', role: CategoryRole.support),
          category('cat-other', 'Other', role: CategoryRole.other),
        ],
        subcategories: [
          subcategory('proj-1', 'cat-init', 'Billing migration'),
          subcategory('mode-unblock', 'cat-support', 'Unblock'),
          subcategory('mode-review', 'cat-support', 'Review'),
          subcategory('mode-other', 'cat-other', 'Meetings'),
        ],
      ),
      settingsApiBuilder: (_) => FakeSettingsApi(),
      entryApiBuilder: (_) => entryApi,
      summaryApiBuilder: (_) => summaryApi ?? FakeSummaryApi(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var index = 0; index < 6; index++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }
  return entryApi;
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText?.startsWith(label) == true,
);

Finder modeDropdown() => find.byType(DropdownButton<String>);

Finder periodDropdown() =>
    find.byWidgetPredicate((widget) => widget is DropdownButton);

void main() {
  testWidgets('lists support entries newest first and marks them', (
    tester,
  ) async {
    final entryApi = await pumpSupport(
      tester,
      entries: [
        supportEntry(
          id: 'older',
          hour: 9,
          description: 'Reviewed the event bus design',
        ),
        supportEntry(
          id: 'newer',
          hour: 14,
          subcategoryId: 'mode-review',
          person: 'Sam',
          description: 'Paired on the billing migration',
        ),
        WorkEntry(
          id: 'initiative-work',
          categoryId: 'cat-init',
          subcategoryId: 'proj-1',
          description: 'Backfill script',
          startedAt: DateTime.now(),
          endedAt: DateTime.now().add(const Duration(minutes: 30)),
          minutes: 30,
          localDate: isoDate(DateTime.now()),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
    );

    expect(entryApi.lastCategoryId, 'cat-support');
    expect(entryApi.lastFromDate, isoDate(startOfQuarter(DateTime.now())));
    expect(entryApi.lastToDate, isoDate(DateTime.now()));

    expect(find.byType(SupportEntryRow), findsNWidgets(2));
    expect(find.textContaining('Support · Priya · Unblock'), findsOneWidget);
    expect(find.textContaining('Support · Sam · Review'), findsOneWidget);
    expect(find.text('Backfill script'), findsNothing);

    // Newest first: the 14:00 review sits above the 09:00 entry.
    final newer = tester
        .getTopLeft(find.text('Paired on the billing migration'))
        .dy;
    final older = tester
        .getTopLeft(find.text('Reviewed the event bus design'))
        .dy;
    expect(newer, lessThan(older));
  });

  testWidgets('requires a person and saves taxonomy-driven modes', (
    tester,
  ) async {
    final entryApi = await pumpSupport(
      tester,
      entries: [supportEntry(id: 'existing')],
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Log support').first);
    await tester.pumpAndSettle();

    // Only support-role subcategories are offered as modes.
    await tester.tap(modeDropdown());
    await tester.pumpAndSettle();
    expect(find.text('Unblock'), findsWidgets);
    expect(find.text('Review'), findsWidgets);
    expect(find.text('Billing migration'), findsNothing);
    await tester.tap(find.text('Unblock').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Related initiative'), findsNothing);

    await tester.enterText(
      field('What did you do?'),
      '  Reviewed the event bus design  ',
    );
    await tester.enterText(field('Minutes'), '45');
    await tester.enterText(field('Impact or outcome'), 'Risks identified');
    await tester.enterText(
      field('Links'),
      'Design doc | https://example.com/doc',
    );

    // Saving without a person is a field error and never reaches the service.
    await tester.tap(find.widgetWithText(FilledButton, 'Save support'));
    await tester.pumpAndSettle();
    expect(find.text('Who did you support?'), findsOneWidget);
    expect(entryApi.drafts, isEmpty);

    await tester.enterText(field('Person'), 'Priya');
    await tester.enterText(field('Team'), 'Payments');
    await tester.tap(find.widgetWithText(FilledButton, 'Save support'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Log support'), findsWidgets);
    expect(entryApi.drafts, hasLength(1));
    final draft = entryApi.drafts.single;
    expect(draft.categoryId, 'cat-support');
    expect(draft.subcategoryId, 'mode-unblock');
    expect(draft.description, 'Reviewed the event bus design');
    expect(draft.outcome, 'Risks identified');
    expect(draft.person, 'Priya');
    expect(draft.team, 'Payments');
    expect(draft.minutes, 45);
    expect(draft.links, hasLength(1));
    expect(draft.links.single.label, 'Design doc');
    expect(draft.links.single.url, 'https://example.com/doc');
  });

  testWidgets('surfaces a service person field error on the form', (
    tester,
  ) async {
    final entryApi = await pumpSupport(
      tester,
      entries: [supportEntry(id: 'existing')],
    );
    entryApi.createFailure = const EntryFailure(
      'is required for support entries',
      field: 'person',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Log support').first);
    await tester.pumpAndSettle();
    await tester.enterText(field('What did you do?'), 'Helped Priya');
    await tester.enterText(field('Person'), 'Priya');
    await tester.tap(find.widgetWithText(FilledButton, 'Save support'));
    await tester.pumpAndSettle();

    expect(find.text('is required for support entries'), findsOneWidget);
    expect(entryApi.entries, hasLength(1));
  });

  testWidgets('handles loading, error, retry and empty states', (tester) async {
    final gate = Completer<List<WorkEntry>>();
    final entryApi = await pumpSupport(tester, logGate: gate, settle: false);
    expect(find.text('Loading support…'), findsOneWidget);

    gate.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No support logged in this period'), findsWidgets);

    entryApi.listFailure = const EntryFailure('The service is unreachable.');
    // Switching the period reloads the feed and exposes the failure state.
    await tester.tap(periodDropdown().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('This month').last);
    await tester.pumpAndSettle();
    expect(find.text('Could not load support'), findsOneWidget);

    entryApi.listFailure = null;
    entryApi.entries.add(supportEntry(id: 'after-retry'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(SupportEntryRow), findsOneWidget);
  });

  testWidgets('edits and deletes support entries', (tester) async {
    final entryApi = await pumpSupport(
      tester,
      entries: [
        supportEntry(
          id: 'editable',
          description: 'Reviewed the plan',
          outcome: 'Old outcome',
        ),
      ],
    );

    await tester.tap(find.byTooltip('Support row actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Impact or outcome'), 'New outcome');
    await tester.tap(find.widgetWithText(FilledButton, 'Save support'));
    await tester.pumpAndSettle();
    expect(entryApi.entries.single.outcome, 'New outcome');
    expect(find.byIcon(Icons.verified_outlined), findsWidgets);

    await tester.tap(find.byTooltip('Support row actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(entryApi.deleteCalls, 1);
    expect(find.byType(SupportEntryRow), findsNothing);
  });

  testWidgets('rollups come from the period report, not the entries', (
    tester,
  ) async {
    final today = isoDate(DateTime.now());
    final quarterStart = isoDate(startOfQuarter(DateTime.now()));
    final summary = FakeSummaryApi(
      report: PeriodReport(
        fromDate: quarterStart,
        toDate: today,
        totalMinutes: 180,
        entryCount: 4,
        supportPeople: const [
          SupportPersonAllocation(
            person: 'Priya',
            minutes: 120,
            interactions: 3,
          ),
          SupportPersonAllocation(person: 'Sam', minutes: 60, interactions: 1),
        ],
        supportModes: const [
          SupportModeAllocation(
            subcategoryId: 'mode-unblock',
            name: 'Unblock',
            minutes: 90,
            interactions: 2,
          ),
          SupportModeAllocation(
            subcategoryId: 'mode-review',
            name: 'Review',
            minutes: 90,
            interactions: 2,
          ),
        ],
      ),
    );

    // The one loaded entry is only 30 minutes, so any number that matches the
    // report proves the screen did not add the entries up itself.
    await pumpSupport(
      tester,
      entries: [supportEntry(id: 'only-entry', minutes: 30)],
      summaryApi: summary,
    );

    expect(find.text('3h · 2 people · 4 interactions'), findsOneWidget);
    // Priya's report minutes, the person total, not the entry's 30m.
    expect(find.text('2h'), findsOneWidget);
    expect(find.text('3 interactions'), findsOneWidget);
    expect(find.text('1 interaction'), findsOneWidget);
    // Review exists only in the report's mode rollup.
    expect(find.text('Review'), findsWidgets);

    final supportRequest = summary.requests.lastWhere(
      (request) => !request.currentWeek,
    );
    expect(supportRequest.from, quarterStart);
    expect(supportRequest.to, today);
  });

  testWidgets('an empty period renders an empty rollup, not an error', (
    tester,
  ) async {
    final summary = FakeSummaryApi(
      report: PeriodReport(
        fromDate: isoDate(startOfQuarter(DateTime.now())),
        toDate: isoDate(DateTime.now()),
      ),
    );

    await pumpSupport(tester, summaryApi: summary);

    expect(find.text('0m · 0 people · 0 interactions'), findsOneWidget);
    expect(find.text('No support logged in this period'), findsWidgets);
    expect(find.text('No interactions yet'), findsOneWidget);
    expect(find.text('Could not load support'), findsNothing);
  });
}
