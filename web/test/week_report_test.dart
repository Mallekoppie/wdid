import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/demo_repository.dart';
import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/widgets/allocation_bars.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';
import 'fake_summary_api.dart';

Category category(String id, String name, CategoryRole role) => Category(
  id: id,
  name: name,
  role: role,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

void main() {
  Future<FakeSummaryApi> pumpToday(
    WidgetTester tester, {
    required FakeSummaryApi summaryApi,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1400, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        repository: DemoWdidRepository(latency: Duration.zero),
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/today',
        categoryApiBuilder: (_) => FakeCategoryApi(
          categories: [
            category('cat-projects', 'Projects', CategoryRole.initiative),
            category('cat-meetings', 'Meetings', CategoryRole.other),
          ],
        ),
        settingsApiBuilder: (_) =>
            FakeSettingsApi(settings: const AppSettings()),
        entryApiBuilder: (_) => FakeEntryApi(),
        summaryApiBuilder: (_) => summaryApi,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var index = 0; index < 6; index++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }
    return summaryApi;
  }

  testWidgets('week bars and the weekly total come from the period report', (
    tester,
  ) async {
    final summaryApi = await pumpToday(tester, summaryApi: FakeSummaryApi());

    // The server resolves the week; the client does not trust its own clock.
    expect(summaryApi.lastCurrentWeek, isTrue);
    expect(summaryApi.lastFrom, isEmpty);
    expect(summaryApi.lastTo, isEmpty);

    // The report owns the totals: there are no entries for the fixture to sum.
    expect(find.text('1h 30m this week'), findsOneWidget);
    expect(find.text('Week by category'), findsOneWidget);

    final bars = find.byType(AllocationBars);
    expect(
      find.descendant(of: bars, matching: find.text('Initiatives')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bars, matching: find.text('Support')),
      findsOneWidget,
    );

    // The category's subcategories are its hover breakdown.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('Billing migration · 1h') == true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('an empty report renders zero totals and the empty state', (
    tester,
  ) async {
    await pumpToday(
      tester,
      summaryApi: FakeSummaryApi(
        report: const PeriodReport(
          fromDate: '2026-10-19',
          toDate: '2026-10-25',
        ),
      ),
    );

    expect(find.text('0m this week'), findsOneWidget);
    expect(find.text('No time logged in this period.'), findsOneWidget);
  });

  testWidgets('a failed report shows an error with a working retry', (
    tester,
  ) async {
    final summaryApi = FakeSummaryApi()
      ..failure = const SummaryFailure(
        'The service is unreachable. Check that the server is running.',
      );
    await pumpToday(tester, summaryApi: summaryApi);

    expect(find.text('Could not load this week'), findsOneWidget);
    expect(find.textContaining('unreachable'), findsOneWidget);

    summaryApi.failure = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load this week'), findsNothing);
    expect(find.text('1h 30m this week'), findsOneWidget);
    expect(summaryApi.calls, greaterThanOrEqualTo(2));
  });

  testWidgets('a slow report shows a loading state', (tester) async {
    final gate = Completer<PeriodReport>();
    final summaryApi = FakeSummaryApi()..gate = gate;
    await pumpToday(tester, summaryApi: summaryApi, settle: false);

    expect(find.text('Loading this week…'), findsWidgets);

    gate.complete(summaryApi.report);
    await tester.pumpAndSettle();

    expect(find.text('Loading this week…'), findsNothing);
    expect(find.text('1h 30m this week'), findsOneWidget);
  });
}
