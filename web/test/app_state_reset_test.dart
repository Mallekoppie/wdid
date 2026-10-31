import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/check_in.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/utils/time_utils.dart';

import 'fake_checkin_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';

Category _category(String id, String name) => Category(
  id: id,
  name: name,
  role: CategoryRole.initiative,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

Subcategory _project(String id, String categoryId, String name) => Subcategory(
  id: id,
  categoryId: categoryId,
  name: name,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

WorkEntry _todayEntry() {
  final started = DateTime.now().subtract(const Duration(minutes: 30));
  return WorkEntry(
    id: 'entry-1',
    categoryId: 'cat-1',
    subcategoryId: 'sub-1',
    description: 'Old account work',
    outcome: '',
    people: const [],
    startedAt: started.toUtc(),
    endedAt: started.add(const Duration(minutes: 30)).toUtc(),
    minutes: 30,
    localDate: isoDate(started),
    createdAt: started.toUtc(),
    updatedAt: started.toUtc(),
  );
}

CheckIn _checkIn() => CheckIn(
  id: 'checkin-1',
  kind: CheckInKind.manager,
  state: CheckInState.draft,
  audience: CheckInAudience.oneOnOne,
  focusNotes: 'Old account focus',
  periodStart: DateTime(2026, 10, 1),
  periodEnd: DateTime(2026, 10, 23),
  createdAt: DateTime.utc(2026, 10, 23, 12),
  totals: const CheckInTotals(minutes: 90),
);

void main() {
  test(
    'reset drops cached account data and a stale load cannot refill it',
    () async {
      final categoryApi = FakeCategoryApi(
        categories: [_category('cat-1', 'Initiatives')],
        subcategories: [_project('sub-1', 'cat-1', 'Billing migration')],
      );
      final settingsApi = FakeSettingsApi(
        settings: const AppSettings(defaultDurationMinutes: 45),
      );
      final entryApi = FakeEntryApi(entries: [_todayEntry()]);
      final checkInApi = FakeCheckInApi(checkIns: [_checkIn()]);

      final state = AppState(
        categoryApi: categoryApi,
        settingsApi: settingsApi,
        entryApi: entryApi,
        checkInApi: checkInApi,
      );
      addTearDown(state.dispose);

      await state.load();
      await pumpEventQueue();

      expect(state.categories, isNotEmpty);
      expect(state.subcategories, isNotEmpty);
      expect(state.settings.defaultDurationMinutes, 45);
      expect(state.entries, isNotEmpty);
      expect(state.checkIns, isNotEmpty);

      // Start a taxonomy read for the old account, then sign out while it is
      // still in flight.
      final gate = Completer<void>();
      categoryApi.gate = gate;
      final stale = state.loadTaxonomy();

      state.reset();

      expect(state.categories, isEmpty);
      expect(state.subcategories, isEmpty);
      expect(state.settings.defaultDurationMinutes, 30);
      expect(state.entries, isEmpty);
      expect(state.checkIns, isEmpty);

      // The old account's late response must not repopulate the new session.
      gate.complete();
      await stale;
      await pumpEventQueue();

      expect(state.categories, isEmpty);
      expect(state.subcategories, isEmpty);
      expect(state.taxonomyLoading, isFalse);
    },
  );
}
