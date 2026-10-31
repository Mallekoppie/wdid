import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/auth_api.dart';
import 'package:wdid_web/data/grpc_channel.dart';

import 'fake_auth_api.dart';
import 'fake_preferences_api.dart';

const _expiredMessage = 'Your session expired. Sign in again.';

AuthSession _expiringSession({DateTime? at}) => AuthSession(
  user: const AuthUser(
    id: 'user-1',
    email: 'test@example.com',
    displayName: 'Test User',
    role: 'user',
  ),
  token: 'test-token',
  expiresAt: at ?? DateTime.now(),
);

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required AuthSession? session,
    String route = '/today',
    ApiSession? Function(ApiSession)? captureSession,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: session,
        initialRoute: route,
        settingsApiBuilder: (session) {
          captureSession?.call(session);
          return FakeSettingsApi();
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
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
  }

  testWidgets('an expired session redirects to login with the expiry message', (
    tester,
  ) async {
    await pumpApp(tester, session: _expiringSession());

    expect(find.byKey(const Key('session-expired')), findsOneWidget);
    expect(find.text(_expiredMessage), findsOneWidget);
    expect(find.text('Start a timer'), findsNothing);
  });

  testWidgets('signing in again after expiry lands on Today', (tester) async {
    await pumpApp(tester, session: _expiringSession(), route: '/settings');

    expect(find.byKey(const Key('session-expired')), findsOneWidget);

    await signIn(tester);

    // The interrupted route is not restored.
    expect(find.text('Start a timer'), findsOneWidget);
    expect(find.text('Data & backups'), findsNothing);
  });

  testWidgets('an unauthenticated RPC ends the session the same way', (
    tester,
  ) async {
    ApiSession? session;
    await pumpApp(
      tester,
      session: signedInSession(),
      captureSession: (value) => session = value,
    );

    expect(find.text('Start a timer'), findsOneWidget);

    // A service client reports that the server rejected the token.
    session!.onUnauthenticated!();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session-expired')), findsOneWidget);
    expect(find.text(_expiredMessage), findsOneWidget);
    expect(find.text('Start a timer'), findsNothing);
  });

  testWidgets('no expired token is attached once the session has ended', (
    tester,
  ) async {
    ApiSession? session;
    await pumpApp(
      tester,
      session: _expiringSession(),
      captureSession: (value) => session = value,
    );

    expect(find.byKey(const Key('session-expired')), findsOneWidget);
    // The shared token accessor every service client reads now yields nothing.
    expect(session!.token(), isNull);
  });

  testWidgets('sign-out shows no expiry message', (tester) async {
    await pumpApp(tester, session: signedInSession());

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session-expired')), findsNothing);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });
}
