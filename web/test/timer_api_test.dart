import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/timer_api.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/src/generated/entries.pb.dart' as entries;
import 'package:wdid_web/src/generated/timer.pb.dart' as generated;

class FakeTimerRpc implements TimerRpc {
  Object? error;

  generated.ActiveTimer timer = protoTimer();
  bool timerPresent = true;
  entries.WorkEntry entry = entries.WorkEntry();

  generated.StartTimerRequest? startRequest;
  generated.StopTimerRequest? stopRequest;
  String? pausedId;
  String? resumedId;

  void _maybeFail() {
    if (error != null) throw error!;
  }

  @override
  Future<generated.GetActiveTimerResponse> getActiveTimer(
    generated.GetActiveTimerRequest request,
  ) async {
    _maybeFail();
    return generated.GetActiveTimerResponse(
      timer: timerPresent ? timer : null,
      blockLimit: duration.Duration(seconds: Int64(240 * 60)),
    );
  }

  @override
  Future<generated.StartTimerResponse> startTimer(
    generated.StartTimerRequest request,
  ) async {
    startRequest = request;
    _maybeFail();
    return generated.StartTimerResponse(timer: timer);
  }

  @override
  Future<generated.PauseTimerResponse> pauseTimer(
    generated.PauseTimerRequest request,
  ) async {
    pausedId = 'paused';
    _maybeFail();
    return generated.PauseTimerResponse(timer: timer);
  }

  @override
  Future<generated.ResumeTimerResponse> resumeTimer(
    generated.ResumeTimerRequest request,
  ) async {
    resumedId = 'resumed';
    _maybeFail();
    return generated.ResumeTimerResponse(timer: timer);
  }

  @override
  Future<generated.StopTimerResponse> stopTimer(
    generated.StopTimerRequest request,
  ) async {
    stopRequest = request;
    _maybeFail();
    return generated.StopTimerResponse(entry: entry);
  }
}

generated.ActiveTimer protoTimer({
  bool paused = false,
  String description = 'Backfill script',
  String person = '',
}) {
  final started = DateTime.utc(2026, 10, 18, 9);
  return generated.ActiveTimer(
    categoryId: 'cat-1',
    subcategoryId: 'sub-1',
    description: description,
    person: person,
    startedAt: Timestamp.fromDateTime(started),
    segmentStartedAt: Timestamp.fromDateTime(
      started.add(const Duration(minutes: 10)),
    ),
    pausedAt: paused
        ? Timestamp.fromDateTime(started.add(const Duration(minutes: 10)))
        : null,
    accumulatedPaused: duration.Duration(seconds: Int64(600)),
    elapsed: duration.Duration(seconds: Int64(1200)),
    paused: paused,
  );
}

void main() {
  test('getActiveTimer maps the snapshot and block limit', () async {
    final rpc = FakeTimerRpc();

    final status = await GrpcTimerApi(rpc: rpc).getActiveTimer();

    expect(status.blockLimitMinutes, 240);
    final timer = status.timer!;
    expect(timer.categoryId, 'cat-1');
    expect(timer.subcategoryId, 'sub-1');
    expect(timer.description, 'Backfill script');
    expect(timer.accumulatedPaused, const Duration(minutes: 10));
    expect(timer.elapsed, const Duration(minutes: 20));
    expect(timer.isPaused, isFalse);
  });

  test('an absent timer is null rather than an error', () async {
    final rpc = FakeTimerRpc()..timerPresent = false;

    final status = await GrpcTimerApi(rpc: rpc).getActiveTimer();

    expect(status.timer, isNull);
    expect(status.blockLimitMinutes, 240);
  });

  test('startTimer sends the attribution, description and person', () async {
    final rpc = FakeTimerRpc();

    final timer = await GrpcTimerApi(rpc: rpc).startTimer(
      categoryId: 'cat-1',
      subcategoryId: 'sub-1',
      description: 'Backfill script',
      person: 'Priya',
    );

    expect(rpc.startRequest!.categoryId, 'cat-1');
    expect(rpc.startRequest!.subcategoryId, 'sub-1');
    expect(rpc.startRequest!.description, 'Backfill script');
    expect(rpc.startRequest!.person, 'Priya');
    expect(timer.categoryId, 'cat-1');
  });

  test('pause and resume send their transitions', () async {
    final rpc = FakeTimerRpc();
    final api = GrpcTimerApi(rpc: rpc);

    await api.pauseTimer();
    expect(rpc.pausedId, 'paused');

    await api.resumeTimer();
    expect(rpc.resumedId, 'resumed');
  });

  test('stopTimer maps every action onto the wire enum', () async {
    final rpc = FakeTimerRpc();
    final api = GrpcTimerApi(rpc: rpc);

    await api.stopTimer(action: TimerStopAction.keep);
    expect(
      rpc.stopRequest!.action,
      generated.TimerStopAction.TIMER_STOP_ACTION_KEEP,
    );

    await api.stopTimer(action: TimerStopAction.trim);
    expect(
      rpc.stopRequest!.action,
      generated.TimerStopAction.TIMER_STOP_ACTION_TRIM,
    );

    await api.stopTimer(action: TimerStopAction.discard);
    expect(
      rpc.stopRequest!.action,
      generated.TimerStopAction.TIMER_STOP_ACTION_DISCARD,
    );

    await api.stopTimer();
    expect(
      rpc.stopRequest!.action,
      generated.TimerStopAction.TIMER_STOP_ACTION_UNSPECIFIED,
    );
  });

  test('stopTimer maps the saved entry', () async {
    final rpc = FakeTimerRpc()
      ..entry = entries.WorkEntry(
        id: 'entry-1',
        categoryId: 'cat-1',
        description: 'Backfill script',
        duration: duration.Duration(seconds: Int64(25 * 60)),
        source: entries.EntrySource.ENTRY_SOURCE_TIMER,
      );

    final result = await GrpcTimerApi(rpc: rpc).stopTimer();

    expect(result.discarded, isFalse);
    expect(result.entry!.id, 'entry-1');
    expect(result.entry!.minutes, 25);
    expect(result.entry!.source, EntrySource.timer);
  });

  test('a block-limit stop surfaces the conflict reason', () async {
    final rpc = FakeTimerRpc()
      ..error = GrpcError.failedPrecondition(
        'timer_block_limit: 300 minutes exceeds the 240 minute block limit',
      );

    expect(
      () => GrpcTimerApi(rpc: rpc).stopTimer(),
      throwsA(
        isA<TimerConflict>().having(
          (conflict) => conflict.reason,
          'reason',
          TimerConflictReason.blockLimit,
        ),
      ),
    );
  });

  test('a short stop surfaces the conflict reason', () async {
    final rpc = FakeTimerRpc()
      ..error = GrpcError.failedPrecondition(
        'timer_too_short: the timer has run for less than a minute',
      );

    expect(
      () => GrpcTimerApi(rpc: rpc).stopTimer(),
      throwsA(
        isA<TimerConflict>().having(
          (conflict) => conflict.reason,
          'reason',
          TimerConflictReason.tooShort,
        ),
      ),
    );
  });
}
