import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc_or_grpcweb.dart';

import 'package:wdid_web/data/auth_api.dart';
import 'package:wdid_web/src/generated/auth.pbgrpc.dart' as generated;

class FakeAuthRpc implements AuthRpc {
  generated.GetAuthConfigResponse configResponse =
      generated.GetAuthConfigResponse(
        localLogin: true,
        registrationEnabled: true,
        bootstrapRequired: false,
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
    required String email,
    required String password,
  }) async {
    lastLogin = {'email': email, 'password': password};
    if (error != null) throw error!;
    return loginResponse;
  }

  @override
  Future<generated.RegisterAccountResponse> register({
    required String email,
    required String password,
    required String displayName,
    String inviteCode = '',
    String bootstrapSecret = '',
  }) async {
    lastRegister = {
      'email': email,
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
    expect(config.oidcIssuerUrl, 'http://zitadel.local:8080');
    expect(config.oidcClientId, 'wdid-client');
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
