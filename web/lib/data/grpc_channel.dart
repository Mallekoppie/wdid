import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';

/// Opens the shared gRPC-Web channel, same-origin unless the dev server points
/// `WDID_API_BASE_URL` elsewhere.
GrpcOrGrpcWebClientChannel openAppChannel() {
  const configured = String.fromEnvironment('WDID_API_BASE_URL');
  final base = configured.isEmpty ? Uri.base : Uri.parse(configured);
  final port = base.hasPort ? base.port : (base.scheme == 'https' ? 443 : 80);

  return GrpcOrGrpcWebClientChannel.toSingleEndpoint(
    host: base.host,
    port: port,
    transportSecure: base.scheme == 'https',
  );
}

/// The session a service-backed client works with: the bearer token to attach
/// to every RPC and the callback that ends the session when the service
/// rejects that token.
///
/// Keeping both on one object gives every client, and the fakes tests swap in,
/// the same session-ending seam.
class ApiSession {
  const ApiSession({required this.token, this.onUnauthenticated});

  final String? Function() token;
  final void Function()? onUnauthenticated;
}

/// Whether [error] means the service rejected the bearer token.
bool isUnauthenticated(Object error) =>
    error is GrpcError && error.code == StatusCode.unauthenticated;

/// Reports an unauthenticated failure of [response] through
/// [onUnauthenticated], leaving the response's own error handling untouched.
void watchUnauthenticatedFuture(
  Future<Object?> response,
  void Function()? onUnauthenticated,
) {
  if (onUnauthenticated == null) return;
  response.then<void>(
    (_) {},
    onError: (Object error, StackTrace _) {
      if (isUnauthenticated(error)) onUnauthenticated();
    },
  );
}

/// Adds the signed-in account's bearer token to every RPC and reports an
/// unauthenticated unary reply through [onUnauthenticated].
ClientInterceptor bearerInterceptor(
  String? Function() token, {
  void Function()? onUnauthenticated,
}) => _BearerInterceptor(token, onUnauthenticated);

/// Reports an unauthenticated stream error through [onUnauthenticated] and
/// passes the error on to the caller.
///
/// A [ResponseStream] cannot be listened to twice, so streaming clients wrap
/// their response with this instead of the interceptor watching it.
Stream<T> watchUnauthenticated<T>(
  Stream<T> stream,
  void Function()? onUnauthenticated,
) {
  if (onUnauthenticated == null) return stream;
  return stream.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stackTrace, sink) {
        if (isUnauthenticated(error)) onUnauthenticated();
        sink.addError(error, stackTrace);
      },
    ),
  );
}

class _BearerInterceptor extends ClientInterceptor {
  _BearerInterceptor(this._token, this._onUnauthenticated);

  final String? Function() _token;
  final void Function()? _onUnauthenticated;

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    final response = invoker(method, request, _withToken(options));
    watchUnauthenticatedFuture(response, _onUnauthenticated);
    return response;
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) {
    return invoker(method, requests, _withToken(options));
  }

  CallOptions _withToken(CallOptions options) {
    final value = _token()?.trim() ?? '';
    if (value.isEmpty) return options;
    return options.mergedWith(
      CallOptions(metadata: {'authorization': 'Bearer $value'}),
    );
  }
}
