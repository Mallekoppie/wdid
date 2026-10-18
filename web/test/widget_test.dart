import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/demo_repository.dart';

void main() {
  testWidgets('renders Today and navigates to Log', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        repository: DemoWdidRepository(latency: Duration.zero),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Start a timer'), findsOneWidget);
    expect(find.text('Billing migration'), findsWidgets);

    await tester.tap(find.text('Log').first);
    await tester.pumpAndSettle();

    expect(find.text('Export period'), findsOneWidget);
    expect(find.text('Week by attribution'), findsNothing);
  });
}
