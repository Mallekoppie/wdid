import 'package:grpc/grpc_or_grpcweb.dart';

import '../models/work_entry.dart';
import '../src/generated/timer.pb.dart' as generated;
import '../src/generated/timer.pbgrpc.dart' as generated_rpc;
import 'entry_api.dart' show entryFromProto;
import 'grpc_channel.dart';
import 'grpc_errors.dart';

/// What to do with the elapsed time when a timer stops.
enum TimerStopAction { save, keep, trim, discard }

/// Why a stop needs a decision before it can proceed.
enum TimerConflictReason { tooShort, blockLimit }

/// A stop the server refused until the caller chooses keep, trim or discard.
class TimerConflict implements Exception {
  const TimerConflict(this.reason);

  final TimerConflictReason reason;

  @override
  String toString() => switch (reason) {
    TimerConflictReason.tooShort =>
      'This timer has run for less than a minute.',
    TimerConflictReason.blockLimit => 'This timer is past your block limit.',
  };
}

/// A user-facing timer failure.
class TimerFailure extends ServiceFailure {
  const TimerFailure(super.message);
}

/// A server-owned timer snapshot. The client renders it; it never changes the
/// lifecycle locally.
class TimerSnapshot {
  const TimerSnapshot({
    required this.categoryId,
    this.subcategoryId = '',
    this.description = '',
    this.person = '',
    required this.startedAt,
    required this.segmentStartedAt,
    this.pausedAt,
    this.accumulatedPaused = Duration.zero,
    this.elapsed = Duration.zero,
    this.paused = false,
  });

  final String categoryId;
  final String subcategoryId;
  final String description;
  final String person;
  final DateTime startedAt;
  final DateTime segmentStartedAt;
  final DateTime? pausedAt;
  final Duration accumulatedPaused;

  /// Elapsed time when the server built the response.
  final Duration elapsed;
  final bool paused;

  bool get isPaused => paused || pausedAt != null;
}

/// The timer and the block limit that applies to it.
class TimerStatus {
  const TimerStatus({this.timer, required this.blockLimitMinutes});

  final TimerSnapshot? timer;
  final int blockLimitMinutes;
}

/// What a stop produced. A discarded timer has neither entry nor item.
class StopTimerResult {
  const StopTimerResult({this.entry, this.discarded = false});

  final WorkEntry? entry;
  final bool discarded;
}

/// The timer operations the UI consumes. Every call is scoped to the signed-in
/// account by the service.
abstract class TimerApi {
  Future<TimerStatus> getActiveTimer();

  Future<TimerSnapshot> startTimer({
    required String categoryId,
    String subcategoryId = '',
    String description = '',
    String person = '',
  });

  Future<TimerSnapshot> pauseTimer();

  Future<TimerSnapshot> resumeTimer();

  Future<StopTimerResult> stopTimer({
    TimerStopAction action = TimerStopAction.save,
  });
}

/// The narrow generated-client surface, separated so mapping and error
/// translation can be tested without a network channel.
abstract class TimerRpc {
  Future<generated.GetActiveTimerResponse> getActiveTimer(
    generated.GetActiveTimerRequest request,
  );

  Future<generated.StartTimerResponse> startTimer(
    generated.StartTimerRequest request,
  );

  Future<generated.PauseTimerResponse> pauseTimer(
    generated.PauseTimerRequest request,
  );

  Future<generated.ResumeTimerResponse> resumeTimer(
    generated.ResumeTimerRequest request,
  );

  Future<generated.StopTimerResponse> stopTimer(
    generated.StopTimerRequest request,
  );
}

/// The generated Connect client over gRPC-Web.
class GrpcTimerRpc implements TimerRpc {
  GrpcTimerRpc({
    generated_rpc.TimerServiceClient? client,
    String? Function()? token,
  }) : _client =
           client ??
           generated_rpc.TimerServiceClient(
             openAppChannel(),
             interceptors: [bearerInterceptor(token ?? (() => null))],
           );

  final generated_rpc.TimerServiceClient _client;

  @override
  Future<generated.GetActiveTimerResponse> getActiveTimer(
    generated.GetActiveTimerRequest request,
  ) => _client.getActiveTimer(request);

  @override
  Future<generated.StartTimerResponse> startTimer(
    generated.StartTimerRequest request,
  ) => _client.startTimer(request);

