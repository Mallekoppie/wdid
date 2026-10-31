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
  const ApiSession({required this.tokenProvider, this.onUnauthenticated});

  /// Reads the bearer token for the current request. It is a provider because
  /// the token can expire or be replaced between requests.
  final String? Function() tokenProvider;

  /// Called with the token that issued a request the service answered with
  /// unauthenticated. A caller compares it with the current session's token so
  /// a late reply from a previous session cannot end a newer one.
  final void Function(String? token)? onUnauthenticated;
}

/// The interceptor list every service-backed client shares: it attaches the
/// session's bearer token and reports an unauthenticated reply with the token
/// that issued that request.
List<ClientInterceptor> sessionInterceptors(ApiSession? session) => [
  bearerInterceptor(
    session?.tokenProvider ?? (() => null),
    onUnauthenticated: session?.onUnauthenticated,
  ),
];

/// Whether [error] means the service rejected the bearer token.
bool isUnauthenticated(Object error) =>
    error is GrpcError && error.code == StatusCode.unauthenticated;

/// Reports an unauthenticated failure of [response], made with [token], through
/// [onUnauthenticated]. The response's own error handling is left untouched.
void watchUnauthenticatedFuture(
  Future<Object?> response,
  String? token,
  void Function(String? token)? onUnauthenticated,
) {
  if (onUnauthenticated == null) return;
  response.then<void>(
    (_) {},
    onError: (Object error, StackTrace _) {
      if (isUnauthenticated(error)) onUnauthenticated(token);
    },
  );
}

/// Adds the signed-in account's bearer token to every RPC and reports an
/// unauthenticated unary reply through [onUnauthenticated].
ClientInterceptor bearerInterceptor(
  String? Function() tokenProvider, {
  void Function(String? token)? onUnauthenticated,
}) => _BearerInterceptor(tokenProvider, onUnauthenticated);

/// Reports an unauthenticated stream error, made with [token], through
/// [onUnauthenticated] and passes the error on to the caller.
///
/// A [ResponseStream] cannot be listened to twice, so streaming clients wrap
/// their response with this instead of the interceptor watching it.
Stream<T> watchUnauthenticated<T>(
  Stream<T> stream,
  String? token,
  void Function(String? token)? onUnauthenticated,
) {
  if (onUnauthenticated == null) return stream;
  return stream.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stackTrace, sink) {
        if (isUnauthenticated(error)) onUnauthenticated(token);
        sink.addError(error, stackTrace);
      },
    ),
  );
}

class _BearerInterceptor extends ClientInterceptor {
  _BearerInterceptor(this._tokenProvider, this._onUnauthenticated);

  final String? Function() _tokenProvider;
  final void Function(String? token)? _onUnauthenticated;

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    // Capture the token before the call so a late unauthenticated reply is
    // attributed to the session that issued it, not whichever session is live
    // when the reply arrives.
    final token = _token();
    final response = invoker(method, request, _withToken(options, token));
    watchUnauthenticatedFuture(response, token, _onUnauthenticated);
    return response;
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) {
    return invoker(method, requests, _withToken(options, _token()));
  }

  String? _token() {
    final value = _tokenProvider()?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  CallOptions _withToken(CallOptions options, String? token) {
    if (token == null) return options;
    return options.mergedWith(
      CallOptions(metadata: {'authorization': 'Bearer $token'}),
    );
  }
}
