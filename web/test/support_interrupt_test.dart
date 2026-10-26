import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/timer_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/screens/today_screen.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/widgets/app_shell.dart';
import 'package:wdid_web/widgets/interrupt_resume_card.dart';
import 'package:wdid_web/widgets/support_now_strip.dart';
import 'package:wdid_web/widgets/timer_pill.dart';

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
({AppState state, FakeTimerApi timerApi, FakeEntryApi entryApi}) buildState({
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
  List<String> people = const [],
}) {
  final now = DateTime.now().toUtc();
  api.timer = TimerSnapshot(
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    description: description,
    people: people,
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
  Size viewport = const Size(1600, 2400),
}) async {
  tester.view.physicalSize = viewport;
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
      settingsApiBuilder: (_) =>
          FakeSettingsApi(settings: AppSettings(supportPeople: roster)),
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

  test('a manual start clears the interrupt stash', () async {
    final harness = buildState();
    addTearDown(harness.state.dispose);
    await harness.state.load();

    harness.state.setInterruptedTimer(
      const InterruptedTimer(categoryId: 'cat-1', subcategoryId: 'sub-1'),
    );

    await harness.state.startTimer(categoryId: 'cat-1', subcategoryId: 'sub-1');

    expect(
      harness.state.interruptedTimer,
      isNull,
      reason: 'an unrelated start must not leave a stale Resume offer',
    );
  });

  test('a failed start keeps the interrupt stash', () async {
    final harness = buildState();
    addTearDown(harness.state.dispose);
    await harness.state.load();
    // A timer on the server the client has not synced yet makes the start fail.
    seedRunningTimer(harness.timerApi);

    harness.state.setInterruptedTimer(
      const InterruptedTimer(categoryId: 'cat-1', subcategoryId: 'sub-1'),
    );

    await expectLater(
      harness.state.startTimer(categoryId: 'cat-1', subcategoryId: 'sub-1'),
      throwsA(isA<TimerFailure>()),
    );

    expect(
      harness.state.interruptedTimer,
      isNotNull,
      reason: 'a start that never happened must keep the offer',
    );
  });

  test('a preserved support start keeps the stash past its stop', () async {
    final harness = buildState();
    addTearDown(harness.state.dispose);
    await harness.state.load();

    harness.state.setInterruptedTimer(
      const InterruptedTimer(categoryId: 'cat-1', subcategoryId: 'sub-1'),
    );

    await harness.state.startSupportTimer(
      people: const ['Priya'],
      preserveInterruptedTimer: true,
    );
    expect(
      harness.state.interruptedTimer,
      isNotNull,
      reason: 'the interrupt target is needed when support ends',
    );

    await harness.state.stopTimer();
    expect(harness.state.interruptedTimer, isNotNull);
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
      people: const ['Sam'],
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
      expect(find.text('Start a support timer'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(MenuAnchor),
          matching: find.widgetWithText(ChoiceChip, 'Priya'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(timerApi.startCalls, 1);
      expect(timerApi.lastStartCategoryId, 'cat-support');
      expect(timerApi.lastStartSubcategoryId, isEmpty);
      expect(timerApi.lastStartDescription, isEmpty);
      expect(timerApi.lastStartPeople, ['Priya']);
      expect(
        state.interruptedTimer,
        isNotNull,
        reason: 'the interrupt target survives the support start',
      );
      expect(find.byType(TodayScreen), findsOneWidget);
      expect(find.text('Start a support timer'), findsNothing);
    },
  );

  testWidgets('narrow headers keep every timer action at 48px', (tester) async {
    final timerApi = FakeTimerApi();
    seedRunningTimer(timerApi);
    await pumpApp(tester, timerApi: timerApi, viewport: const Size(600, 1200));

    // Below 900px the segments are icon-only, so their tooltips carry the
    // label and each one stays a full 48px target. The Today timer card keeps
    // its own labelled buttons, so scope this to the header pill.
    final pill = find.byType(TimerPill);
    expect(
      find.descendant(of: pill, matching: find.text('Interrupt')),
      findsNothing,
    );
    expect(
      find.descendant(of: pill, matching: find.text('Pause')),
      findsNothing,
    );
    expect(
      find.descendant(of: pill, matching: find.text('Stop')),
      findsNothing,
    );
    for (final tooltip in [
      'Interrupt the running timer and start support',
      'Pause',
      'Stop & save',
    ]) {
      final size = tester.getSize(
        find.descendant(of: pill, matching: find.byTooltip(tooltip)),
      );
      expect(size.width, greaterThanOrEqualTo(48), reason: tooltip);
      expect(size.height, greaterThanOrEqualTo(48), reason: tooltip);
    }
  });

  testWidgets('an interrupt shows a pinned, auto-width resume card', (
    tester,
  ) async {
    final timerApi = FakeTimerApi()..elapsedMinutesOnStop = 20;
    seedRunningTimer(timerApi);
    await pumpApp(tester, timerApi: timerApi);

    await tester.tap(find.text('Interrupt'));
    await tester.pumpAndSettle();

    final card = find.byType(InterruptResumeCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Saved 20m')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('Initiatives · Billing migration'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byTooltip('Done')),
      findsOneWidget,
    );

    final rect = tester.getRect(card);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      rect.width,
      lessThan(screen.width / 2),
      reason: 'the card is auto-width, not full-width',
    );
    expect(
      rect.right,
      greaterThan(screen.width - 64),
      reason: 'the card is pinned to the right edge',
    );
    expect(
      rect.bottom,
      greaterThan(screen.height - 64),
      reason: 'the card is pinned to the bottom edge',
    );
  });

  testWidgets('Resume on the card starts a fresh timer and closes it', (
    tester,
  ) async {
    final timerApi = FakeTimerApi()..elapsedMinutesOnStop = 20;
    seedRunningTimer(timerApi);
    final state = await pumpApp(tester, timerApi: timerApi);

    await tester.tap(find.text('Interrupt'));
    await tester.pumpAndSettle();

    final card = find.byType(InterruptResumeCard);
    expect(card, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: card,
        matching: find.widgetWithText(FilledButton, 'Resume'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(timerApi.startCalls, 1, reason: 'Resume starts a new timer');
    expect(timerApi.lastStartCategoryId, 'cat-1');
    expect(timerApi.lastStartSubcategoryId, 'sub-1');
    expect(timerApi.lastStartDescription, 'Backfill script');
    expect(state.interruptedTimer, isNull);
    expect(find.byType(InterruptResumeCard), findsNothing);
  });

  testWidgets('Done on the card forgets the stash without starting', (
    tester,
  ) async {
    final timerApi = FakeTimerApi()..elapsedMinutesOnStop = 20;
    seedRunningTimer(timerApi);
    final state = await pumpApp(tester, timerApi: timerApi);

    await tester.tap(find.text('Interrupt'));
    await tester.pumpAndSettle();

    final card = find.byType(InterruptResumeCard);
    expect(card, findsOneWidget);

    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Done')),
    );
    await tester.pump();

    expect(state.interruptedTimer, isNull);
    expect(find.byType(InterruptResumeCard), findsNothing);
    expect(timerApi.startCalls, 0);
    expect(timerApi.timer, isNull);
  });

  testWidgets('an old interrupt stash never attaches Resume to a later stop', (
    tester,
  ) async {
    final timerApi = FakeTimerApi()..elapsedMinutesOnStop = 20;
    seedRunningTimer(timerApi);
    final state = await pumpApp(tester, timerApi: timerApi);

    // Interrupt the initiative and start support, leaving the stash in memory.
    await tester.tap(find.text('Interrupt'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MenuAnchor),
        matching: find.widgetWithText(ChoiceChip, 'Priya'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.interruptedTimer, isNotNull);
    expect(find.byType(InterruptResumeCard), findsOneWidget);

    // Let the support-start toast retire so the stop toast is the only one.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    // This stop is ordinary even though an old interrupt stash exists.
    await tester.tap(find.widgetWithText(FilledButton, 'Stop & save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final snackBar = find.byType(SnackBar);
    expect(snackBar, findsOneWidget);
    expect(tester.widget<SnackBar>(snackBar).action, isNull);
    expect(find.byType(SnackBarAction), findsNothing);
    expect(
      find.byType(InterruptResumeCard),
      findsOneWidget,
      reason: 'a later stop must not replace the interrupt card',
    );
    expect(state.interruptedTimer, isNotNull);
  });

  testWidgets('an ordinary stop shows only a brief, actionless toast', (
    tester,
  ) async {
    final timerApi = FakeTimerApi()..elapsedMinutesOnStop = 20;
    final state = await pumpApp(tester, timerApi: timerApi);

    await state.startTimer(
      categoryId: 'cat-1',
      subcategoryId: 'sub-1',
      description: 'Backfill script',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Stop & save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final snackBar = find.byType(SnackBar);
    expect(snackBar, findsOneWidget);
    expect(
      find.text('Saved 20m · Backfill script'),
      findsOneWidget,
      reason: 'the ordinary stop still confirms what it saved',
    );
    final bar = tester.widget<SnackBar>(snackBar);
    expect(bar.action, isNull);
    expect(bar.duration, const Duration(seconds: 2));
    expect(find.byType(SnackBarAction), findsNothing);
    expect(find.byType(InterruptResumeCard), findsNothing);

    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: 'the toast auto-dismisses',
    );
  });

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
    expect(find.text('Start a support timer'), findsNothing);
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
    expect(find.text('Start a support timer'), findsNothing);
  });

  testWidgets('the Today support strip starts a support timer with one tap', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    await pumpApp(tester, timerApi: timerApi);

    final strip = find.byType(SupportNowStrip);
    expect(strip, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: strip,
        matching: find.widgetWithText(ChoiceChip, 'Priya'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(timerApi.startCalls, 1);
    expect(timerApi.lastStartCategoryId, 'cat-support');
    expect(timerApi.lastStartSubcategoryId, isEmpty);
    expect(timerApi.lastStartDescription, isEmpty);
    expect(timerApi.lastStartPeople, ['Priya']);
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('the Today support strip stops the running timer first', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    seedRunningTimer(timerApi);
    final state = await pumpApp(tester, timerApi: timerApi);

    final strip = find.byType(SupportNowStrip);
    await tester.tap(
      find.descendant(
        of: strip,
        matching: find.widgetWithText(ChoiceChip, 'Sam'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(timerApi.savedEntries, hasLength(1));
    expect(timerApi.savedEntries.single.categoryId, 'cat-1');
    expect(timerApi.stopActions, [TimerStopAction.save]);
    expect(timerApi.startCalls, 1);
    expect(timerApi.lastStartCategoryId, 'cat-support');
    expect(timerApi.lastStartPeople, ['Sam']);
    expect(state.interruptedTimer!.categoryId, 'cat-1');
    expect(state.interruptedTimer!.subcategoryId, 'sub-1');
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('Resume restores the interruption as a new block', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    seedRunningTimer(timerApi);
    final state = await pumpApp(tester, timerApi: timerApi);

    // Interrupt the initiative and pick the person.
    await tester.tap(find.text('Interrupt'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MenuAnchor),
        matching: find.widgetWithText(ChoiceChip, 'Priya'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(timerApi.timer!.categoryId, 'cat-support');

    // Stop the interrupt timer from the Today card.
    await tester.tap(find.widgetWithText(FilledButton, 'Stop & save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Nothing resumes automatically; the interrupt card survives the later
    // ordinary stop and keeps carrying the offer.
    final card = find.byType(InterruptResumeCard);
    expect(timerApi.timer, isNull);
    expect(timerApi.startCalls, 1);
    expect(card, findsOneWidget);
    expect(state.interruptedTimer, isNotNull);

    await tester.tap(
      find.descendant(
        of: card,
        matching: find.widgetWithText(FilledButton, 'Resume'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(timerApi.startCalls, 2);
    expect(timerApi.lastStartCategoryId, 'cat-1');
    expect(timerApi.lastStartSubcategoryId, 'sub-1');
    expect(timerApi.lastStartDescription, 'Backfill script');
    expect(state.interruptedTimer, isNull);
    expect(
      find.byType(InterruptResumeCard),
      findsNothing,
      reason: 'the card disappears once the stash is consumed',
    );
  });

  testWidgets('a manual start clears the Resume offer after an interrupt', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    seedRunningTimer(timerApi);
    final state = await pumpApp(tester, timerApi: timerApi);

    // Interrupt the initiative and start support.
    await tester.tap(find.text('Interrupt'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MenuAnchor),
        matching: find.widgetWithText(ChoiceChip, 'Priya'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Stop the support timer; the interrupt target stays resumable.
    await tester.tap(find.widgetWithText(FilledButton, 'Stop & save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.interruptedTimer, isNotNull);

    // The interrupt card carries the offer once the toast has retired.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(InterruptResumeCard), findsOneWidget);

    await state.startTimer(categoryId: 'cat-1', subcategoryId: 'sub-1');
    await tester.pump();

    expect(state.interruptedTimer, isNull);
    expect(
      find.byType(InterruptResumeCard),
      findsNothing,
      reason: 'starting anything else retires the old Resume offer',
    );
  });

  testWidgets('an unrelated stop toast has no Resume action', (tester) async {
    final timerApi = FakeTimerApi();
    final state = await pumpApp(tester, timerApi: timerApi);

    await state.startTimer(categoryId: 'cat-1', subcategoryId: 'sub-1');
    await tester.pump();
    expect(state.interruptedTimer, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Stop & save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final snackBars = find.byType(SnackBar);
    expect(snackBars, findsOneWidget);
    expect(tester.widget<SnackBar>(snackBars).action, isNull);
  });

  testWidgets(
    'the interrupt entry gets a mode selector that re-files and clears',
    (tester) async {
      final timerApi = FakeTimerApi();
      seedRunningTimer(timerApi);
      final entryApi = FakeEntryApi();
      final state = await pumpApp(
        tester,
        timerApi: timerApi,
        entryApi: entryApi,
        categories: [
          category('cat-1', 'Initiatives'),
          category('cat-support', 'Support', role: CategoryRole.support),
          category('cat-mentoring', 'Mentoring', role: CategoryRole.support),
        ],
        subcategories: [
          subcategory('sub-1', 'cat-1', 'Billing migration'),
          subcategory('mode-s', 'cat-support', 'Unblock'),
          subcategory('mode-m', 'cat-mentoring', 'Pairing'),
        ],
      );

      // Interrupt the initiative and start the support timer.
      await tester.tap(find.text('Interrupt'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MenuAnchor),
          matching: find.widgetWithText(ChoiceChip, 'Priya'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Stop the interrupt timer so the support entry lands on Today.
      await tester.tap(find.widgetWithText(FilledButton, 'Stop & save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Mode'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.byTooltip('Change support mode'), findsOneWidget);
      // The menu anchor must be the visible control, not the width of the
      // cell, or the highlight and the opened menu land to its left.
      expect(
        tester.getSize(find.byTooltip('Change support mode')).width,
        lessThan(240),
      );

      await tester.tap(find.byTooltip('Change support mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pairing').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(entryApi.updateCalls, 1);
      final reFiled = entryApi.entries.singleWhere(
        (entry) => entry.categoryId == 'cat-mentoring',
      );
      expect(reFiled.subcategoryId, 'mode-m');
      expect(find.textContaining('Mentoring · Pairing'), findsOneWidget);
      expect(find.text('Not set'), findsNothing);
      expect(
        state.entries.any((entry) => entry.categoryId == 'cat-mentoring'),
        isTrue,
      );

      // The selector stays available after a mode exists, so it can be changed.
      await tester.tap(find.byTooltip('Change support mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unblock').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(entryApi.updateCalls, 2);
      final changed = entryApi.entries.singleWhere(
        (entry) => entry.id == reFiled.id,
      );
      expect(changed.categoryId, 'cat-support');
      expect(changed.subcategoryId, 'mode-s');
      expect(find.textContaining('Support · Unblock'), findsOneWidget);

      // Clearing removes the mode but keeps the entry on Today.
      await tester.tap(find.widgetWithText(TextButton, 'Clear'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(entryApi.updateCalls, 3);
      final cleared = entryApi.entries.singleWhere(
        (entry) => entry.id == reFiled.id,
      );
      expect(cleared.categoryId, 'cat-support');
      expect(cleared.subcategoryId, isEmpty);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.textContaining('Support · Priya'), findsOneWidget);
    },
  );

  testWidgets('header Start opens the person picker for a support default', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    final state = await pumpApp(tester, timerApi: timerApi);

    // Leave a support category as the remembered start category.
    await state.startTimer(categoryId: 'cat-support', people: const ['Priya']);
    await tester.pump();
    await state.stopTimer();
    await tester.pump();
    expect(state.activeTimer, isNull);
    expect(state.lastCategoryId, 'cat-support');

    await tester.tap(find.text('Start timer'));
    await tester.pumpAndSettle();

    expect(find.text('Start a support timer'), findsOneWidget);
    expect(
      find.text('Who are you supporting? Add a person first.'),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(MenuAnchor),
        matching: find.widgetWithText(ChoiceChip, 'Sam'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(timerApi.startCalls, 2, reason: 'setup start plus the picker start');
    expect(timerApi.lastStartCategoryId, 'cat-support');
    expect(timerApi.lastStartSubcategoryId, isEmpty);
    expect(timerApi.lastStartPeople, ['Sam']);
  });

  testWidgets('header Start still starts an initiative default directly', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    final state = await pumpApp(tester, timerApi: timerApi);

    await state.startTimer(categoryId: 'cat-1', subcategoryId: 'sub-1');
    await tester.pump();
    await state.stopTimer();
    await tester.pump();
    expect(state.lastCategoryId, 'cat-1');

    await tester.tap(find.text('Start timer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Start a support timer'), findsNothing);
    expect(timerApi.startCalls, 2, reason: 'setup start plus the button start');
    expect(timerApi.lastStartCategoryId, 'cat-1');
  });

  testWidgets('T opens the person picker for a support default too', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    final state = await pumpApp(tester, timerApi: timerApi);

    await state.startTimer(categoryId: 'cat-support', people: const ['Priya']);
    await tester.pump();
    await state.stopTimer();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AlertDialog, 'Start support'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ChoiceChip, 'Sam'),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Start'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(timerApi.startCalls, 2);
    expect(timerApi.lastStartCategoryId, 'cat-support');
    expect(timerApi.lastStartPeople, ['Sam']);
  });

  testWidgets('the Now strip can start support for several people', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    await pumpApp(tester, timerApi: timerApi);

    final strip = find.byType(SupportNowStrip);
    await tester.tap(
      find.descendant(
        of: strip,
        matching: find.widgetWithText(TextButton, 'Several people'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ChoiceChip, 'Priya'),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ChoiceChip, 'Sam'),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Start support'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(timerApi.startCalls, 1);
    expect(timerApi.lastStartCategoryId, 'cat-support');
    expect(timerApi.lastStartPeople, ['Priya', 'Sam']);
  });

  testWidgets('the header picker can start support for several people', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    final state = await pumpApp(tester, timerApi: timerApi);

    await state.startTimer(categoryId: 'cat-support', people: const ['Priya']);
    await tester.pump();
    await state.stopTimer();
    await tester.pump();

    await tester.tap(find.text('Start timer'));
    await tester.pumpAndSettle();
    expect(find.text('Start a support timer'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(MenuAnchor),
        matching: find.widgetWithText(TextButton, 'Several people'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ChoiceChip, 'Priya'),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ChoiceChip, 'Sam'),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Start support'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(timerApi.startCalls, 2);
    expect(timerApi.lastStartCategoryId, 'cat-support');
    expect(timerApi.lastStartPeople, ['Priya', 'Sam']);
  });
}