  @override
  Future<generated.PauseTimerResponse> pauseTimer(
    generated.PauseTimerRequest request,
  ) => _client.pauseTimer(request);

  @override
  Future<generated.ResumeTimerResponse> resumeTimer(
    generated.ResumeTimerRequest request,
  ) => _client.resumeTimer(request);

  @override
  Future<generated.StopTimerResponse> stopTimer(
    generated.StopTimerRequest request,
  ) => _client.stopTimer(request);
}

/// Timers over Connect/gRPC-Web.
class GrpcTimerApi implements TimerApi {
  GrpcTimerApi({TimerRpc? rpc}) : _rpc = rpc ?? GrpcTimerRpc();

  final TimerRpc _rpc;

  @override
  Future<TimerStatus> getActiveTimer() async {
    try {
      final response = await _rpc.getActiveTimer(
        generated.GetActiveTimerRequest(),
      );
      return TimerStatus(
        timer: response.hasTimer() ? _timerFromProto(response.timer) : null,
        blockLimitMinutes: response.blockLimit.seconds.toInt() ~/ 60,
      );
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TimerSnapshot> startTimer({
    required String categoryId,
    String subcategoryId = '',
    String description = '',
    String person = '',
  }) async {
    try {
      final response = await _rpc.startTimer(
        generated.StartTimerRequest(
          categoryId: categoryId,
          subcategoryId: subcategoryId,
          description: description,
          person: person,
        ),
      );
      return _timerFromProto(response.timer);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TimerSnapshot> pauseTimer() async {
    try {
      final response = await _rpc.pauseTimer(generated.PauseTimerRequest());
      return _timerFromProto(response.timer);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<TimerSnapshot> resumeTimer() async {
    try {
      final response = await _rpc.resumeTimer(generated.ResumeTimerRequest());
      return _timerFromProto(response.timer);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<StopTimerResult> stopTimer({
    TimerStopAction action = TimerStopAction.save,
  }) async {
    try {
      final response = await _rpc.stopTimer(
        generated.StopTimerRequest(action: _actionToProto(action)),
      );
      return StopTimerResult(
        entry: response.hasEntry() ? entryFromProto(response.entry) : null,
        discarded: response.discarded,
      );
    } on GrpcError catch (error) {
      throw _stopFailure(error);
    }
  }

  TimerFailure _failure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The service is unreachable. Check that the server is running.',
      unauthenticated: 'Sign in again to use the timer.',
      failedPrecondition: 'The timer changed. Refresh and try again.',
      notFound: 'That timer no longer exists.',
    );
    return TimerFailure(text.message);
  }

  TimerFailure _stopFailure(GrpcError error) {
    final message = error.message ?? '';
    if (error.code == StatusCode.failedPrecondition) {
      if (message.contains('timer_block_limit')) {
        throw const TimerConflict(TimerConflictReason.blockLimit);
      }
      if (message.contains('timer_too_short')) {
        throw const TimerConflict(TimerConflictReason.tooShort);
      }
    }
    return _failure(error);
  }
}

TimerSnapshot _timerFromProto(generated.ActiveTimer timer) => TimerSnapshot(
  categoryId: timer.categoryId,
  subcategoryId: timer.subcategoryId,
  description: timer.description,
  person: timer.person,
  startedAt: timer.startedAt.toDateTime(),
  segmentStartedAt: timer.segmentStartedAt.toDateTime(),
  pausedAt: timer.hasPausedAt() ? timer.pausedAt.toDateTime() : null,
  accumulatedPaused: Duration(seconds: timer.accumulatedPaused.seconds.toInt()),
  elapsed: Duration(seconds: timer.elapsed.seconds.toInt()),
  paused: timer.paused,
);

generated.TimerStopAction _actionToProto(TimerStopAction action) =>
    switch (action) {
      TimerStopAction.save =>
        generated.TimerStopAction.TIMER_STOP_ACTION_UNSPECIFIED,
      TimerStopAction.keep => generated.TimerStopAction.TIMER_STOP_ACTION_KEEP,
      TimerStopAction.trim => generated.TimerStopAction.TIMER_STOP_ACTION_TRIM,
      TimerStopAction.discard =>
        generated.TimerStopAction.TIMER_STOP_ACTION_DISCARD,
    };
