import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc_or_grpcweb.dart';

import 'package:wdid_web/data/auth_api.dart';
import 'package:wdid_web/src/generated/auth.pbgrpc.dart' as generated;

/// A standard JWT-shaped token. The signature is never verified by the client;
/// only the payload's `exp` claim is read.
String _jwt(Map<String, Object?> claims) {
  String encode(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final header = encode({'alg': 'HS256', 'typ': 'JWT'});
  final payload = encode(claims);
  return '$header.$payload.signature';
}

class FakeAuthRpc implements AuthRpc {
  generated.GetAuthConfigResponse configResponse =
      generated.GetAuthConfigResponse(
        localLogin: true,
        registrationEnabled: true,
        bootstrapRequired: false,
        mode: generated.AuthMode.AUTH_MODE_SERVER,
        oidc: generated.OIDCConfig(
          enabled: true,
          issuerUrl: 'http://zitadel.local:8080',
          clientId: 'wdid-client',
        ),
      );

  generated.LoginResponse loginResponse = generated.LoginResponse(
    user: generated.User(
      id: 'user-1',
      email: 'admin@example.com',
      displayName: 'Admin',
      role: generated.UserRole.USER_ROLE_ADMIN,
    ),
    token: 'login-token',
  );

  generated.RegisterAccountResponse registerResponse =
      generated.RegisterAccountResponse(
        user: generated.User(
          id: 'user-2',
          email: 'new@example.com',
          displayName: 'New User',
          role: generated.UserRole.USER_ROLE_USER,
        ),
        token: 'register-token',
      );

  Object? error;

  Map<String, String> lastLogin = const {};
  Map<String, String> lastRegister = const {};

  @override
  Future<generated.GetAuthConfigResponse> getAuthConfig() async {
    if (error != null) throw error!;
    return configResponse;
  }

  @override
  Future<generated.LoginResponse> login({
    String email = '',
    String username = '',
    required String password,
  }) async {
    lastLogin = {'email': email, 'username': username, 'password': password};
    if (error != null) throw error!;
    return loginResponse;
  }

  @override
  Future<generated.RegisterAccountResponse> register({
    String email = '',
    String username = '',
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  }) async {
    lastRegister = {
      'email': email,
      'username': username,
      'password': password,
      'displayName': displayName,
      'inviteCode': inviteCode,
      'bootstrapSecret': bootstrapSecret,
    };
    if (error != null) throw error!;
    return registerResponse;
  }
}

void main() {
  test('getConfig maps every capability', () async {
    final api = GrpcAuthApi(rpc: FakeAuthRpc());

    final config = await api.getConfig();

    expect(config.localLogin, isTrue);
    expect(config.registrationEnabled, isTrue);
    expect(config.bootstrapRequired, isFalse);
    expect(config.oidcEnabled, isTrue);
    expect(config.mode, AuthMode.server);
    expect(config.setupRequired, isFalse);
    expect(config.passwordRequired, isFalse);
    expect(config.username, isEmpty);
    expect(config.oidcIssuerUrl, 'http://zitadel.local:8080');
    expect(config.oidcClientId, 'wdid-client');
  });

  test('getConfig maps the local setup state', () async {
    final rpc = FakeAuthRpc()
      ..configResponse = generated.GetAuthConfigResponse(
        localLogin: true,
        mode: generated.AuthMode.AUTH_MODE_LOCAL,
        setupRequired: true,
        passwordRequired: false,
        username: 'malle',
        oidc: generated.OIDCConfig(),
      );
    final api = GrpcAuthApi(rpc: rpc);

    final config = await api.getConfig();

    expect(config.mode, AuthMode.local);
    expect(config.isLocal, isTrue);
    expect(config.setupRequired, isTrue);
    expect(config.username, 'malle');
    expect(config.passwordRequired, isFalse);
    expect(config.oidcEnabled, isFalse);
  });

  test('login sends a local username', () async {
    final rpc = FakeAuthRpc();
    final api = GrpcAuthApi(rpc: rpc);

    await api.login(username: 'malle', password: '');

    expect(rpc.lastLogin['username'], 'malle');
    expect(rpc.lastLogin['email'], '');
    expect(rpc.lastLogin['password'], '');
  });

  test('login sends credentials and returns the session', () async {
    final rpc = FakeAuthRpc();
    final api = GrpcAuthApi(rpc: rpc);

    final session = await api.login(
      email: 'admin@example.com',
      password: 'longenough1',
    );

    expect(rpc.lastLogin['email'], 'admin@example.com');
    expect(rpc.lastLogin['password'], 'longenough1');
    expect(session.user.email, 'admin@example.com');
    expect(session.user.role, 'admin');
    expect(session.token, 'login-token');
  });

  test('login records the expiry from the token exp claim', () async {
    final rpc = FakeAuthRpc()
      ..loginResponse = generated.LoginResponse(
        user: generated.User(id: 'user-1', displayName: 'Admin'),
        token: _jwt({'exp': 1700000000}),
      );
    final api = GrpcAuthApi(rpc: rpc);

    final session = await api.login(
      email: 'admin@example.com',
      password: 'longenough1',
    );

    expect(
      session.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
  });

  test('a malformed or claim-less token records no expiry', () async {
    for (final token in [
      'login-token',
      _jwt({'sub': 'user-1'}),
    ]) {
      final rpc = FakeAuthRpc()
        ..loginResponse = generated.LoginResponse(
          user: generated.User(id: 'user-1', displayName: 'Admin'),
          token: token,
        );
      final api = GrpcAuthApi(rpc: rpc);

      final session = await api.login(
        email: 'admin@example.com',
        password: 'longenough1',
      );

      expect(session.expiresAt, isNull, reason: token);
    }
  });

  test('register sends the invite or bootstrap credential', () async {
    final rpc = FakeAuthRpc();
    final api = GrpcAuthApi(rpc: rpc);

    await api.register(
      email: 'new@example.com',
      password: 'longenough1',
      displayName: 'New User',
      inviteCode: 'wdid-ABCD-EFGH-IJKL-MNOP',
    );

    expect(rpc.lastRegister['inviteCode'], 'wdid-ABCD-EFGH-IJKL-MNOP');
    expect(rpc.lastRegister['bootstrapSecret'], '');

    await api.register(
      email: 'admin@example.com',
      password: 'longenough1',
      displayName: 'Admin',
      bootstrapSecret: 'deployment-bootstrap-secret',
    );

    expect(rpc.lastRegister['bootstrapSecret'], 'deployment-bootstrap-secret');
    expect(rpc.lastRegister['inviteCode'], '');
  });

  test('server messages become AuthFailures', () async {
    final rpc = FakeAuthRpc()
      ..error = const GrpcError.custom(
        StatusCode.permissionDenied,
        'invite code has already been used',
      );
    final api = GrpcAuthApi(rpc: rpc);

    await expectLater(
      api.login(email: 'admin@example.com', password: 'longenough1'),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.message,
          'message',
          'invite code has already been used',
        ),
      ),
    );
  });

  test('unreachable service gets a helpful message', () async {
    final rpc = FakeAuthRpc()
      ..error = const GrpcError.custom(StatusCode.unavailable);
    final api = GrpcAuthApi(rpc: rpc);

    await expectLater(
      api.getConfig(),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.message,
          'message',
          contains('service is unreachable'),
        ),
      ),
    );
  });
}
