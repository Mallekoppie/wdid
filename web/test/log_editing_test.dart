import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/link_ref.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/screens/log_screen.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/utils/time_utils.dart';
import 'package:wdid_web/widgets/forms/date_range_dialog.dart';
import 'package:wdid_web/widgets/forms/dialog_frame.dart';
import 'package:wdid_web/widgets/forms/entry_form.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';

Category category(
  String id,
  String name, {
  CategoryRole role = CategoryRole.initiative,
  bool archived = false,
}) => Category(
  id: id,
  name: name,
  role: role,
  archived: archived,
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
  List<String> people = const [],
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
    people: people,
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
  FakeCategoryApi? categoryApi,
  AppSettings settings = const AppSettings(),
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
      authApi: FakeAuthApi(),
      initialSession: signedInSession(),
      initialRoute: '/log',
      categoryApiBuilder: (_) =>
          categoryApi ??
          FakeCategoryApi(
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
      settingsApiBuilder: (_) => FakeSettingsApi(settings: settings),
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

Finder formDropdown(int index) => find
    .descendant(
      of: find.byType(EntryForm),
      matching: find.byType(DropdownButton<String>),
    )
    .at(index);

String? formCategoryValue(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(formDropdown(0)).value;

String? formSubcategoryValue(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(formDropdown(1)).value;

Finder personField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Person',
);

Future<void> openAddEntry(WidgetTester tester) async {
  await tester.tap(find.text('Add entry').first);
  await tester.pumpAndSettle();
}

/// Picks an option in one of the Log's own filter dropdowns. The filter
/// dropdowns always come before any entry form in the tree.
Future<void> pickFilter(
  WidgetTester tester, {
  required int dropdown,
  required String option,
}) async {
  await tester.tap(find.byType(DropdownButton<String>).at(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> pickCategoryFilter(WidgetTester tester, String name) =>
    pickFilter(tester, dropdown: 0, option: name);

Future<void> pickSubcategoryFilter(WidgetTester tester, String label) =>
    pickFilter(tester, dropdown: 1, option: label);

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

  testWidgets('custom range opens a compact dialog and reloads the log', (
    tester,
  ) async {
    final entryApi = await pumpLog(tester);

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButton).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom range').last);
    await tester.pumpAndSettle();

    // The shared dialog replaces Flutter's full-bleed range picker.
    expect(find.byType(DateRangeDialog), findsOneWidget);
    final frame = tester.widget<DialogFrame>(find.byType(DialogFrame));
    expect(frame.maxWidth, DateRangeDialog.maxWidth);
    expect(DateRangeDialog.maxWidth, lessThan(600));
    // Presets and explicit start/end fields live in the same dialog.
    expect(find.widgetWithText(ChoiceChip, 'Last 7 days'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DateRangeDialog),
        matching: find.byIcon(Icons.first_page),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DateRangeDialog),
        matching: find.byIcon(Icons.today_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'This month'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    final today = dateOnly(DateTime.now());
    expect(entryApi.lastFromDate, isoDate(DateTime(today.year, today.month)));
    expect(entryApi.lastToDate, isoDate(today));
    expect(find.byType(DateRangeDialog), findsNothing);
  });

  testWidgets('cancelling custom range keeps the current Log range', (
    tester,
  ) async {
    final entryApi = await pumpLog(tester);
    final from = entryApi.lastFromDate;
    final to = entryApi.lastToDate;

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButton).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom range').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(DateRangeDialog), findsNothing);
    expect(entryApi.lastFromDate, from);
    expect(entryApi.lastToDate, to);
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

  testWidgets('keeps an inline draft across a reload', (tester) async {
    final entryApi = await pumpLog(
      tester,
      entries: [
        testWorkEntry(id: 'entry-a', description: 'Backfill script skeleton'),
      ],
    );

    await openRowMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(descriptionField(), 'Unsaved draft text');

    final gate = Completer<List<WorkEntry>>();
    entryApi.logGate = gate;
    await tester.enterText(searchField(), 'backfill');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    // The rows stay mounted while the reload is in flight, so the editor and
    // its draft are not destroyed by the loading panel.
    expect(find.text('Loading entries…'), findsNothing);
    expect(descriptionField(), findsOneWidget);

    // The server returns a different description and the filter no longer
    // matches it; the open editor still survives.
    gate.complete([testWorkEntry(id: 'entry-a', description: 'Server values')]);
    await tester.pumpAndSettle();

    expect(descriptionField(), findsOneWidget);
    expect(
      tester.widget<TextField>(descriptionField()).controller!.text,
      'Unsaved draft text',
    );
  });

  testWidgets('archived categories are not offered or preselected', (
    tester,
  ) async {
    final taxonomy = FakeCategoryApi(
      categories: [
        category(
          'cat-retired',
          'Retired',
          role: CategoryRole.other,
          archived: true,
        ),
        category('cat-1', 'Initiatives'),
      ],
      subcategories: [
        Subcategory(
          id: 'sub-retired',
          categoryId: 'cat-retired',
          name: 'Old project',
          archived: true,
          createdAt: DateTime.utc(2026, 10, 23),
          updatedAt: DateTime.utc(2026, 10, 23),
        ),
        subcategory('sub-1', 'cat-1', 'Billing migration'),
      ],
    );
    await pumpLog(
      tester,
      categoryApi: taxonomy,
      entries: [
        testWorkEntry(
          id: 'entry-archived',
          categoryId: 'cat-retired',
          subcategoryId: 'sub-retired',
          description: 'Old archived work',
        ),
      ],
    );

    await tester.tap(find.text('Add entry').first);
    await tester.pumpAndSettle();

    // The remembered pair came from the archived entry, so the form must fall
    // back to the first selectable category and no subcategory.
    final formCategory = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).at(2),
    );
    final formSubcategory = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).at(3),
    );
    expect(formCategory.value, 'cat-1');
    expect(formSubcategory.value, '');

    await tester.tap(find.byType(DropdownButton<String>).at(2));
    await tester.pumpAndSettle();
    expect(find.text('Retired'), findsNothing);
    expect(find.text('Old project'), findsNothing);
    await tester.tap(find.text('Initiatives').last);
    await tester.pumpAndSettle();
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
    expect(entryApi.entries.single.people, ['Priya']);
  });

  testWidgets('a support row shows every name in the Log', (tester) async {
    await pumpLog(
      tester,
      entries: [
        testWorkEntry(
          id: 'entry-multi',
          categoryId: 'cat-s',
          subcategoryId: 'sub-s',
          description: 'Paired on the migration',
          people: const ['Priya', 'Sam'],
        ),
      ],
    );

    expect(
      find.textContaining('Support · Unblock · Priya, Sam'),
      findsOneWidget,
    );
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

  testWidgets('row actions are 48px targets and rows keep vertical padding', (
    tester,
  ) async {
    await pumpLog(
      tester,
      entries: [
        testWorkEntry(id: 'entry-a', description: 'Backfill script skeleton'),
      ],
    );

    final target = tester.getSize(find.byTooltip('Row actions'));
    expect(target.width, greaterThanOrEqualTo(48));
    expect(target.height, greaterThanOrEqualTo(48));

    // The header keeps clear space above and below its text instead of
    // letting the description sit on the divider.
    final description = find.text('Backfill script skeleton');
    final header = find
        .ancestor(of: description, matching: find.byType(InkWell))
        .first;
    final descriptionRect = tester.getRect(description);
    final headerRect = tester.getRect(header);
    expect(descriptionRect.top - headerRect.top, greaterThanOrEqualTo(10));
    expect(
      headerRect.bottom - descriptionRect.bottom,
      greaterThanOrEqualTo(10),
    );
  });

  testWidgets('compact density still keeps the row action at 48px', (
    tester,
  ) async {
    await pumpLog(
      tester,
      settings: const AppSettings(density: DensityPreference.compact),
      entries: [
        testWorkEntry(id: 'entry-a', description: 'Backfill script skeleton'),
      ],
    );

    final target = tester.getSize(find.byTooltip('Row actions'));
    expect(target.width, greaterThanOrEqualTo(48));
    expect(target.height, greaterThanOrEqualTo(48));
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

  group('adding an entry from a filtered log', () {
    // The sample entries are today's, so the remembered pair is the newest
    // one: Meetings / Sprint planning.
    const rememberedCategory = 'cat-2';
    const rememberedSubcategory = 'sub-2';

    testWidgets('a category filter seeds the new entry form', (tester) async {
      await pumpLog(tester);
      await pickCategoryFilter(tester, 'Initiatives');
      await openAddEntry(tester);

      expect(formCategoryValue(tester), 'cat-1');
      // The remembered subcategory belongs to another category, so it is not
      // carried across.
      expect(formSubcategoryValue(tester), '');
    });

    testWidgets('a category filter keeps a matching last-used subcategory', (
      tester,
    ) async {
      await pumpLog(tester);
      final state = AppStateScope.read(tester.element(find.byType(LogScreen)));
      state.lastCategoryId = 'cat-1';
      state.lastSubcategoryId = 'sub-1';

      await pickCategoryFilter(tester, 'Initiatives');
      await openAddEntry(tester);

      expect(formCategoryValue(tester), 'cat-1');
      expect(formSubcategoryValue(tester), 'sub-1');
    });

    testWidgets('a subcategory-only filter seeds its parent category', (
      tester,
    ) async {
      await pumpLog(tester);
      // With no category filter the option spells out its parent.
      await pickSubcategoryFilter(tester, 'Billing migration · Initiatives');
      await openAddEntry(tester);

      expect(formCategoryValue(tester), 'cat-1');
      expect(formSubcategoryValue(tester), 'sub-1');
    });

    testWidgets('category and subcategory filters seed both halves', (
      tester,
    ) async {
      await pumpLog(tester);
      await pickCategoryFilter(tester, 'Initiatives');
      await pickSubcategoryFilter(tester, 'Billing migration');
      await openAddEntry(tester);

      expect(formCategoryValue(tester), 'cat-1');
      expect(formSubcategoryValue(tester), 'sub-1');
    });

    testWidgets('an archived filtered category seeds nothing', (tester) async {
      final taxonomy = FakeCategoryApi(
        categories: [
          category('cat-retired', 'Retired', archived: true),
          category('cat-1', 'Initiatives'),
          category('cat-2', 'Meetings', role: CategoryRole.other),
        ],
        subcategories: [
          subcategory('sub-retired', 'cat-retired', 'Old project'),
          subcategory('sub-1', 'cat-1', 'Billing migration'),
          subcategory('sub-2', 'cat-2', 'Sprint planning'),
        ],
      );
      await pumpLog(
        tester,
        categoryApi: taxonomy,
        entries: [
          testWorkEntry(
            id: 'entry-a',
            categoryId: 'cat-1',
            subcategoryId: 'sub-1',
            description: 'Backfill script skeleton',
          ),
        ],
      );

      await pickCategoryFilter(tester, 'Retired');
      await openAddEntry(tester);

      // The form could never produce an archived category, so the remembered
      // pair is used exactly as before the change.
      expect(formCategoryValue(tester), 'cat-1');
      expect(formSubcategoryValue(tester), 'sub-1');
    });

    testWidgets('no taxonomy filter leaves the form unchanged', (tester) async {
      await pumpLog(tester);
      await openAddEntry(tester);

      expect(formCategoryValue(tester), rememberedCategory);
      expect(formSubcategoryValue(tester), rememberedSubcategory);
    });

    testWidgets('a seeded support category shows the person picker', (
      tester,
    ) async {
      await pumpLog(tester);
      await pickCategoryFilter(tester, 'Support');
      await openAddEntry(tester);

      expect(formCategoryValue(tester), 'cat-s');
      expect(personField(), findsOneWidget);
    });

    testWidgets('saving a seeded entry keeps the filters and remembers '
        'the saved pair', (tester) async {
      final entryApi = await pumpLog(tester);
      await pickCategoryFilter(tester, 'Initiatives');
      await openAddEntry(tester);

      await tester.enterText(descriptionField(), 'Billing follow-up');
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();

      expect(entryApi.drafts.single.categoryId, 'cat-1');
      expect(find.text('Entry saved'), findsOneWidget);
      expect(find.text('Billing follow-up'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .value,
        'cat-1',
      );

      // The saved taxonomy becomes the remembered pair for the next entry.
      await pickCategoryFilter(tester, 'All categories');
      await openAddEntry(tester);
      expect(formCategoryValue(tester), 'cat-1');
      expect(formSubcategoryValue(tester), '');
    });

    testWidgets('cancelling and reopening seeds again without changing '
        'the remembered pair', (tester) async {
      await pumpLog(tester);
      await pickCategoryFilter(tester, 'Initiatives');

      await openAddEntry(tester);
      expect(formCategoryValue(tester), 'cat-1');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await openAddEntry(tester);
      expect(formCategoryValue(tester), 'cat-1');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await pickCategoryFilter(tester, 'All categories');
      await openAddEntry(tester);

      // Opening the form did not overwrite the user's last-used pair.
      expect(formCategoryValue(tester), rememberedCategory);
      expect(formSubcategoryValue(tester), rememberedSubcategory);
    });
  });
}
