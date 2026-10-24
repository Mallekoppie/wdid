import 'package:grpc/grpc_or_grpcweb.dart';

import '../src/generated/auth.pbgrpc.dart' as generated;
import 'grpc_channel.dart';

/// Login capabilities reported by the service before anyone signs in.
class AuthConfig {
  const AuthConfig({
    required this.localLogin,
    required this.registrationEnabled,
    required this.bootstrapRequired,
    required this.oidcEnabled,
    this.oidcIssuerUrl = '',
    this.oidcClientId = '',
  });

  final bool localLogin;
  final bool registrationEnabled;
  final bool bootstrapRequired;
  final bool oidcEnabled;
  final String oidcIssuerUrl;
  final String oidcClientId;
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
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
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

  Future<AuthSession> login({required String email, required String password});

  Future<AuthSession> register({
    required String email,
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
    required String email,
    required String password,
  });

  Future<generated.RegisterAccountResponse> register({
    required String email,
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
    required String email,
    required String password,
  }) {
    return _client.login(
      generated.LoginRequest(email: email, password: password),
    );
  }

  @override
  Future<generated.RegisterAccountResponse> register({
    required String email,
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
        oidcIssuerUrl: oidc.issuerUrl,
        oidcClientId: oidc.clientId,
      );
    } on GrpcError catch (error) {
      throw AuthFailure(_message(error));
    }
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _rpc.login(email: email, password: password);
      return _session(response.user, response.token);
    } on GrpcError catch (error) {
      throw AuthFailure(_message(error));
    }
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  }) async {
    try {
      final response = await _rpc.register(
        email: email,
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
