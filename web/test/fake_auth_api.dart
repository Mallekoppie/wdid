import 'package:wdid_web/data/auth_api.dart';

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
    required String email,
    required String password,
  }) async {
    logins.add({'email': email, 'password': password});
    return _session(email);
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  }) async {
    registrations.add({
      'email': email,
      'password': password,
      'displayName': displayName,
      'inviteCode': inviteCode,
      'bootstrapSecret': bootstrapSecret,
    });
    return _session(email);
  }

  AuthSession _session(String email) {
    if (failure != null) throw failure!;
    return AuthSession(
      user: AuthUser(
        id: 'user-1',
        email: email,
        displayName: 'Test User',
        role: 'user',
      ),
      token: 'test-token',
    );
  }
}
