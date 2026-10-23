import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/demo_repository.dart';
import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/initiative.dart' show LinkRef;
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/utils/time_utils.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';

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

WorkEntry testWorkEntry({
  required String id,
  String categoryId = 'cat-1',
  String subcategoryId = 'sub-1',
  required String description,
  String outcome = '',
  int hour = 9,
  int minute = 0,
  int minutes = 60,
  List<String> tags = const [],
  List<LinkRef> links = const [],
}) {
  final now = DateTime.now();
  final started = DateTime(now.year, now.month, now.day, hour, minute);
  return WorkEntry(
    id: id,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    description: description,
    outcome: outcome,
    tags: tags,
    links: links,
    startedAt: started.toUtc(),
    endedAt: started.add(Duration(minutes: minutes)).toUtc(),
    minutes: minutes,
    localDate: isoDate(started),
    createdAt: started.toUtc(),
    updatedAt: started.toUtc(),
  );
}

List<WorkEntry> sampleEntries() => [
  testWorkEntry(id: 'entry-a', description: 'Backfill script skeleton'),
  testWorkEntry(
    id: 'entry-b',
    categoryId: 'cat-2',
    subcategoryId: 'sub-2',
    description: 'Daily standup',
    hour: 9,
    minute: 30,
    minutes: 30,
  ),
];

