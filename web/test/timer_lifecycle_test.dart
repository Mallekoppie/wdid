import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/demo_repository.dart';
import 'package:wdid_web/data/timer_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/widgets/searchable_dropdown.dart';
import 'package:wdid_web/widgets/service_timer_card.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';
import 'fake_timer_api.dart';

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

Finder timerDescription() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.hintText == 'What are you working on?',
);

void main() {
  Future<void> pumpToday(
    WidgetTester tester, {
    required FakeTimerApi timerApi,
    FakeEntryApi? entryApi,
  }) async {
    tester.view.physicalSize = const Size(1400, 2000);
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
        settingsApiBuilder: (_) =>
            FakeSettingsApi(settings: const AppSettings()),
        entryApiBuilder: (_) => entryApi ?? FakeEntryApi(),
        timerApiBuilder: (_) => timerApi,
      ),
    );
    await tester.pumpAndSettle();

    // Dispose the app so its poll ticker does not outlive the test.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
  }

  Future<void> startTimer(WidgetTester tester) async {
    final dropdowns = find.descendant(
      of: find.byType(ServiceTimerCard),
      matching: find.byType(SearchableDropdown<String>),
    );
    await tester.tap(dropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: dropdowns.at(1), matching: find.byType(TextField)),
      'Bill',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .widgetWithText(MenuItemButton, 'Billing migration')
          .hitTestable()
          .last,
    );
    await tester.pumpAndSettle();

    await tester.enterText(timerDescription(), 'Backfill script');
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> settleDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('starts, pauses, resumes and stops a server-owned timer', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    await pumpToday(tester, timerApi: timerApi);
    await startTimer(tester);

    expect(timerApi.startCalls, 1);
    expect(timerApi.timer!.categoryId, 'cat-1');
    expect(timerApi.timer!.subcategoryId, 'sub-1');
    expect(timerApi.timer!.description, 'Backfill script');
    expect(find.text('Start timer'), findsNothing);
    expect(
      find.textContaining('Initiatives · Billing migration'),
      findsWidgets,
    );

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(timerApi.timer!.isPaused, isTrue);
    expect(find.text('Paused'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(timerApi.timer!.isPaused, isFalse);

    await tester.tap(find.byTooltip('Stop & save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(timerApi.stopActions, [TimerStopAction.save]);
    expect(timerApi.timer, isNull);
    expect(find.textContaining('Saved 30m'), findsOneWidget);
    expect(find.text('Start timer'), findsOneWidget);
  });

  testWidgets('above the block limit offers keep, trim and discard', (
    tester,
  ) async {
    final timerApi = FakeTimerApi()
      ..elapsedMinutesOnStop = 300
      ..stopConflict = const TimerConflict(TimerConflictReason.blockLimit);
    await pumpToday(tester, timerApi: timerApi);
    await startTimer(tester);

    await tester.tap(find.byTooltip('Stop & save'));
    await settleDialog(tester);

    expect(
      find.text('Still working on Initiatives · Billing migration?'),
      findsOneWidget,
    );
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Trim to 4h'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    await tester.tap(find.text('Trim to 4h'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(timerApi.stopActions, [TimerStopAction.save, TimerStopAction.trim]);
    expect(timerApi.timer, isNull);
    expect(find.textContaining('Saved 4h'), findsOneWidget);
  });

  testWidgets('a stop under one minute can be discarded', (tester) async {
    final timerApi = FakeTimerApi()
      ..stopConflict = const TimerConflict(TimerConflictReason.tooShort);
    await pumpToday(tester, timerApi: timerApi);
    await startTimer(tester);

    await tester.tap(find.byTooltip('Stop & save'));
    await settleDialog(tester);

    expect(find.text('Less than a minute'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(timerApi.stopActions, [
      TimerStopAction.save,
      TimerStopAction.discard,
    ]);
    expect(timerApi.timer, isNull);
    expect(find.text('Timer discarded'), findsOneWidget);
  });

  test('the global start asks for a category instead of guessing', () async {
    final timerApi = FakeTimerApi();
    final state = AppState(
      DemoWdidRepository(latency: Duration.zero),
      categoryApi: FakeCategoryApi(
        categories: [
          category('cat-support', 'Support', role: CategoryRole.support),
          category('cat-1', 'Initiatives'),
        ],
        subcategories: const [],
      ),
      settingsApi: FakeSettingsApi(settings: const AppSettings()),
      entryApi: FakeEntryApi(),
      timerApi: timerApi,
    );
    addTearDown(state.dispose);

    await state.load();
    await expectLater(state.startTimer(), throwsA(isA<TimerFailure>()));

    expect(timerApi.timer, isNull);
  });

  test('a reload follows the server timer instead of inventing one', () async {
    final timerApi = FakeTimerApi();
    await timerApi.startTimer(
      categoryId: 'cat-1',
      subcategoryId: 'sub-1',
      description: 'Backfill script',
    );

    final state = AppState(
      DemoWdidRepository(latency: Duration.zero),
      categoryApi: FakeCategoryApi(
        categories: [category('cat-1', 'Initiatives')],
        subcategories: [subcategory('sub-1', 'cat-1', 'Billing migration')],
      ),
      settingsApi: FakeSettingsApi(settings: const AppSettings()),
      entryApi: FakeEntryApi(),
      timerApi: timerApi,
    );
    addTearDown(state.dispose);

    await state.load();

    expect(state.activeTimer, isNotNull);
    expect(
      state.timerLabel(state.activeTimer!),
      'Initiatives · Billing migration',
    );

    // Another tab stops the timer; the poll picks the change up.
    await timerApi.stopTimer();
    await state.syncTimer();
    expect(state.activeTimer, isNull);
  });
}
