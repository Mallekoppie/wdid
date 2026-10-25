import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/timer_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/screens/today_screen.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/utils/time_utils.dart';
import 'package:wdid_web/widgets/app_shell.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';
import 'fake_timer_api.dart';

Category category(
  String id,
  String name, {
  CategoryRole role = CategoryRole.initiative,
  int sortOrder = 0,
}) => Category(
  id: id,
  name: name,
  role: role,
  sortOrder: sortOrder,
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

/// A service-backed state with an initiative and support taxonomy.
({AppState state, FakeTimerApi timerApi, FakeEntryApi entryApi})
buildState({
  FakeTimerApi? timerApi,
  FakeEntryApi? entryApi,
  List<Category>? categories,
  List<Subcategory>? subcategories,
}) {
  final timer = timerApi ?? FakeTimerApi();
  final entries = entryApi ?? FakeEntryApi();
  final state = AppState(
    categoryApi: FakeCategoryApi(
      categories:
          categories ??
          [
            category('cat-1', 'Initiatives'),
            category('cat-support', 'Support', role: CategoryRole.support),
          ],
      subcategories:
          subcategories ??
          [
            subcategory('sub-1', 'cat-1', 'Billing migration'),
            subcategory('mode-s', 'cat-support', 'Unblock'),
          ],
    ),
    settingsApi: FakeSettingsApi(
      settings: const AppSettings(supportPeople: ['Priya', 'Sam']),
    ),
    entryApi: entries,
    timerApi: timer,
  );
  return (state: state, timerApi: timer, entryApi: entries);
}

/// Puts a timer on the fake server so the app sees one after load.
void seedRunningTimer(
  FakeTimerApi api, {
  String categoryId = 'cat-1',
  String subcategoryId = 'sub-1',
  String description = 'Backfill script',
  String person = '',
}) {
  final now = DateTime.now().toUtc();
  api.timer = TimerSnapshot(
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    description: description,
    person: person,
    startedAt: now.subtract(const Duration(minutes: 20)),
    segmentStartedAt: now.subtract(const Duration(minutes: 20)),
    elapsed: const Duration(minutes: 20),
  );
}

/// Pumps the real app on Today and returns its state.
Future<AppState> pumpApp(
  WidgetTester tester, {
  required FakeTimerApi timerApi,
  FakeEntryApi? entryApi,
  List<Category>? categories,
  List<Subcategory>? subcategories,
  List<String> roster = const ['Priya', 'Sam'],
}) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    WdidApp(
      authApi: FakeAuthApi(),
      initialSession: signedInSession(),
      initialRoute: '/today',
      categoryApiBuilder: (_) => FakeCategoryApi(
        categories:
            categories ??
            [
              category('cat-1', 'Initiatives'),
              category('cat-support', 'Support', role: CategoryRole.support),
            ],
        subcategories:
            subcategories ??
            [
              subcategory('sub-1', 'cat-1', 'Billing migration'),
              subcategory('mode-s', 'cat-support', 'Unblock'),
            ],
      ),
      settingsApiBuilder: (_) => FakeSettingsApi(
        settings: AppSettings(supportPeople: roster),
      ),
      entryApiBuilder: (_) => entryApi ?? FakeEntryApi(),
      timerApiBuilder: (_) => timerApi,
    ),
  );
  await tester.pumpAndSettle();

  // Dispose the app so its poll ticker does not outlive the test.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
  });

  return AppStateScope.read(tester.element(find.byType(AppShell)));
}

