import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/models/check_in.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/models/taxonomy.dart';

import 'fake_auth_api.dart';
import 'fake_checkin_api.dart';
import 'fake_entry_api.dart';
import 'fake_milestone_api.dart';
import 'fake_note_api.dart';
import 'fake_preferences_api.dart';
import 'fake_summary_api.dart';

Category _category(
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

Subcategory _project(String id, String categoryId, String name) => Subcategory(
  id: id,
  categoryId: categoryId,
  name: name,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

CheckIn _checkIn() => CheckIn(
  id: 'checkin-1',
  kind: CheckInKind.manager,
  state: CheckInState.draft,
  audience: CheckInAudience.oneOnOne,
  focusNotes: 'Smoke focus',
  periodStart: DateTime(2026, 10, 1),
  periodEnd: DateTime(2026, 10, 23),
  createdAt: DateTime.utc(2026, 10, 23, 12),
  totals: const CheckInTotals(minutes: 90),
);

void main() {
  Future<void> pumpRoute(
    WidgetTester tester,
    String route, {
    Size size = const Size(1440, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: route == '/login' ? null : signedInSession(),
        initialRoute: route,
        categoryApiBuilder: (_) => FakeCategoryApi(
          categories: [
            _category('cat-init', 'Initiatives'),
            _category('cat-support', 'Support', role: CategoryRole.support),
          ],
          subcategories: [
            _project('sub-1', 'cat-init', 'Billing migration'),
            _project('sub-support', 'cat-support', 'Unblock'),
          ],
        ),
        settingsApiBuilder: (_) => FakeSettingsApi(),
        entryApiBuilder: (_) => FakeEntryApi(),
        summaryApiBuilder: (_) => FakeSummaryApi(),
        noteApiBuilder: (_) => FakeNoteApi(),
        milestoneApiBuilder: (_) => FakeMilestoneApi(),
        checkInApiBuilder: (_) => FakeCheckInApi(checkIns: [_checkIn()]),
      ),
    );
    await tester.pumpAndSettle();
  }

  final cases = <String, String>{
    '/today': 'Start a timer',
    '/log': 'Add entry',
    '/initiatives': 'New project',
    '/initiatives/sub-1': 'Billing migration',
    '/support': 'Log support',
    '/checkins': 'Create check-in',
    '/checkins/checkin-1': 'Summary',
    '/settings': 'Data & backups',
    '/login': 'Sign in',
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key} renders without exceptions', (tester) async {
      await pumpRoute(tester, entry.key);
      expect(find.text(entry.value), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Today renders at a tablet width', (tester) async {
    await pumpRoute(tester, '/today', size: const Size(820, 760));
    expect(find.text('Start a timer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
