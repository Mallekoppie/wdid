import 'package:grpc/grpc_or_grpcweb.dart';

/// A user-facing service failure, optionally naming the rejected field.
class ServiceFailure implements Exception {
  const ServiceFailure(this.message, {this.field});

  final String message;
  final String? field;

  @override
  String toString() => message;
}

/// The message and field a Connect error should surface.
class GrpcFailureText {
  const GrpcFailureText(this.message, {this.field});

  final String message;
  final String? field;
}

/// Translates a Connect error into user-facing text, keeping field errors
/// visible. Callers choose the wording for their own domain.
GrpcFailureText describeGrpcError(
  GrpcError error, {
  required String unavailable,
  required String unauthenticated,
  String? notFound,
  String? failedPrecondition,
}) {
  final raw = error.message?.trim() ?? '';
  final field = fieldFromMessage(raw);
  final message = messageWithoutCode(raw);

  switch (error.code) {
    case StatusCode.unavailable:
      return GrpcFailureText(unavailable);
    case StatusCode.unauthenticated:
      return GrpcFailureText(message.isEmpty ? unauthenticated : message);
    case StatusCode.failedPrecondition:
      if (failedPrecondition == null) break;
      return GrpcFailureText(message.isEmpty ? failedPrecondition : message);
    case StatusCode.notFound:
      if (notFound == null) break;
      return GrpcFailureText(message.isEmpty ? notFound : message);
    case StatusCode.invalidArgument:
      return GrpcFailureText(
        message.isEmpty ? 'Check the form and try again.' : message,
        field: field,
      );
  }
  return GrpcFailureText(
    message.isEmpty ? 'The request could not be completed.' : message,
  );
}

/// Extracts the field name from a Connect validation error message.
///
/// The service sends `google.rpc.BadRequest` details, but goslow's request-id
/// interceptor re-wraps the error, so the wire-observable message is
/// `invalid_argument: <field>: <reason>`. Both forms are accepted.
String? fieldFromMessage(String message) {
  for (final match in _fieldPattern.allMatches(message)) {
    final field = match.group(1);
    if (field != null && !_connectCodes.contains(field)) return field;
  }
  return null;
}

/// Removes a leading Connect code such as `invalid_argument: `, leaving a
/// field-prefixed message (`name: is required`) intact.
String messageWithoutCode(String message) {
  for (final code in _connectCodes) {
    final prefix = '$code: ';
    if (message.startsWith(prefix)) return message.substring(prefix.length);
  }
  return message;
}

final _fieldPattern = RegExp(r'(?:^|: )([A-Za-z][A-Za-z0-9]*): ');

const _connectCodes = {
  'invalid_argument',
  'failed_precondition',
  'not_found',
  'unauthenticated',
  'permission_denied',
  'internal',
};
