import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/demo_repository.dart';

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
        repository: DemoWdidRepository(latency: Duration.zero),
        initialRoute: route,
      ),
    );
    await tester.pumpAndSettle();
  }

  final cases = <String, String>{
    '/today': 'Start a timer',
    '/log': 'Export period',
    '/initiatives': 'New initiative',
    '/initiatives/init-billing': 'Billing migration',
    '/support': 'Log support',
    '/checkins': 'Create check-in',
    '/checkins/checkin-generated': 'Summary',
    '/settings': 'Data',
    '/login': 'Continue with Zitadel',
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key} renders without exceptions', (tester) async {
      await pumpRoute(tester, entry.key);
      expect(find.text(entry.value), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Today renders at a tablet width', (tester) async {
    await pumpRoute(
      tester,
      '/today',
      size: const Size(820, 760),
    );
    expect(find.text('Start a timer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
