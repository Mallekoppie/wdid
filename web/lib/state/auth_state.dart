import 'package:flutter/foundation.dart';

import '../data/auth_api.dart';

/// Holds the sign-in configuration and the current session.
class AuthState extends ChangeNotifier {
  AuthState(this.api, {AuthSession? initialSession}) : session = initialSession;

  final AuthApi api;

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

  Future<bool> login({required String email, required String password}) {
    return _submit(() => api.login(email: email, password: password));
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  }) {
    return _submit(
      () => api.register(
        email: email,
        password: password,
        displayName: displayName,
        inviteCode: inviteCode,
        bootstrapSecret: bootstrapSecret,
      ),
    );
  }

  void logout() {
    session = null;
    _notify();
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
