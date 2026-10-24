import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/category_api.dart';
import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';

import 'fake_auth_api.dart';
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
  SubcategoryStatus status = SubcategoryStatus.active,
  int progress = 0,
  String targetOutcome = '',
  bool archived = false,
}) {
  return Subcategory(
    id: id,
    categoryId: categoryId,
    name: name,
    status: status,
    progress: progress,
    targetOutcome: targetOutcome,
    archived: archived,
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
  );
}

PeriodReport reportWith({
  String lastActivityDate = '2026-10-22',
  String lastActivityDescription = 'Backfill script',
}) {
  return PeriodReport(
    fromDate: '2026-10-01',
    toDate: '2026-10-23',
    totalMinutes: 150,
    entryCount: 3,
    categories: [
      CategoryAllocation(
        categoryId: 'cat-init',
        name: 'Initiatives',
        role: CategoryRole.initiative,
        minutes: 120,
        entryCount: 2,
      ),
      CategoryAllocation(
        categoryId: 'cat-support',
        name: 'Support',
        role: CategoryRole.support,
        minutes: 30,
        entryCount: 1,
      ),
    ],
    subcategories: [
      SubcategoryAllocation(
        subcategoryId: 'sub-invoice',
        categoryId: 'cat-init',
        name: 'Invoice pipeline',
        minutes: 120,
        entryCount: 2,
        lastActivityDate: lastActivityDate,
        lastActivityDescription: lastActivityDescription,
      ),
      SubcategoryAllocation(
        subcategoryId: 'sub-spike',
        categoryId: 'cat-init',
        name: 'Dependency spike',
        minutes: 30,
        entryCount: 1,
        lastActivityDate: '2026-10-10',
        lastActivityDescription: 'Spike notes',
      ),
    ],
  );
}

