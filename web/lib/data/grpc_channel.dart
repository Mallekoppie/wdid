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

/// Adds the signed-in account's bearer token to every RPC.
ClientInterceptor bearerInterceptor(String? Function() token) =>
    _BearerInterceptor(token);

class _BearerInterceptor extends ClientInterceptor {
  _BearerInterceptor(this._token);

  final String? Function() _token;

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    return invoker(method, request, _withToken(options));
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
