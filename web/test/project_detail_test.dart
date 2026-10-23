import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/category_api.dart';
import 'package:wdid_web/data/demo_repository.dart';
import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';
import 'fake_summary_api.dart';

Category category(
  String id,
  String name, {
  CategoryRole role = CategoryRole.initiative,
  bool archived = false,
}) {
  return Category(
    id: id,
    name: name,
    role: role,
    archived: archived,
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
  );
}

Subcategory project(
  String id, {
  String categoryId = 'cat-init',
  required String name,
  String description = '',
  SubcategoryStatus status = SubcategoryStatus.active,
  int progress = 0,
  String targetOutcome = '',
  bool archived = false,
}) {
  return Subcategory(
    id: id,
    categoryId: categoryId,
    name: name,
    description: description,
    status: status,
    progress: progress,
    targetOutcome: targetOutcome,
    archived: archived,
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
  );
}

WorkEntry workEntry({
  required String id,
  String categoryId = 'cat-init',
  String subcategoryId = 'sub-invoice',
  String description = '',
  String outcome = '',
  String person = '',
  required DateTime startedAt,
  int minutes = 30,
}) {
  return WorkEntry(
    id: id,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    description: description,
    outcome: outcome,
    person: person,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(minutes: minutes)),
    minutes: minutes,
    localDate: startedAt.toIso8601String().substring(0, 10),
    createdAt: startedAt,
    updatedAt: startedAt,
  );
}

PeriodReport reportWithProject({
  int minutes = 120,
  int entryCount = 2,
  String lastActivityDate = '2026-10-22',
  String lastActivityDescription = 'Backfill review',
}) {
  return PeriodReport(
    fromDate: '2026-10-01',
    toDate: '2026-10-23',
    totalMinutes: minutes,
    entryCount: entryCount,
    categories: [
      CategoryAllocation(
        categoryId: 'cat-init',
        name: 'Initiatives',
        role: CategoryRole.initiative,
        minutes: minutes,
        entryCount: entryCount,
      ),
    ],
    subcategories: [
      SubcategoryAllocation(
        subcategoryId: 'sub-invoice',
        categoryId: 'cat-init',
        name: 'Invoice pipeline',
        minutes: minutes,
        entryCount: entryCount,
        lastActivityDate: lastActivityDate,
        lastActivityDescription: lastActivityDescription,
      ),
    ],
  );
}

FakeCategoryApi projectTaxonomy({bool archived = false}) {
  return FakeCategoryApi(
    categories: [
      category('cat-init', 'Initiatives'),
      category('cat-support', 'Support', role: CategoryRole.support),
    ],
    subcategories: [
      project(
        'sub-invoice',
        name: 'Invoice pipeline',
        progress: 64,
        targetOutcome: 'Invoice generation under 5 minutes',
        archived: archived,
      ),
      project('sub-spike', name: 'Dependency spike'),
    ],
  );
}