void main() {
  Future<FakeCategoryApi> pumpInitiatives(
    WidgetTester tester, {
    FakeCategoryApi? categoryApi,
    FakeSummaryApi? summaryApi,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final categories =
        categoryApi ??
        FakeCategoryApi(
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
            ),
            project(
              'sub-spike',
              name: 'Dependency spike',
              status: SubcategoryStatus.planned,
              progress: 12,
              targetOutcome: 'Zero P1s from dependencies',
            ),
            project(
              'sub-unblock',
              categoryId: 'cat-support',
              name: 'Unblock',
              status: SubcategoryStatus.active,
            ),
          ],
        );

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/initiatives',
        categoryApiBuilder: (_) => categories,
        summaryApiBuilder: (_) =>
            summaryApi ?? FakeSummaryApi(report: reportWith()),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return categories;
  }

  testWidgets(
    'shows initiative projects with report-sourced time, progress and activity',
    (tester) async {
      await pumpInitiatives(tester);

      expect(find.text('Invoice pipeline'), findsOneWidget);
      expect(find.text('Dependency spike'), findsOneWidget);

      // Time invested comes from the period report, not from local addition.
      expect(find.text('2h'), findsOneWidget);
      // The header excludes support time from the portfolio total.
      expect(find.textContaining('2 projects · 2h logged'), findsOneWidget);
      expect(find.text('30m'), findsOneWidget);

      expect(find.text('64%'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      expect(find.text('Invoice generation under 5 minutes'), findsOneWidget);
      expect(find.text('Zero P1s from dependencies'), findsOneWidget);
      expect(find.textContaining('Backfill script'), findsOneWidget);

      // Only initiative-role subcategories are projects.
      expect(find.text('Unblock'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('creates a project with its category and project fields', (
    tester,
  ) async {
    final categories = FakeCategoryApi(
      categories: [category('cat-init', 'Initiatives')],
    );

    await pumpInitiatives(tester, categoryApi: categories);

    await tester.tap(find.text('New project').first);
    await tester.pumpAndSettle();

    expect(
      find.text('A project is a subcategory under an initiative category.'),
      findsOneWidget,
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Invoice pipeline');
    await tester.enterText(fields.at(1), 'Move invoicing to the new pipeline');
    await tester.enterText(fields.at(2), 'Invoice generation under 5 minutes');
    await tester.enterText(fields.at(3), 'Epic | https://example.com/epic');

    await tester.tap(find.widgetWithText(FilledButton, 'Create project'));
    await tester.pumpAndSettle();

    final created = categories.subcategories.single;
    expect(created.name, 'Invoice pipeline');
    expect(created.categoryId, 'cat-init');
    expect(created.description, 'Move invoicing to the new pipeline');
    expect(created.targetOutcome, 'Invoice generation under 5 minutes');
    expect(created.links.single.label, 'Epic');
    expect(created.links.single.url, 'https://example.com/epic');

    expect(find.text('Invoice pipeline'), findsOneWidget);
    expect(find.text('Epic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archives a project from its card', (tester) async {
    final categories = await pumpInitiatives(tester);

    await tester.tap(find.byTooltip('Project actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    // Cards sort by name, so the first action belongs to Dependency spike.
    expect(
      categories.subcategories
          .firstWhere((item) => item.id == 'sub-spike')
          .archived,
      isTrue,
    );
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.text('Dependency spike'), findsNothing);
    expect(find.text('Invoice pipeline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps projects visible under an archived initiative category', (
    tester,
  ) async {
    final categories = FakeCategoryApi(
      categories: [category('cat-old', 'Legacy initiatives', archived: true)],
      subcategories: [
        project('sub-old', categoryId: 'cat-old', name: 'Old project'),
      ],
    );

    await pumpInitiatives(tester, categoryApi: categories);

    expect(find.text('Old project'), findsOneWidget);

    // The archived category is not offered for new projects.
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'New project'),
    );
    expect(create.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separates archived projects and restores them', (tester) async {
    final categories = FakeCategoryApi(
      categories: [category('cat-init', 'Initiatives')],
      subcategories: [
        project('sub-invoice', name: 'Invoice pipeline'),
        project('sub-legacy', name: 'Legacy billing', archived: true),
      ],
    );

    await pumpInitiatives(tester, categoryApi: categories);

    // Archived projects stay out of the portfolio until the section is opened.
    expect(find.text('Invoice pipeline'), findsOneWidget);
    expect(find.text('Legacy billing'), findsNothing);

    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy billing'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(
      categories.subcategories
          .firstWhere((item) => item.id == 'sub-legacy')
          .archived,
      isFalse,
    );
    expect(find.text('Legacy billing'), findsOneWidget);
    expect(find.text('Restore'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains that projects need an initiative category', (
    tester,
  ) async {
    await pumpInitiatives(tester, categoryApi: FakeCategoryApi());

    expect(find.text('No initiative category'), findsOneWidget);
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'New project'),
    );
    expect(create.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a retryable error when the taxonomy cannot load', (
    tester,
  ) async {
    final categories = FakeCategoryApi()
      ..failure = const CategoryFailure('The service is unreachable.');

    await pumpInitiatives(tester, categoryApi: categories);

    expect(find.text('The service is unreachable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the portfolio visible when the report fails', (
    tester,
  ) async {
    final summary = FakeSummaryApi(report: reportWith())
      ..failure = const SummaryFailure('The report is unavailable.');

    await pumpInitiatives(tester, summaryApi: summary);

    expect(find.text('The report is unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Invoice pipeline'), findsOneWidget);
    expect(find.text('No activity this quarter'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a loading state while the taxonomy loads', (tester) async {
    final gate = Completer<void>();
    final categories = FakeCategoryApi(
      categories: [category('cat-init', 'Initiatives')],
      subcategories: [project('sub-invoice', name: 'Invoice pipeline')],
    )..gate = gate;

    await pumpInitiatives(tester, categoryApi: categories, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Invoice pipeline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validates a project name before creating it', (tester) async {
    final categories = FakeCategoryApi(
      categories: [category('cat-init', 'Initiatives')],
    );

    await pumpInitiatives(tester, categoryApi: categories);
    await tester.tap(find.text('New project').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create project'));
    await tester.pumpAndSettle();

    expect(find.text('Project name is required.'), findsOneWidget);
    expect(categories.subcategories, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
