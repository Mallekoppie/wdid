import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/timer_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/utils/time_utils.dart';

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
}
