import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/data/auth_api.dart';
import 'package:wdid_web/state/auth_state.dart';

import 'fake_auth_api.dart';

AuthSession _session({DateTime? expiresAt}) => AuthSession(
  user: const AuthUser(
    id: 'user-1',
    email: 'test@example.com',
    displayName: 'Test User',
    role: 'user',
  ),
  token: 'token',
  expiresAt: expiresAt,
);

void main() {
  test(
    'the session ends and shows the notice when the token expiry passes',
    () {
      fakeAsync((async) {
        var ended = 0;
        final auth = AuthState(
          FakeAuthApi(),
          initialSession: _session(
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          ),
        );
        addTearDown(auth.dispose);
        auth.onSessionEnded = () => ended++;

        expect(auth.signedIn, isTrue);
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(auth.signedIn, isTrue);

        async.elapse(const Duration(seconds: 2));

        expect(auth.session, isNull);
        expect(auth.sessionNotice, 'Your session expired. Sign in again.');
        expect(ended, 1);
      });
    },
  );

  test('a token with no known expiry does not end the session', () {
    fakeAsync((async) {
      var ended = 0;
      final auth = AuthState(FakeAuthApi(), initialSession: _session());
      addTearDown(auth.dispose);
      auth.onSessionEnded = () => ended++;

      async.elapse(const Duration(days: 1));

      expect(auth.signedIn, isTrue);
      expect(ended, 0);
    });
  });

  test('an unauthenticated RPC ends the same session once', () {
    var ended = 0;
    final auth = AuthState(FakeAuthApi(), initialSession: _session());
    addTearDown(auth.dispose);
    auth.onSessionEnded = () => ended++;

    auth.handleUnauthenticated();
    auth.handleUnauthenticated();

    expect(auth.session, isNull);
    expect(auth.sessionNotice, 'Your session expired. Sign in again.');
    expect(ended, 1);
  });

  test('an unauthenticated reply while signed out is ignored', () {
    var ended = 0;
    final auth = AuthState(FakeAuthApi());
    addTearDown(auth.dispose);
    auth.onSessionEnded = () => ended++;

    // A wrong password on the login screen is unauthenticated too.
    auth.handleUnauthenticated();

    expect(auth.sessionNotice, isNull);
    expect(ended, 0);
  });

  test('signing out clears the session without the expiry notice', () {
    var ended = 0;
    final auth = AuthState(FakeAuthApi(), initialSession: _session());
    addTearDown(auth.dispose);
    auth.onSessionEnded = () => ended++;
    auth.sessionNotice = AuthState.sessionExpiredMessage;

    auth.signOut();

    expect(auth.session, isNull);
    expect(auth.sessionNotice, isNull);
    expect(ended, 1);
  });

  test('no token is handed out after its expiry', () {
    final auth = AuthState(
      FakeAuthApi(),
      initialSession: _session(
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
    );
    addTearDown(auth.dispose);

    expect(auth.token, isNull);
  });

  test('a live token is handed out until it expires', () {
    final auth = AuthState(
      FakeAuthApi(),
      initialSession: _session(
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );
    addTearDown(auth.dispose);

    expect(auth.token, 'token');
  });

  test(
    'signing in again clears the expiry notice and schedules the new token',
    () {
      fakeAsync((async) {
        var ended = 0;
        final auth = AuthState(FakeAuthApi());
        addTearDown(auth.dispose);
        auth.onSessionEnded = () => ended++;
        auth.sessionNotice = AuthState.sessionExpiredMessage;

        auth.login(email: 'test@example.com', password: 'password1');
        async.flushMicrotasks();

        expect(auth.signedIn, isTrue);
        expect(auth.sessionNotice, isNull);
        expect(ended, 0);
      });
    },
  );
}
