import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/demo_repository.dart';
import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/utils/time_utils.dart';
import 'package:wdid_web/widgets/quick_capture_bar.dart';

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

WorkEntry todayEntry({
  String id = 'entry-1',
  String categoryId = 'cat-1',
  String subcategoryId = 'sub-1',
  String description = 'Backfill script skeleton',
  String outcome = '',
  int minutes = 42,
}) {
  final started = DateTime.now().subtract(Duration(minutes: minutes));
  return WorkEntry(
    id: id,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    description: description,
    outcome: outcome,
    startedAt: started.toUtc(),
    endedAt: started.add(Duration(minutes: minutes)).toUtc(),
    minutes: minutes,
    localDate: isoDate(started),
    createdAt: started.toUtc(),
    updatedAt: started.toUtc(),
  );
}

Finder descriptionField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.hintText == 'What did you do?',
);

Finder dropdownAt(int index) => find.byType(DropdownButton<String>).at(index);

void main() {
  Future<void> pumpToday(
    WidgetTester tester, {
    required FakeEntryApi entryApi,
    FakeCategoryApi? categoryApi,
    FakeSettingsApi? settingsApi,
  }) async {
    tester.view.physicalSize = const Size(1400, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        repository: DemoWdidRepository(latency: Duration.zero),
        authApi: FakeAuthApi(),
        initialRoute: '/today',
        categoryApiBuilder: (_) =>
            categoryApi ??
            FakeCategoryApi(
              categories: [
                category('cat-1', 'Initiatives'),
                category('cat-2', 'Meetings'),
              ],
              subcategories: [
                subcategory('sub-1', 'cat-1', 'Billing migration'),
                subcategory('sub-2', 'cat-2', 'Sprint planning'),
              ],
            ),
        settingsApiBuilder: (_) =>
            settingsApi ??
            FakeSettingsApi(
              settings: const AppSettings(defaultDurationMinutes: 45),
            ),
        entryApiBuilder: (_) => entryApi,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('captures one line with the settings default duration', (
    tester,
  ) async {
    final entryApi = FakeEntryApi();
    await pumpToday(tester, entryApi: entryApi);

    final selectedChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '45m'),
    );
    expect(selectedChip.selected, isTrue);

    await tester.tap(dropdownAt(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meetings').last);
    await tester.pumpAndSettle();

    await tester.tap(dropdownAt(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sprint planning').last);
    await tester.pumpAndSettle();

    await tester.enterText(descriptionField(), 'Planned the sprint');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(entryApi.drafts, hasLength(1));
    final draft = entryApi.drafts.single;
    expect(draft.categoryId, 'cat-2');
    expect(draft.subcategoryId, 'sub-2');
    expect(draft.description, 'Planned the sprint');
    expect(draft.minutes, 45);
    expect(find.textContaining('Logged 45m'), findsOneWidget);
    expect(find.textContaining('Planned the sprint'), findsOneWidget);
  });

  testWidgets('remembers the last used category and subcategory', (
    tester,
  ) async {
    final entryApi = FakeEntryApi();
    await pumpToday(tester, entryApi: entryApi);

    await tester.tap(dropdownAt(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meetings').last);
    await tester.pumpAndSettle();
    await tester.tap(dropdownAt(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sprint planning').last);
    await tester.pumpAndSettle();

    await tester.enterText(descriptionField(), 'First capture');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.enterText(descriptionField(), 'Second capture');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(entryApi.drafts, hasLength(2));
    expect(entryApi.drafts.last.categoryId, 'cat-2');
    expect(entryApi.drafts.last.subcategoryId, 'sub-2');

    // The pair lives in AppState, not only in the bar's widget state, so a
    // rebuilt capture bar picks it up.
    final state = AppStateScope.read(
      tester.element(find.byType(QuickCaptureBar)),
    );
    expect(state.lastCategoryId, 'cat-2');
    expect(state.lastSubcategoryId, 'sub-2');
  });

  testWidgets('captures a support entry with the required person', (
    tester,
  ) async {
    final entryApi = FakeEntryApi();
    await pumpToday(
      tester,
      entryApi: entryApi,
      categoryApi: FakeCategoryApi(
        categories: [
          category('cat-support', 'Support', role: CategoryRole.support),
        ],
        subcategories: [subcategory('sub-review', 'cat-support', 'Review')],
      ),
    );

    await tester.enterText(descriptionField(), 'Reviewed the migration plan');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Who did you support?'), findsWidgets);
    expect(entryApi.drafts, isEmpty);

    final personField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Person',
    );
    await tester.enterText(personField, 'Priya');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(entryApi.drafts, hasLength(1));
    expect(entryApi.drafts.single.person, 'Priya');
    expect(entryApi.drafts.single.categoryId, 'cat-support');
  });

  test('loading today entries prefills the remembered pair', () async {
    final entryApi = FakeEntryApi(
      entries: [todayEntry(categoryId: 'cat-2', subcategoryId: 'sub-2')],
    );
    final state = AppState(
      DemoWdidRepository(latency: Duration.zero),
      categoryApi: FakeCategoryApi(
        categories: [
          category('cat-1', 'Initiatives'),
          category('cat-2', 'Meetings'),
        ],
        subcategories: [
          subcategory('sub-1', 'cat-1', 'Billing migration'),
          subcategory('sub-2', 'cat-2', 'Sprint planning'),
        ],
      ),
      settingsApi: FakeSettingsApi(),
      entryApi: entryApi,
    );

    await state.load();
    await state.loadEntries();

    expect(state.lastCategoryId, 'cat-2');
    expect(state.lastSubcategoryId, 'sub-2');
  });

  testWidgets('validates the description and keeps service field errors', (
    tester,
  ) async {
    final entryApi = FakeEntryApi();
    await pumpToday(tester, entryApi: entryApi);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Describe what you did first.'), findsOneWidget);
    expect(entryApi.drafts, isEmpty);

    entryApi.createFailure = const EntryFailure(
      'description: is required',
      field: 'description',
    );
    await tester.enterText(descriptionField(), 'Something');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('description: is required'), findsOneWidget);
  });

  testWidgets('shows a missing-category validation on the selector', (
    tester,
  ) async {
    final entryApi = FakeEntryApi();
    await pumpToday(tester, entryApi: entryApi, categoryApi: FakeCategoryApi());

    await tester.enterText(descriptionField(), 'Something');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a category.'), findsOneWidget);
    expect(entryApi.drafts, isEmpty);
  });

  testWidgets("lists today's entries and adds an outcome afterwards", (
    tester,
  ) async {
    final entryApi = FakeEntryApi(entries: [todayEntry()]);
    await pumpToday(tester, entryApi: entryApi);

    expect(find.text('Billing migration'), findsWidgets);
    expect(find.textContaining('Backfill script skeleton'), findsOneWidget);
    expect(find.text('42m'), findsWidgets);

    await tester.tap(find.text('Add outcome'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'Script runs against staging',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save outcome'));
    await tester.pumpAndSettle();

    expect(entryApi.updateCalls, 1);
    expect(entryApi.entries.single.outcome, 'Script runs against staging');
    expect(find.text('Script runs against staging'), findsOneWidget);
  });

  testWidgets('shows an existing outcome in the list', (tester) async {
    final entryApi = FakeEntryApi(
      entries: [todayEntry(outcome: 'Script runs against staging')],
    );
    await pumpToday(tester, entryApi: entryApi);

    expect(find.text('Script runs against staging'), findsOneWidget);
    expect(find.text('Edit outcome'), findsOneWidget);
  });

  testWidgets("handles loading, error and empty today's entries", (
    tester,
  ) async {
    final gate = Completer<List<WorkEntry>>();
    final entryApi = FakeEntryApi()..listGate = gate;

    tester.view.physicalSize = const Size(1400, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        repository: DemoWdidRepository(latency: Duration.zero),
        authApi: FakeAuthApi(),
        initialRoute: '/today',
        categoryApiBuilder: (_) => FakeCategoryApi(
          categories: [category('cat-1', 'Initiatives')],
          subcategories: [subcategory('sub-1', 'cat-1', 'Billing migration')],
        ),
        settingsApiBuilder: (_) => FakeSettingsApi(),
        entryApiBuilder: (_) => entryApi,
      ),
    );

    // The page becomes ready while the entry list is still in flight.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text("Loading today's entries…"), findsOneWidget);

    entryApi.listFailure = const EntryFailure('The service is unreachable.');
    gate.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('The service is unreachable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    entryApi.listFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing logged yet'), findsOneWidget);
  });
}