Future<void> pumpDetail(
  WidgetTester tester, {
  required String route,
  FakeCategoryApi? categoryApi,
  FakeEntryApi? entryApi,
  FakeSummaryApi? summaryApi,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    WdidApp(
      repository: DemoWdidRepository(latency: Duration.zero),
      authApi: FakeAuthApi(),
      initialRoute: route,
      categoryApiBuilder: (_) => categoryApi ?? projectTaxonomy(),
      entryApiBuilder: (_) =>
          entryApi ??
          FakeEntryApi(
            entries: [
              workEntry(
                id: 'entry-old',
                description: 'Backfill script',
                startedAt: DateTime.utc(2026, 10, 20, 9),
                minutes: 60,
              ),
              workEntry(
                id: 'entry-new',
                description: 'Backfill review',
                outcome: 'Script runs against staging',
                person: 'Priya',
                startedAt: DateTime.utc(2026, 10, 22, 9),
                minutes: 60,
              ),
            ],
          ),
      summaryApiBuilder: (_) =>
          summaryApi ?? FakeSummaryApi(report: reportWithProject()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('opens a project from the portfolio', (tester) async {
    await pumpDetail(tester, route: '/initiatives');

    await tester.tap(find.text('Invoice pipeline'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back to initiatives'), findsOneWidget);
    expect(find.text('Invoice pipeline'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a direct link shows the project header', (tester) async {
    await pumpDetail(tester, route: '/initiatives/sub-invoice');

    expect(find.text('Invoice pipeline'), findsWidgets);
    expect(find.text('Initiatives'), findsWidgets);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('Invoice generation under 5 minutes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logs time against the project', (tester) async {
    final entryApi = FakeEntryApi();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Log time'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Backfill script skeleton');
    await tester.enterText(fields.at(1), 'Script runs against staging');
    await tester.enterText(fields.at(2), '30');

    await tester.tap(find.widgetWithText(FilledButton, 'Save entry'));
    await tester.pumpAndSettle();

    expect(entryApi.drafts, hasLength(1));
    expect(entryApi.drafts.single.categoryId, 'cat-init');
    expect(entryApi.drafts.single.subcategoryId, 'sub-invoice');
    expect(entryApi.drafts.single.description, 'Backfill script skeleton');
    expect(entryApi.drafts.single.outcome, 'Script runs against staging');
    expect(entryApi.drafts.single.minutes, 30);
    expect(find.text('Backfill script skeleton'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report shows project-scoped totals and interactions', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      summaryApi: FakeSummaryApi(
        report: reportWithProject(minutes: 150, entryCount: 3),
      ),
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    // The total comes from the report allocation, not the two timeline rows.
    expect(find.text('2h 30m'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Backfill review'), findsWidgets);
    expect(find.text('1 interaction'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Script runs against staging'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an archived project is read-only until restored', (
    tester,
  ) async {
    final categories = projectTaxonomy(archived: true);
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: categories,
    );

    expect(
      find.text('This project is archived and read-only.'),
      findsOneWidget,
    );
    expect(find.text('Log time'), findsNothing);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(
      categories.subcategories
          .firstWhere((item) => item.id == 'sub-invoice')
          .archived,
      isFalse,
    );
    expect(find.text('This project is archived and read-only.'), findsNothing);
    expect(find.text('Log time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty timeline state', (tester) async {
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: FakeEntryApi(),
    );

    expect(find.text('No time logged yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries the timeline after a service failure', (tester) async {
    final entryApi = FakeEntryApi()
      ..listFailure = const EntryFailure('The service is unreachable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    expect(find.text('The service is unreachable.'), findsOneWidget);

    entryApi.listFailure = null;
    entryApi.entries.addAll([
      workEntry(
        id: 'entry-1',
        description: 'Backfill script',
        startedAt: DateTime.utc(2026, 10, 20, 9),
      ),
    ]);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Backfill script'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries the report after a service failure', (tester) async {
    final summary = FakeSummaryApi(report: reportWithProject())
      ..failure = const SummaryFailure('The report is unavailable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      summaryApi: summary,
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('The report is unavailable.'), findsOneWidget);

    summary.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('2h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles an unknown project id', (tester) async {
    await pumpDetail(tester, route: '/initiatives/missing');

    expect(find.text('Project not found'), findsOneWidget);
    expect(find.text('Back to initiatives'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a retryable state when the taxonomy fails', (
    tester,
  ) async {
    final failing = FakeCategoryApi()
      ..failure = const CategoryFailure('The taxonomy is unavailable.');
    await pumpDetail(
      tester,
      route: '/initiatives/missing',
      categoryApi: failing,
    );

    expect(find.text('Could not load the projects'), findsOneWidget);
    expect(find.text('The taxonomy is unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a loading state while the taxonomy loads', (tester) async {
    final gate = Completer<void>();
    final categories = projectTaxonomy()..gate = gate;

    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: categories,
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Invoice pipeline'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validates the log-time form before saving', (tester) async {
    final entryApi = FakeEntryApi();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Log time'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save entry'));
    await tester.pumpAndSettle();

    expect(find.text('A short description is required.'), findsOneWidget);
    expect(entryApi.drafts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens an archived project from the portfolio', (tester) async {
    final categories = projectTaxonomy(archived: true);
    await pumpDetail(tester, route: '/initiatives', categoryApi: categories);

    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoice pipeline'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back to initiatives'), findsOneWidget);
    expect(
      find.text('This project is archived and read-only.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report only lists interactions from its period', (
    tester,
  ) async {
    final entryApi = FakeEntryApi(
      entries: [
        workEntry(
          id: 'entry-in',
          description: 'In period review',
          person: 'Priya',
          startedAt: DateTime.utc(2026, 10, 22, 9),
        ),
        workEntry(
          id: 'entry-out',
          description: 'Old review',
          person: 'Sam',
          startedAt: DateTime.utc(2026, 8, 1, 9),
        ),
      ],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('In period review'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Old review'), findsNothing);
    expect(find.text('Sam'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report surfaces a timeline failure instead of empty', (
    tester,
  ) async {
    final entryApi = FakeEntryApi()
      ..listFailure = const EntryFailure('The service is unreachable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(
      find.text('This project’s entries could not be loaded.'),
      findsOneWidget,
    );
    expect(find.text('The service is unreachable.'), findsOneWidget);
    expect(find.textContaining('No people were named'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the timeline lists the project entries newest first', (
    tester,
  ) async {
    await pumpDetail(tester, route: '/initiatives/sub-invoice');

    expect(find.text('Backfill review'), findsOneWidget);
    expect(find.text('Backfill script'), findsOneWidget);
    expect(find.text('Script runs against staging'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);

    final newest = tester.getTopLeft(find.text('Backfill review')).dy;
    final oldest = tester.getTopLeft(find.text('Backfill script')).dy;
    expect(newest, lessThan(oldest));
    expect(tester.takeException(), isNull);
  });
}
