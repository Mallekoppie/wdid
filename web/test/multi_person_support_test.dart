import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/data/timer_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/state/app_state.dart';

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

typedef Harness = ({
  AppState state,
  FakeTimerApi timerApi,
  FakeEntryApi entryApi,
});

Future<Harness> buildState() async {
  final timerApi = FakeTimerApi();
  final entryApi = FakeEntryApi();
  final state = AppState(
    categoryApi: FakeCategoryApi(
      categories: [
        category('cat-1', 'Initiatives'),
        category('cat-support', 'Support', role: CategoryRole.support),
      ],
      subcategories: [
        subcategory('sub-1', 'cat-1', 'Billing migration'),
        subcategory('mode-s', 'cat-support', 'Unblock'),
      ],
    ),
    settingsApi: FakeSettingsApi(
      settings: const AppSettings(supportPeople: ['Priya', 'Sam', 'Team']),
    ),
    entryApi: entryApi,
    timerApi: timerApi,
  );
  await state.load();
  addTearDown(state.dispose);
  return (state: state, timerApi: timerApi, entryApi: entryApi);
}

void main() {
  test('a timer keeps every name through a start and stop', () async {
    final harness = await buildState();

    await harness.state.startTimer(
      categoryId: 'cat-support',
      subcategoryId: 'mode-s',
      people: const ['Priya', 'Sam', 'priya'],
    );

    // The state normalizes before sending the batch to the service.
    expect(harness.timerApi.lastStartPeople, ['Priya', 'Sam']);
    expect(harness.state.activeTimer!.people, ['Priya', 'Sam']);

    await harness.state.stopTimer();

    final saved = harness.timerApi.savedEntries.single;
    expect(saved.people, ['Priya', 'Sam']);
    expect(harness.state.entries.single.people, ['Priya', 'Sam']);
  });

  test('a one-tap support start is a one-name list', () async {
    final harness = await buildState();

    await harness.state.startSupportTimer(people: const ['Sam']);

    expect(harness.timerApi.lastStartCategoryId, 'cat-support');
    expect(harness.timerApi.lastStartPeople, ['Sam']);
    expect(harness.state.activeTimer!.people, ['Sam']);
  });

  test('a support timer still requires at least one name', () async {
    final harness = await buildState();

    expect(
      () => harness.state.startTimer(categoryId: 'cat-support'),
      throwsA(isA<TimerFailure>()),
    );
  });

  test('team is an ordinary name', () async {
    final harness = await buildState();

    await harness.state.startSupportTimer(people: const ['Team']);

    expect(harness.timerApi.lastStartPeople, ['Team']);
    expect(harness.state.activeTimer!.people, ['Team']);
  });

  test('resuming an interrupted timer carries every name', () async {
    final harness = await buildState();
    harness.state.setInterruptedTimer(
      const InterruptedTimer(
        categoryId: 'cat-support',
        subcategoryId: 'mode-s',
        description: 'Pairing',
        people: ['Priya', 'Sam'],
      ),
    );

    expect(harness.state.interruptedTimerLabel, contains('Priya, Sam'));

    await harness.state.resumeInterruptedTimer();

    expect(harness.timerApi.lastStartPeople, ['Priya', 'Sam']);
    expect(harness.timerApi.lastStartDescription, 'Pairing');
    expect(harness.state.interruptedTimer, isNull);
  });

  test('quick capture sends the whole ordered list', () async {
    final harness = await buildState();

    final entry = await harness.state.quickCapture(
      categoryId: 'cat-support',
      subcategoryId: 'mode-s',
      description: 'Reviewed the migration',
      minutes: 30,
      people: const ['Priya', 'Sam'],
    );

    expect(harness.entryApi.drafts.single.people, ['Priya', 'Sam']);
    expect(entry.people, ['Priya', 'Sam']);
  });

  test('a loaded timer snapshot exposes every name', () async {
    final timerApi = FakeTimerApi();
    final now = DateTime.now().toUtc();
    timerApi.timer = TimerSnapshot(
      categoryId: 'cat-support',
      subcategoryId: 'mode-s',
      description: 'Pairing',
      people: const ['Priya', 'Sam'],
      startedAt: now,
      segmentStartedAt: now,
    );
    final entryApi = FakeEntryApi();
    final state = AppState(
      categoryApi: FakeCategoryApi(
        categories: [
          category('cat-support', 'Support', role: CategoryRole.support),
        ],
        subcategories: [subcategory('mode-s', 'cat-support', 'Unblock')],
      ),
      settingsApi: FakeSettingsApi(settings: const AppSettings()),
      entryApi: entryApi,
      timerApi: timerApi,
    );
    await state.load();
    addTearDown(state.dispose);

    expect(state.activeTimer!.people, ['Priya', 'Sam']);
  });
}
