import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/auth_api.dart';

/// Holds the sign-in configuration and the current session.
class AuthState extends ChangeNotifier {
  AuthState(this.api, {AuthSession? initialSession})
    : session = initialSession {
    _scheduleExpiry();
  }

  /// The message the login screen shows after the token expired or the service
  /// rejected it. It is separate from [error] because loading the sign-in
  /// configuration clears that, and the redirect usually happens before the
  /// login screen has its config.
  static const sessionExpiredMessage = 'Your session expired. Sign in again.';

  final AuthApi api;

  /// Invoked after the session is cleared. The app wires this to drop the
  /// previous account's cached data and navigate to the login screen, so every
  /// session-ending path shares the same cleanup.
  void Function()? onSessionEnded;

  AuthConfig? config;
  AuthSession? session;
  String? sessionNotice;
  bool loading = false;
  String? error;

  Timer? _expiryTimer;

  bool get signedIn => session != null;

  /// The bearer token service calls may attach, or null when signed out or the
  /// token's expiry has passed. Reading this lazily means a stale token is
  /// never sent even if the expiry timer is late, for example in a suspended
  /// tab.
  String? get token {
    final current = session;
    if (current == null) return null;
    final expiresAt = current.expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) return null;
    return current.token;
  }

  Future<void> loadConfig() async {
    if (loading) return;
    loading = true;
    error = null;
    _notify();
    try {
      config = await api.getConfig();
    } catch (failure) {
      error = _message(failure);
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> login({
    String email = '',
    String username = '',
    required String password,
  }) {
    return _submit(
      () => api.login(email: email, username: username, password: password),
    );
  }

  Future<bool> register({
    String email = '',
    String username = '',
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  }) {
    return _submit(
      () => api.register(
        email: email,
        username: username,
        password: password,
        displayName: displayName,
        inviteCode: inviteCode,
        bootstrapSecret: bootstrapSecret,
      ),
    );
  }

  /// Ends the current session. This is the single session-clearing seam:
  /// sign-out, token expiry, and the service rejecting the token all call it.
  /// It is idempotent, so concurrent callers cannot end the same session twice.
  void signOut() => endSession();

  /// Ends the session after the service answered an RPC with unauthenticated.
  ///
  /// [token] is the token that issued the rejected request. A late reply from a
  /// previous session carries that session's token, so it cannot end a newer
  /// one. While signed out this is a no-op, so the login screen's own "wrong
  /// password" unauthenticated reply cannot end or duplicate a session.
  void handleUnauthenticated(String? token) {
    final current = session;
    if (current == null) return;
    if (token == null || token != current.token) return;
    endSession(message: sessionExpiredMessage);
  }

  /// Clears the session and, when [message] is given, records the notice the
  /// login screen shows. The router is told through [onSessionEnded].
  void endSession({String? message}) {
    if (session == null) return;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    session = null;
    error = null;
    sessionNotice = message;
    _notify();
    onSessionEnded?.call();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final expiresAt = session?.expiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now());
    _expiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _expire,
    );
  }

  void _expire() {
    _expiryTimer = null;
    endSession(message: sessionExpiredMessage);
  }

  Future<bool> _submit(Future<AuthSession> Function() action) async {
    if (loading) return false;
    loading = true;
    error = null;
    _notify();
    try {
      session = await action();
      sessionNotice = null;
      _scheduleExpiry();
      return true;
    } catch (failure) {
      error = _message(failure);
      return false;
    } finally {
      loading = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    super.dispose();
  }

  String _message(Object failure) {
    if (failure is AuthFailure) return failure.message;
    return failure.toString();
  }

  void _notify() {
    notifyListeners();
  }
}
