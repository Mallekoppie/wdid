import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/category_api.dart';
import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/link_ref.dart';
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
  String description = '',
  SubcategoryStatus status = SubcategoryStatus.active,
  int progress = 0,
  String targetOutcome = '',
  String targetDate = '',
  List<LinkRef> links = const [],
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
    targetDate: targetDate,
    links: links,
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

  testWidgets('edits a project from its card with the current values', (
    tester,
  ) async {
    final categories = FakeCategoryApi(
      categories: [category('cat-init', 'Initiatives')],
      subcategories: [
        project(
          'sub-invoice',
          name: 'Invoice pipeline',
          description: 'Move invoicing to the new pipeline',
          status: SubcategoryStatus.blocked,
          progress: 64,
          targetOutcome: 'Invoice generation under 5 minutes',
          targetDate: '2026-12-01',
          links: const [
            LinkRef(label: 'Epic', url: 'https://example.com/epic'),
            LinkRef(
              label: 'https://example.com/design',
              url: 'https://example.com/design',
            ),
          ],
        ),
      ],
    );

    await pumpInitiatives(tester, categoryApi: categories);

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(find.text('Edit project'), findsOneWidget);
    // The category is read-only, so it is not a dropdown.
    expect(
      find.descendant(
        of: dialog,
        matching: find.byType(DropdownButton<String>),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Initiatives')),
      findsOneWidget,
    );

    final fields = find.byType(TextFormField);
    expect(
      tester.widget<TextFormField>(fields.at(0)).controller!.text,
      'Invoice pipeline',
    );
    expect(
      tester.widget<TextFormField>(fields.at(1)).controller!.text,
      'Move invoicing to the new pipeline',
    );
    expect(
      tester.widget<TextFormField>(fields.at(2)).controller!.text,
      'Invoice generation under 5 minutes',
    );
    expect(
      tester.widget<TextFormField>(fields.at(3)).controller!.text,
      'Epic | https://example.com/epic\nhttps://example.com/design',
    );
    expect(
      tester
          .widget<DropdownButton<SubcategoryStatus>>(
            find.byType(DropdownButton<SubcategoryStatus>),
          )
          .value,
      SubcategoryStatus.blocked,
    );
    expect(tester.widget<Slider>(find.byType(Slider)).value, 64);
    expect(find.text('1 Dec'), findsOneWidget);

    await tester.enterText(fields.at(0), 'Invoice pipeline v2');
    await tester.enterText(fields.at(1), 'Cut over invoicing');
    await tester.enterText(fields.at(2), 'Invoices under two minutes');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    final saved = categories.subcategories.single;
    expect(saved.name, 'Invoice pipeline v2');
    expect(saved.description, 'Cut over invoicing');
    expect(saved.targetOutcome, 'Invoices under two minutes');
    // Fields the user did not touch keep their values.
    expect(saved.status, SubcategoryStatus.blocked);
    expect(saved.progress, 64);
    expect(saved.targetDate, '2026-12-01');
    expect(saved.links, hasLength(2));
    expect(find.text('Invoice pipeline v2'), findsOneWidget);
    expect(find.text('Project updated · Invoice pipeline v2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits status, progress, links and the target date', (
    tester,
  ) async {
    final categories = FakeCategoryApi(
      categories: [category('cat-init', 'Initiatives')],
      subcategories: [
        project(
          'sub-invoice',
          name: 'Invoice pipeline',
          progress: 20,
          targetDate: '2026-12-01',
          links: const [LinkRef(label: 'Epic', url: 'https://example.com/epic')],
        ),
      ],
    );

    await pumpInitiatives(tester, categoryApi: categories);
    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<SubcategoryStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blocked').last);
    await tester.pumpAndSettle();

    tester.widget<Slider>(find.byType(Slider)).onChanged!(80);
    await tester.pump();

    await tester.tap(find.byTooltip('Clear target date'));
    await tester.pump();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(3), 'Design | https://example.com/design');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    final saved = categories.subcategories.single;
    expect(saved.status, SubcategoryStatus.blocked);
    expect(saved.progress, 80);
    expect(saved.targetDate, '');
    expect(saved.links.single.label, 'Design');
    expect(saved.links.single.url, 'https://example.com/design');
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits a project under an archived initiative category', (
    tester,
  ) async {
    final categories = FakeCategoryApi(
      categories: [category('cat-old', 'Legacy initiatives', archived: true)],
      subcategories: [
        project('sub-old', categoryId: 'cat-old', name: 'Old project'),
      ],
    );

    await pumpInitiatives(tester, categoryApi: categories);
    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // The archived category still resolves, so the read-only label is right.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Legacy initiatives'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField).first, 'Old project v2');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(categories.subcategories.single.name, 'Old project v2');
    expect(find.text('Old project v2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived projects offer no edit action', (tester) async {
    final categories = FakeCategoryApi(
      categories: [category('cat-init', 'Initiatives')],
      subcategories: [
        project('sub-legacy', name: 'Legacy billing', archived: true),
      ],
    );

    await pumpInitiatives(tester, categoryApi: categories);
    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy billing'), findsOneWidget);
    expect(find.byTooltip('Project actions'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
