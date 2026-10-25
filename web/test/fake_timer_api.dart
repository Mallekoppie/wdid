import 'package:wdid_web/data/timer_api.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/utils/time_utils.dart';

/// In-memory TimerService used by state and widget tests. The fake owns the
/// timer exactly as the server does, so a rebuilt app sees the same snapshot.
class FakeTimerApi implements TimerApi {
  TimerSnapshot? timer;
  int blockLimitMinutes = 240;

  /// Minutes a stop would record. Tests set this to cross the block limit.
  int elapsedMinutesOnStop = 30;

  /// When set, the next stop throws this conflict before changing state.
  TimerConflict? stopConflict;

  final List<TimerStopAction> stopActions = [];
  int startCalls = 0;
  int getActiveCalls = 0;

  /// The raw arguments of the most recent start. The snapshot substitutes a
  /// default description, so tests asserting "no description" read these.
  String? lastStartCategoryId;
  String? lastStartSubcategoryId;
  String? lastStartDescription;
  String? lastStartPerson;

  /// Every entry this fake's stop produced, in order. Tests can pass this list
  /// to a fake entry service so a stopped timer is visible to reloads.
  final List<WorkEntry> savedEntries = [];

  @override
  Future<TimerStatus> getActiveTimer() async {
    getActiveCalls++;
    return TimerStatus(timer: timer, blockLimitMinutes: blockLimitMinutes);
  }

  @override
  Future<TimerSnapshot> startTimer({
    required String categoryId,
    String subcategoryId = '',
    String description = '',
    String person = '',
  }) async {
    startCalls++;
    lastStartCategoryId = categoryId;
    lastStartSubcategoryId = subcategoryId;
    lastStartDescription = description;
    lastStartPerson = person;
    if (timer != null) {
      throw const TimerFailure('A timer is already running.');
    }
    final now = DateTime.now().toUtc();
    timer = TimerSnapshot(
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      description: description.trim().isEmpty
          ? 'Focus block'
          : description.trim(),
      person: person,
      startedAt: now,
      segmentStartedAt: now,
    );
    return timer!;
  }

  @override
  Future<TimerSnapshot> pauseTimer() async {
    final current = timer;
    if (current == null) {
      throw const TimerFailure('No timer is running.');
    }
    if (current.isPaused) return current;
    final pausedAt = DateTime.now().toUtc();
    final accumulated =
        current.accumulatedPaused +
        pausedAt.difference(current.segmentStartedAt);
    timer = TimerSnapshot(
      categoryId: current.categoryId,
      subcategoryId: current.subcategoryId,
      description: current.description,
      person: current.person,
      startedAt: current.startedAt,
      segmentStartedAt: current.segmentStartedAt,
      pausedAt: pausedAt,
      accumulatedPaused: accumulated,
      elapsed: accumulated,
      paused: true,
    );
    return timer!;
  }

  @override
  Future<TimerSnapshot> resumeTimer() async {
    final current = timer;
    if (current == null) {
      throw const TimerFailure('No timer is running.');
    }
    if (!current.isPaused) return current;
    timer = TimerSnapshot(
      categoryId: current.categoryId,
      subcategoryId: current.subcategoryId,
      description: current.description,
      person: current.person,
      startedAt: current.startedAt,
      segmentStartedAt: DateTime.now().toUtc(),
      accumulatedPaused: current.accumulatedPaused,
      elapsed: current.accumulatedPaused,
    );
    return timer!;
  }

  @override
  Future<StopTimerResult> stopTimer({
    TimerStopAction action = TimerStopAction.save,
  }) async {
    stopActions.add(action);
    final conflict = stopConflict;
    if (conflict != null) {
      stopConflict = null;
      throw conflict;
    }

    final current = timer;
    if (current == null) {
      throw const TimerFailure('No timer is running.');
    }

    if (action == TimerStopAction.discard) {
      timer = null;
      return const StopTimerResult(discarded: true);
    }

    var minutes = elapsedMinutesOnStop;
    if (minutes > blockLimitMinutes && action == TimerStopAction.trim) {
      minutes = blockLimitMinutes;
    }
    final entry = WorkEntry(
      id: 'timer-entry-${stopActions.length}',
      categoryId: current.categoryId,
      subcategoryId: current.subcategoryId,
      description: current.description.isEmpty
          ? 'Timer work'
          : current.description,
      startedAt: current.startedAt,
      endedAt: current.startedAt.add(Duration(minutes: minutes)),
      minutes: minutes,
      localDate: isoDate(current.startedAt.toLocal()),
      person: current.person,
      source: EntrySource.timer,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    timer = null;
    savedEntries.add(entry);
    return StopTimerResult(entry: entry);
  }
}
