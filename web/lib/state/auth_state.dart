import 'package:flutter/foundation.dart';

import '../data/auth_api.dart';

/// Holds the sign-in configuration and the current session.
class AuthState extends ChangeNotifier {
  AuthState(this.api, {AuthSession? initialSession}) : session = initialSession;

  final AuthApi api;

  /// Invoked after [signOut] clears the session. The app wires this to drop
  /// the previous account's cached data and navigate to the login screen, so
  /// every session-ending path shares the same cleanup.
  void Function()? onSessionEnded;

  AuthConfig? config;
  AuthSession? session;
  bool loading = false;
  String? error;

  bool get signedIn => session != null;

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
  /// sign-out and, later, token expiry both call it. It is idempotent, so
  /// concurrent callers cannot end the same session twice.
  void signOut() {
    if (session == null) return;
    session = null;
    error = null;
    _notify();
    onSessionEnded?.call();
  }

  Future<bool> _submit(Future<AuthSession> Function() action) async {
    if (loading) return false;
    loading = true;
    error = null;
    _notify();
    try {
      session = await action();
      return true;
    } catch (failure) {
      error = _message(failure);
      return false;
    } finally {
      loading = false;
      _notify();
    }
  }

  String _message(Object failure) {
    if (failure is AuthFailure) return failure.message;
    return failure.toString();
  }

  void _notify() {
    notifyListeners();
  }
}
