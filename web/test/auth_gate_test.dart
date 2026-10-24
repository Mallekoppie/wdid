import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/auth_api.dart';
import 'package:wdid_web/data/demo_repository.dart';

import 'fake_auth_api.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    String? route,
    AuthSession? session,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        repository: DemoWdidRepository(latency: Duration.zero),
        authApi: FakeAuthApi(),
        initialSession: session,
        initialRoute: route,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an unauthenticated visit lands on the login screen', (
    tester,
  ) async {
    await pumpApp(tester, route: '/today');

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Start a timer'), findsNothing);
  });

  testWidgets('an unauthenticated deep link lands on the login screen', (
    tester,
  ) async {
    await pumpApp(tester, route: '/settings');

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Data & backups'), findsNothing);
  });

  testWidgets('signing in opens Today', (tester) async {
    await pumpApp(tester, route: '/today');

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'test@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'password1',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Start a timer'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('a signed-in session skips the login screen', (tester) async {
    await pumpApp(tester, route: '/today', session: signedInSession());

    expect(find.text('Start a timer'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('a signed-in visit to /login redirects to Today', (tester) async {
    await pumpApp(tester, route: '/login', session: signedInSession());

    expect(find.text('Start a timer'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });
}
