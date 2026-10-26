import 'package:grpc/grpc_or_grpcweb.dart';

import '../src/generated/auth.pbgrpc.dart' as generated;
import 'grpc_channel.dart';

/// The account model the service enforces.
enum AuthMode {
  /// A single-user local install: username, optional password, no invites and
  /// no OIDC.
  local,

  /// The multi-user deployment: bootstrap admin, email/password and invites.
  server;

  static AuthMode fromProto(generated.AuthMode mode) {
    return mode == generated.AuthMode.AUTH_MODE_LOCAL
        ? AuthMode.local
        : AuthMode.server;
  }
}

/// Login capabilities reported by the service before anyone signs in.
class AuthConfig {
  const AuthConfig({
    required this.localLogin,
    required this.registrationEnabled,
    required this.bootstrapRequired,
    required this.oidcEnabled,
    this.mode = AuthMode.server,
    this.setupRequired = false,
    this.passwordRequired = false,
    this.username = '',
    this.oidcIssuerUrl = '',
    this.oidcClientId = '',
  });

  final bool localLogin;
  final bool registrationEnabled;
  final bool bootstrapRequired;
  final bool oidcEnabled;
  final AuthMode mode;

  /// Local mode has no account yet, so the first-run setup form is shown.
  final bool setupRequired;

  /// The existing local account has a password and prompts for it.
  final bool passwordRequired;

  /// The existing local account's username, prefilled on later launches.
  final String username;

  final String oidcIssuerUrl;
  final String oidcClientId;

  bool get isLocal => mode == AuthMode.local;
}

/// The signed-in account and its bearer token.
class AuthSession {
  const AuthSession({required this.user, required this.token});

  final AuthUser user;
  final String token;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.username = '',
  });

  final String id;

  /// Empty for a local single-user account.
  final String email;

  final String displayName;
  final String role;

  /// Empty for a server account.
  final String username;
}

/// A user-facing authentication failure.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The auth operations the login screen needs.
abstract class AuthApi {
  Future<AuthConfig> getConfig();

  /// Signs in a server account by email or a local account by username.
  Future<AuthSession> login({
    String email = '',
    String username = '',
    required String password,
  });

  /// Creates a server account (email + invite/bootstrap) or the single local
  /// account (username + optional password).
  Future<AuthSession> register({
    String email = '',
    String username = '',
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  });
}

/// The narrow generated-client surface, separated so the adapter's field
/// mapping and error translation can be tested without a network channel.
abstract class AuthRpc {
  Future<generated.GetAuthConfigResponse> getAuthConfig();

  Future<generated.LoginResponse> login({
    String email = '',
    String username = '',
    required String password,
  });

  Future<generated.RegisterAccountResponse> register({
    String email = '',
    String username = '',
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  });
}

/// The generated Connect client over gRPC-Web, sharing the app's origin by
/// default.
class GrpcAuthRpc implements AuthRpc {
  GrpcAuthRpc({generated.AuthServiceClient? client})
    : _client = client ?? generated.AuthServiceClient(openAppChannel());

  final generated.AuthServiceClient _client;

  @override
  Future<generated.GetAuthConfigResponse> getAuthConfig() {
    return _client.getAuthConfig(generated.GetAuthConfigRequest());
  }

  @override
  Future<generated.LoginResponse> login({
    String email = '',
    String username = '',
    required String password,
  }) {
    return _client.login(
      generated.LoginRequest(
        email: email,
        password: password,
        username: username,
      ),
    );
  }

  @override
  Future<generated.RegisterAccountResponse> register({
    String email = '',
    String username = '',
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  }) {
    return _client.registerAccount(
      generated.RegisterAccountRequest(
        email: email,
        password: password,
        displayName: displayName,
        inviteCode: inviteCode,
        bootstrapSecret: bootstrapSecret,
        username: username,
      ),
    );
  }
}

/// Auth over Connect/gRPC-Web.
class GrpcAuthApi implements AuthApi {
  GrpcAuthApi({AuthRpc? rpc}) : _rpc = rpc ?? GrpcAuthRpc();

  final AuthRpc _rpc;

  @override
  Future<AuthConfig> getConfig() async {
    try {
      final response = await _rpc.getAuthConfig();
      final oidc = response.oidc;
      return AuthConfig(
        localLogin: response.localLogin,
        registrationEnabled: response.registrationEnabled,
        bootstrapRequired: response.bootstrapRequired,
        oidcEnabled: oidc.enabled,
        mode: AuthMode.fromProto(response.mode),
        setupRequired: response.setupRequired,
        passwordRequired: response.passwordRequired,
        username: response.username,
        oidcIssuerUrl: oidc.issuerUrl,
        oidcClientId: oidc.clientId,
      );
    } on GrpcError catch (error) {
      throw AuthFailure(_message(error));
    }
  }

  @override
  Future<AuthSession> login({
    String email = '',
    String username = '',
    required String password,
  }) async {
    try {
      final response = await _rpc.login(
        email: email,
        username: username,
        password: password,
      );
      return _session(response.user, response.token);
    } on GrpcError catch (error) {
      throw AuthFailure(_message(error));
    }
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
    try {
      final response = await _rpc.register(
        email: email,
        username: username,
        password: password,
        displayName: displayName,
        inviteCode: inviteCode,
        bootstrapSecret: bootstrapSecret,
      );
      return _session(response.user, response.token);
    } on GrpcError catch (error) {
      throw AuthFailure(_message(error));
    }
  }

  AuthSession _session(generated.User user, String token) {
    return AuthSession(
      user: AuthUser(
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        username: user.username,
        role: user.role == generated.UserRole.USER_ROLE_ADMIN
            ? 'admin'
            : 'user',
      ),
      token: token,
    );
  }

  String _message(GrpcError error) {
    final message = error.message?.trim() ?? '';
    switch (error.code) {
      case StatusCode.unavailable:
        return 'The service is unreachable. Check that the server is running.';
      case StatusCode.unauthenticated:
        return message.isEmpty ? 'Invalid email or password.' : message;
      case StatusCode.permissionDenied:
        return message.isEmpty ? 'That code or secret is not valid.' : message;
      case StatusCode.invalidArgument:
        return message.isEmpty ? 'Check the form and try again.' : message;
      case StatusCode.alreadyExists:
        return message.isEmpty
            ? 'An account already uses this email address.'
            : message;
      case StatusCode.failedPrecondition:
        return message.isEmpty ? 'This workspace is already set up.' : message;
      default:
        return message.isEmpty ? 'The request failed.' : message;
    }
  }
}