void main() {
  test('a stash resumes as a fresh timer and is consumed', () async {
    final harness = buildState();
    addTearDown(harness.state.dispose);
    await harness.state.load();

    harness.state.setInterruptedTimer(
      const InterruptedTimer(
        categoryId: 'cat-1',
        subcategoryId: 'sub-1',
        description: 'Backfill script',
      ),
    );

    expect(harness.state.interruptedTimer, isNotNull);
    expect(
      harness.state.interruptedTimerLabel,
      'Initiatives · Billing migration',
    );

    await harness.state.resumeInterruptedTimer();

    expect(harness.timerApi.startCalls, 1);
    expect(harness.timerApi.timer!.categoryId, 'cat-1');
    expect(harness.timerApi.timer!.subcategoryId, 'sub-1');
    expect(harness.timerApi.timer!.description, 'Backfill script');
    expect(
      harness.state.interruptedTimer,
      isNull,
      reason: 'resuming consumes the stash',
    );
  });

  test('a new interrupt overwrites the stash', () async {
    final harness = buildState();
    addTearDown(harness.state.dispose);
    await harness.state.load();

    harness.state.setInterruptedTimer(
      const InterruptedTimer(categoryId: 'cat-1', subcategoryId: 'sub-1'),
    );
    harness.state.setInterruptedTimer(
      const InterruptedTimer(categoryId: 'cat-support'),
    );

    expect(harness.state.interruptedTimer!.categoryId, 'cat-support');
    expect(harness.state.interruptedTimer!.subcategoryId, isEmpty);
  });

  test('the default support category is the most recently used one', () async {
    final harness = buildState(
      categories: [
        category('cat-support-a', 'Support A', role: CategoryRole.support),
        category('cat-support-b', 'Support B', role: CategoryRole.support),
        category('cat-1', 'Initiatives'),
      ],
      subcategories: [
        subcategory('mode-a', 'cat-support-a', 'Unblock'),
        subcategory('mode-b', 'cat-support-b', 'Pairing'),
      ],
    );
    addTearDown(harness.state.dispose);
    await harness.state.load();

    expect(
      harness.state.defaultSupportCategory!.id,
      'cat-support-a',
      reason: 'without history the first support category is the fallback',
    );

    await harness.state.startTimer(
      categoryId: 'cat-support-b',
      person: 'Sam',
    );
    await harness.state.stopTimer();

    expect(harness.state.defaultSupportCategory!.id, 'cat-support-b');
  });

  testWidgets(
    'header interrupt saves the initiative and starts support in place',
    (tester) async {
      final timerApi = FakeTimerApi();
      seedRunningTimer(timerApi);
      final entryApi = FakeEntryApi();
      final state = await pumpApp(
        tester,
        timerApi: timerApi,
        entryApi: entryApi,
      );

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('Interrupt'), findsOneWidget);

      await tester.tap(find.text('Interrupt'));
      await tester.pumpAndSettle();

      // The running initiative was saved through the normal stop path.
      expect(timerApi.savedEntries, hasLength(1));
      expect(timerApi.savedEntries.single.categoryId, 'cat-1');
      expect(timerApi.savedEntries.single.subcategoryId, 'sub-1');
      expect(timerApi.savedEntries.single.description, 'Backfill script');
      expect(state.interruptedTimer, isNotNull);
      expect(state.interruptedTimer!.categoryId, 'cat-1');
      expect(state.interruptedTimer!.subcategoryId, 'sub-1');
      expect(state.interruptedTimer!.description, 'Backfill script');

      // The person picker is anchored in the header, not a route.
      expect(find.text('Who are you supporting?'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Priya'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(timerApi.startCalls, 1);
      expect(timerApi.lastStartCategoryId, 'cat-support');
      expect(timerApi.lastStartSubcategoryId, isEmpty);
      expect(timerApi.lastStartDescription, isEmpty);
      expect(timerApi.lastStartPerson, 'Priya');
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('Who are you supporting?'), findsNothing);
    },
  );

  testWidgets('cancelling the under-a-minute decision starts nothing', (
    tester,
  ) async {
    final timerApi = FakeTimerApi()
      ..stopConflict = const TimerConflict(TimerConflictReason.tooShort);
    seedRunningTimer(timerApi);
    final state = await pumpApp(tester, timerApi: timerApi);

    await tester.tap(find.text('Interrupt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Less than a minute'), findsOneWidget);

    await tester.tap(find.text('Keep working'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(timerApi.startCalls, 0);
    expect(timerApi.timer, isNotNull, reason: 'the timer keeps running');
    expect(state.interruptedTimer, isNull);
    expect(find.text('Who are you supporting?'), findsNothing);
  });

  testWidgets('cancelling the block-limit decision starts nothing', (
    tester,
  ) async {
    final timerApi = FakeTimerApi()
      ..stopConflict = const TimerConflict(TimerConflictReason.blockLimit);
    seedRunningTimer(timerApi);
    final state = await pumpApp(tester, timerApi: timerApi);

    await tester.tap(find.text('Interrupt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Still working on Initiatives · Billing migration?'),
      findsOneWidget,
    );
    expect(find.text('Keep'), findsOneWidget);

    // Dismissing the barrier is the cancel path for this dialog.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(timerApi.startCalls, 0);
    expect(timerApi.timer, isNotNull);
    expect(state.interruptedTimer, isNull);
    expect(find.text('Who are you supporting?'), findsNothing);
  });
}