Future<FakeEntryApi> pumpLog(
  WidgetTester tester, {
  List<WorkEntry>? entries,
  EntryFailure? listFailure,
  Completer<List<WorkEntry>>? logGate,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final entryApi = FakeEntryApi(entries: entries ?? sampleEntries())
    ..listFailure = listFailure
    ..logGate = logGate;

  await tester.pumpWidget(
    WdidApp(
      key: UniqueKey(),
      repository: DemoWdidRepository(latency: Duration.zero),
      authApi: FakeAuthApi(),
      initialRoute: '/log',
      categoryApiBuilder: (_) => FakeCategoryApi(
        categories: [
          category('cat-1', 'Initiatives'),
          category('cat-2', 'Meetings', role: CategoryRole.other),
          category('cat-s', 'Support', role: CategoryRole.support),
        ],
        subcategories: [
          subcategory('sub-1', 'cat-1', 'Billing migration'),
          subcategory('sub-2', 'cat-2', 'Sprint planning'),
          subcategory('sub-s', 'cat-s', 'Unblock'),
        ],
      ),
      settingsApiBuilder: (_) => FakeSettingsApi(settings: const AppSettings()),
      entryApiBuilder: (_) => entryApi,
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

Finder descriptionField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == 'Description',
);

Finder minutesField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Minutes',
);

Finder searchField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.hintText == 'Search entries…  /',
);

Future<void> openRowMenu(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.byTooltip('Row actions').at(index));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads the period and marks overlapping entries', (tester) async {
    final entryApi = await pumpLog(tester);

    expect(entryApi.lastFromDate, isoDate(startOfWeek(DateTime.now())));
    expect(entryApi.lastToDate, isoDate(DateTime.now()));
    // Both rows are visible and both sides of the intersection are marked.
    expect(find.text('Backfill script skeleton'), findsOneWidget);
    expect(find.text('Daily standup'), findsOneWidget);
    expect(find.text('Overlap'), findsNWidgets(2));
    expect(find.text('2 overlapping'), findsOneWidget);
  });

  testWidgets('filters by category, subcategory and text', (tester) async {
    final entryApi = await pumpLog(tester);

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Initiatives').last);
    await tester.pumpAndSettle();

    expect(entryApi.lastCategoryId, 'cat-1');
    expect(find.text('Backfill script skeleton'), findsOneWidget);
    expect(find.text('Daily standup'), findsNothing);
    // The marker follows the entry even when its overlapping partner is
    // filtered out.
    expect(find.text('Overlap'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Billing migration').last);
    await tester.pumpAndSettle();
    expect(entryApi.lastSubcategoryId, 'sub-1');

    await tester.enterText(searchField(), 'script');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(entryApi.lastQuery, 'script');
    expect(find.text('Backfill script skeleton'), findsOneWidget);
  });

  testWidgets('today preset asks for exactly today', (tester) async {
    final entryApi = await pumpLog(tester);

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButton).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    final today = dateOnly(DateTime.now());
    expect(entryApi.lastFromDate, isoDate(today));
    expect(entryApi.lastToDate, isoDate(today));
  });

  testWidgets('edits an entry inline', (tester) async {
    final entryApi = await pumpLog(
      tester,
      entries: [
        testWorkEntry(id: 'entry-a', description: 'Backfill script skeleton'),
      ],
    );

    await openRowMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(descriptionField(), findsOneWidget);
    await tester.enterText(descriptionField(), 'Backfill script finished');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();

    expect(entryApi.updateCalls, 1);
    expect(entryApi.entries.single.description, 'Backfill script finished');
    expect(find.text('Backfill script finished'), findsOneWidget);
    expect(find.text('Entry updated'), findsOneWidget);
  });

  testWidgets('rejects invalid inline minutes', (tester) async {
    final entryApi = await pumpLog(
      tester,
      entries: [
        testWorkEntry(id: 'entry-a', description: 'Backfill script skeleton'),
      ],
    );

    await openRowMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(minutesField(), '0');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();

    expect(find.text('1–1440'), findsOneWidget);
    expect(entryApi.updateCalls, isNull);
  });

  testWidgets('splits an entry into contiguous halves', (tester) async {
    final entryApi = await pumpLog(
      tester,
      entries: [testWorkEntry(id: 'entry-a', description: 'Long backfill')],
    );

    await openRowMenu(tester);
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Minutes in the first half',
      ),
      '20',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Split'));
    await tester.pumpAndSettle();

    expect(entryApi.splitCalls, 1);
    expect(entryApi.entries, hasLength(2));
    expect(entryApi.entries.map((entry) => entry.minutes), [20, 40]);
    expect(find.text('Long backfill'), findsNWidgets(2));
  });

  testWidgets('validates the split point', (tester) async {
    final entryApi = await pumpLog(
      tester,
      entries: [
        testWorkEntry(id: 'entry-a', description: 'Long backfill', minutes: 30),
      ],
    );

    await openRowMenu(tester);
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Minutes in the first half',
      ),
      '30',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Split'));
    await tester.pumpAndSettle();

    expect(
      find.text('Leave at least one minute on each side.'),
      findsOneWidget,
    );
    expect(entryApi.splitCalls, isNull);
  });

  testWidgets('deletes an entry after confirmation', (tester) async {
    final entryApi = await pumpLog(
      tester,
      entries: [
        testWorkEntry(id: 'entry-a', description: 'Backfill script skeleton'),
      ],
    );

    await openRowMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(entryApi.deleteCalls, 1);
    expect(entryApi.entries, isEmpty);
    expect(find.text('Backfill script skeleton'), findsNothing);
    expect(find.text('Entry deleted'), findsOneWidget);
  });

  testWidgets('adds an entry from the log', (tester) async {
    final entryApi = await pumpLog(tester, entries: []);

    expect(find.text('Add entry'), findsWidgets);
    await tester.tap(find.text('Add entry').first);
    await tester.pumpAndSettle();

    await tester.enterText(descriptionField(), 'Retro notes');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();

    expect(entryApi.drafts, hasLength(1));
    final draft = entryApi.drafts.single;
    expect(draft.description, 'Retro notes');
    expect(draft.categoryId, 'cat-1');
    expect(draft.minutes, 30);
    expect(find.text('Entry saved'), findsOneWidget);
    expect(find.text('Retro notes'), findsOneWidget);
  });

  testWidgets('requires a person when editing into a support category', (
    tester,
  ) async {
    final entryApi = await pumpLog(
      tester,
      entries: [
        testWorkEntry(id: 'entry-a', description: 'Backfill script skeleton'),
      ],
    );

    await openRowMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // The filter dropdowns come first; the editor's category is the third
    // String dropdown.
    await tester.tap(find.byType(DropdownButton<String>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(find.text('Who are you supporting? Add a person.'), findsOneWidget);
    expect(entryApi.updateCalls, isNull);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Person',
      ),
      'Priya',
    );
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();

    expect(entryApi.updateCalls, 1);
    expect(entryApi.entries.single.categoryId, 'cat-s');
    expect(entryApi.entries.single.person, 'Priya');
  });

  testWidgets('expands a row to show outcome, links and tags', (tester) async {
    await pumpLog(
      tester,
      entries: [
        testWorkEntry(
          id: 'entry-a',
          description: 'Backfill script skeleton',
          outcome: 'Script runs against staging',
          tags: const ['migration'],
          links: const [LinkRef(label: 'PR #412', url: 'https://example.com')],
        ),
      ],
    );

    await tester.tap(find.text('Backfill script skeleton'));
    await tester.pumpAndSettle();

    expect(find.text('OUTCOME'), findsOneWidget);
    expect(find.text('LINKS'), findsOneWidget);
    expect(find.text('PR #412'), findsOneWidget);
    expect(find.text('TAGS'), findsOneWidget);
    expect(find.text('migration'), findsOneWidget);
  });

  testWidgets('shows loading, error and empty states', (tester) async {
    final gate = Completer<List<WorkEntry>>();
    await pumpLog(tester, logGate: gate, settle: false);
    expect(find.text('Loading entries…'), findsOneWidget);
    gate.complete([testWorkEntry(id: 'late', description: 'Late entry')]);
    await tester.pumpAndSettle();
    expect(find.text('Late entry'), findsOneWidget);

    await pumpLog(
      tester,
      listFailure: const EntryFailure('The service is unreachable.'),
    );
    expect(find.text('Could not load the log'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await pumpLog(tester, entries: []);
    expect(find.text('Nothing logged in this period'), findsOneWidget);
  });
}
