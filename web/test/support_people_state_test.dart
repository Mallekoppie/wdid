import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/data/settings_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/state/app_state.dart';

import 'fake_preferences_api.dart';

Future<(AppState, FakeSettingsApi)> buildState({
  AppSettings settings = const AppSettings(),
}) async {
  final api = FakeSettingsApi(settings: settings);
  final state = AppState(settingsApi: api);
  await state.load();
  addTearDown(state.dispose);
  return (state, api);
}

void main() {
  test('adding a person appends once and persists the roster', () async {
    final (state, api) = await buildState(
      settings: const AppSettings(supportPeople: ['Priya']),
    );

    await state.addSupportPerson('Sam');

    expect(state.supportPeople, ['Priya', 'Sam']);
    expect(api.settings.supportPeople, ['Priya', 'Sam']);
    expect(api.updateCalls, 1);
  });

  test('adding a person is case-insensitive and trims the name', () async {
    final (state, api) = await buildState(
      settings: const AppSettings(supportPeople: ['Priya']),
    );

    await state.addSupportPerson('  priya ');

    expect(state.supportPeople, ['Priya']);
    expect(api.updateCalls, 0);

    await state.addSupportPerson('  Sam  ');
    expect(state.supportPeople, ['Priya', 'Sam']);
    expect(api.settings.supportPeople, ['Priya', 'Sam']);
  });

  test(
    'a failed write keeps the optimistic roster and does not throw',
    () async {
      final (state, api) = await buildState(
        settings: const AppSettings(supportPeople: ['Priya']),
      );
      api.failure = const SettingsFailure('The service is unreachable.');

      await state.addSupportPerson('Sam');

      expect(state.supportPeople, ['Priya', 'Sam']);
      expect(state.preferencesError, isNull);
    },
  );

  test(
    'an add while preferences load never writes defaults over the server',
    () async {
      final api = FakeSettingsApi(
        settings: const AppSettings(supportPeople: ['Priya']),
      );
      final gate = Completer<void>();
      api.gate = gate;
      final state = AppState(settingsApi: api);
      addTearDown(state.dispose);

      final loading = state.load();
      expect(state.preferencesLoading, isTrue);

      await state.addSupportPerson('Sam');
      expect(
        api.updateCalls,
        0,
        reason: 'must not persist before the real settings arrive',
      );

      gate.complete();
      await loading;

      expect(state.supportPeople, ['Priya']);
    },
  );

  test('removing a person only changes the roster, never an entry', () async {
    final entries = [
      WorkEntry(
        id: 'entry-1',
        categoryId: 'cat-support',
        description: 'Unblocked the migration',
        startedAt: DateTime.utc(2026, 10, 23, 9),
        endedAt: DateTime.utc(2026, 10, 23, 9, 30),
        minutes: 30,
        localDate: '2026-10-23',
        person: 'Priya',
        createdAt: DateTime.utc(2026, 10, 23, 9),
        updatedAt: DateTime.utc(2026, 10, 23, 9),
      ),
    ];
    final (state, api) = await buildState(
      settings: const AppSettings(supportPeople: ['Priya', 'Sam']),
    );
    state.entries = entries;

    await state.removeSupportPerson('priya');

    expect(state.supportPeople, ['Sam']);
    expect(api.settings.supportPeople, ['Sam']);
    expect(state.entries, same(entries));
    expect(state.entries.single.person, 'Priya');
  });

  test('an unrelated settings save keeps the roster', () async {
    final (state, api) = await buildState(
      settings: const AppSettings(supportPeople: ['Priya', 'Sam']),
    );

    await state.setTheme(ThemePreference.dark);

    expect(state.settings.theme, ThemePreference.dark);
    expect(state.supportPeople, ['Priya', 'Sam']);
    expect(api.settings.supportPeople, ['Priya', 'Sam']);
  });
}
