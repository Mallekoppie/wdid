import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';

import 'package:wdid_web/data/grpc_channel.dart';

/// A real [ResponseFuture] that fails without a network channel, so the
/// interceptor's error handling is exercised end to end.
ResponseFuture<int> _failingUnary(GrpcError error) {
  final call = ClientCall<Object, int>(
    ClientMethod<Object, int>('/test/Method', (_) => const [], (_) => 0),
    const Stream<Object>.empty(),
    CallOptions(),
  );
  call.onConnectionError(error);
  return ResponseFuture<int>(call);
}

void main() {
  test('the bearer interceptor still attaches the session token', () async {
    Map<String, String>? metadata;
    final interceptor = bearerInterceptor(() => 'token-1');

    await interceptor
        .interceptUnary<Object, int>(
          ClientMethod<Object, int>('/test/Method', (_) => const [], (_) => 0),
          Object(),
          CallOptions(),
          (method, request, options) {
            metadata = options.metadata;
            return _failingUnary(GrpcError.unauthenticated('token expired'));
          },
        )
        .catchError((_) => 0);

    expect(metadata?['authorization'], 'Bearer token-1');
  });

  test('an unauthenticated reply reports the dead session', () async {
    var reported = 0;
    final response = Future<int>.error(
      GrpcError.unauthenticated('token expired'),
    );

    watchUnauthenticatedFuture(response, () => reported++);

    await expectLater(response, throwsA(isA<GrpcError>()));
    expect(reported, 1);
  });

  test('other failures do not end the session', () async {
    var reported = 0;
    final response = Future<int>.error(GrpcError.unavailable('offline'));

    watchUnauthenticatedFuture(response, () => reported++);

    await expectLater(response, throwsA(isA<GrpcError>()));
    expect(reported, 0);
  });

  test('a successful reply never reports the session dead', () async {
    var reported = 0;

    watchUnauthenticatedFuture(Future<void>.value(), () => reported++);
    await pumpEventQueue();

    expect(reported, 0);
  });

  test('a stream reports the dead session and keeps its error', () async {
    var reported = 0;
    final stream = watchUnauthenticated<int>(
      Stream<int>.error(GrpcError.unauthenticated('token expired')),
      () => reported++,
    );

    await expectLater(stream, emitsError(isA<GrpcError>()));
    expect(reported, 1);
  });

  test('a healthy stream passes values through untouched', () async {
    var reported = 0;
    final stream = watchUnauthenticated<int>(
      Stream<int>.fromIterable(const [1, 2, 3]),
      () => reported++,
    );

    await expectLater(stream, emitsInOrder(const [1, 2, 3]));
    expect(reported, 0);
  });
}
