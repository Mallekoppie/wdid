import 'package:wdid_web/data/auth_api.dart';

/// A signed-in session for tests that exercise the app behind the auth gate.
AuthSession signedInSession({String role = 'user'}) => AuthSession(
  user: AuthUser(
    id: 'user-1',
    email: 'test@example.com',
    displayName: 'Test User',
    role: role,
  ),
  token: 'test-token',
);

const defaultAuthConfig = AuthConfig(
  localLogin: true,
  registrationEnabled: true,
  bootstrapRequired: false,
  oidcEnabled: false,
);

class FakeAuthApi implements AuthApi {
  FakeAuthApi({this.config = defaultAuthConfig, this.failure});

  AuthConfig config;
  AuthFailure? failure;
  bool configFails = false;

  int configCalls = 0;
  final List<Map<String, String>> logins = [];
  final List<Map<String, String>> registrations = [];

  @override
  Future<AuthConfig> getConfig() async {
    configCalls++;
    if (configFails) throw const AuthFailure('service unavailable');
    return config;
  }

  @override
  Future<AuthSession> login({
    String email = '',
    String username = '',
    required String password,
  }) async {
    logins.add({'email': email, 'username': username, 'password': password});
    return _session(email: email, username: username);
  }

  @override
  Future<AuthSession> register({
    String email = '',
    String username = '',
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  }) async {
    registrations.add({
      'email': email,
      'username': username,
      'password': password,
      'displayName': displayName,
      'inviteCode': inviteCode,
      'bootstrapSecret': bootstrapSecret,
    });
    return _session(email: email, username: username);
  }

  AuthSession _session({String email = '', String username = ''}) {
    if (failure != null) throw failure!;
    return AuthSession(
      user: AuthUser(
        id: 'user-1',
        email: email,
        username: username,
        displayName: 'Test User',
        role: 'user',
      ),
      token: 'test-token',
    );
  }
}
