import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/auth_api.dart';

import 'fake_auth_api.dart';

void main() {
  Future<void> pumpLogin(WidgetTester tester, FakeAuthApi auth) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(WdidApp(authApi: auth, initialRoute: '/login'));
    await tester.pumpAndSettle();
  }

  testWidgets('bootstrap creates the first admin account', (tester) async {
    final auth = FakeAuthApi(
      config: const AuthConfig(
        localLogin: true,
        registrationEnabled: false,
        bootstrapRequired: true,
        oidcEnabled: false,
      ),
    );
    await pumpLogin(tester, auth);

    expect(find.text('Set up the first account'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('bootstrap-name')), 'Admin');
    await tester.enterText(
      find.byKey(const Key('bootstrap-email')),
      'admin@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('bootstrap-password')),
      'longenough1',
    );
    await tester.enterText(
      find.byKey(const Key('bootstrap-secret')),
      'deployment-bootstrap-secret',
    );
    await tester.tap(find.byKey(const Key('bootstrap-submit')));
    await tester.pumpAndSettle();

    final registration = auth.registrations.single;
    expect(registration['email'], 'admin@example.com');
    expect(registration['bootstrapSecret'], 'deployment-bootstrap-secret');
    expect(registration['inviteCode'], '');
    expect(find.text('Start a timer'), findsOneWidget);
  });

  testWidgets('login reaches the app', (tester) async {
    final auth = FakeAuthApi();
    await pumpLogin(tester, auth);

    expect(find.text('Sign in'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'admin@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'longenough1',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.logins.single['email'], 'admin@example.com');
    expect(find.text('Start a timer'), findsOneWidget);
  });

  testWidgets('invite registration reaches the app', (tester) async {
    final auth = FakeAuthApi();
    await pumpLogin(tester, auth);

    await tester.enterText(find.byKey(const Key('register-name')), 'New User');
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'new@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'longenough1',
    );
    await tester.enterText(
      find.byKey(const Key('register-invite')),
      'wdid-ABCD-EFGH-IJKL-MNOP',
    );
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    final registration = auth.registrations.single;
    expect(registration['email'], 'new@example.com');
    expect(registration['inviteCode'], 'wdid-ABCD-EFGH-IJKL-MNOP');
    expect(registration['bootstrapSecret'], '');
    expect(find.text('Start a timer'), findsOneWidget);
  });

  testWidgets('local setup creates the account without an email', (
    tester,
  ) async {
    final auth = FakeAuthApi(
      config: const AuthConfig(
        localLogin: true,
        registrationEnabled: false,
        bootstrapRequired: false,
        oidcEnabled: false,
        mode: AuthMode.local,
        setupRequired: true,
      ),
    );
    await pumpLogin(tester, auth);

    expect(find.text('Set up wdid'), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-secret')), findsNothing);
    expect(find.text('Continue with Zitadel'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('local-setup-username')),
      'malle',
    );
    await tester.tap(find.byKey(const Key('local-setup-submit')));
    await tester.pumpAndSettle();

    final registration = auth.registrations.single;
    expect(registration['username'], 'malle');
    expect(registration['email'], '');
    expect(registration['password'], '');
    expect(registration['bootstrapSecret'], '');
    expect(registration['inviteCode'], '');
    expect(find.text('Start a timer'), findsOneWidget);
  });

  testWidgets('a passwordless local account signs in automatically', (
    tester,
  ) async {
    final auth = FakeAuthApi(
      config: const AuthConfig(
        localLogin: true,
        registrationEnabled: false,
        bootstrapRequired: false,
        oidcEnabled: false,
        mode: AuthMode.local,
        username: 'malle',
      ),
    );
    await pumpLogin(tester, auth);

    expect(auth.logins.single['username'], 'malle');
    expect(auth.logins.single['password'], '');
    expect(find.byKey(const Key('local-login-password')), findsNothing);
    expect(find.text('Start a timer'), findsOneWidget);
  });

  testWidgets('a password-protected local account prefills the username', (
    tester,
  ) async {
    final auth = FakeAuthApi(
      config: const AuthConfig(
        localLogin: true,
        registrationEnabled: false,
        bootstrapRequired: false,
        oidcEnabled: false,
        mode: AuthMode.local,
        passwordRequired: true,
        username: 'malle',
      ),
    );
    await pumpLogin(tester, auth);

    expect(auth.logins, isEmpty);
    final usernameField = tester.widget<TextField>(
      find.byKey(const Key('local-login-username')),
    );
    expect(usernameField.controller!.text, 'malle');

    await tester.enterText(
      find.byKey(const Key('local-login-password')),
      'longenough1',
    );
    await tester.tap(find.byKey(const Key('local-login-submit')));
    await tester.pumpAndSettle();

    expect(auth.logins.single['username'], 'malle');
    expect(auth.logins.single['password'], 'longenough1');
    expect(find.text('Start a timer'), findsOneWidget);
  });

  testWidgets('service failures are shown on the form', (tester) async {
    final auth = FakeAuthApi()
      ..failure = const AuthFailure('invite code has already been used');
    await pumpLogin(tester, auth);

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'admin@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'longenough1',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-error')), findsOneWidget);
    expect(find.text('invite code has already been used'), findsOneWidget);
    expect(find.text('Start a timer'), findsNothing);
  });
}
