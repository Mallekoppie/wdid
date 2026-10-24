import 'dart:async';

import 'package:wdid_web/data/checkin_api.dart';
import 'package:wdid_web/models/check_in.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/enums.dart';

/// In-memory check-in service used by widget and state tests.
class FakeCheckInApi implements CheckInApi {
  FakeCheckInApi({List<CheckIn>? checkIns, CheckInDefaults? defaults})
    : checkIns = checkIns ?? [],
      defaults =
          defaults ??
          CheckInDefaults(
            periodStart: DateTime(2026, 10, 1),
            periodEnd: DateTime(2026, 10, 23),
          );

  final List<CheckIn> checkIns;
  CheckInDefaults defaults;

  CheckInFailure? failure;
  CheckInFailure? defaultsFailure;
  CheckInFailure? detailFailure;
  CheckInFailure? promptFailure;

  CheckInKind? lastKind;
  int listCalls = 0;

  /// The timestamp assigned to created and finalized records. Tests that
  /// exercise the cadence prompt set this to the wall clock so "this period"
  /// matches the app's own notion of today.
  DateTime now = DateTime(2026, 10, 23, 12);

  final List<CheckInDraft> createRequests = [];
  final List<CheckIn> updateRequests = [];
  final List<String> finalizeRequests = [];
  final List<String> deleteRequests = [];
  final List<String> promptRequests = [];
  final List<CheckInSummarySource> updateSources = [];

  /// When set, the next detail read waits for it so tests can observe loading.
  Completer<void>? detailGate;

  /// When set, the next defaults read waits for it.
  Completer<void>? defaultsGate;

  int _sequence = 0;

  void _maybeFail(CheckInFailure? error) {
    if (error != null) throw error;
  }

  @override
  Future<List<CheckIn>> listCheckIns({CheckInKind? kind}) async {
    listCalls++;
    lastKind = kind;
    _maybeFail(failure);
    return [
      for (final checkIn in checkIns)
        if (kind == null || checkIn.kind == kind) checkIn,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<CheckIn> getCheckIn(String id) async {
    if (detailGate != null) {
      final pending = detailGate!;
      detailGate = null;
      await pending.future;
    }
    _maybeFail(detailFailure);
    for (final checkIn in checkIns) {
      if (checkIn.id == id) return checkIn;
    }
    throw CheckInFailure('That check-in no longer exists.');
  }

  @override
  Future<CheckInDefaults> getCheckInDefaults({
    CheckInKind kind = CheckInKind.manager,
  }) async {
    if (defaultsGate != null) {
      final pending = defaultsGate!;
      defaultsGate = null;
      await pending.future;
    }
    _maybeFail(defaultsFailure);
    return defaults;
  }

  @override
  Future<CheckIn> createCheckIn(CheckInDraft draft) async {
    createRequests.add(draft);
    _maybeFail(failure);
    _sequence++;
    final createdAt = now;
    final checkIn = CheckIn(
      id: 'checkin-created-$_sequence',
      periodStart: draft.periodStart,
      periodEnd: draft.periodEnd,
      createdAt: createdAt,
      updatedAt: createdAt,
      kind: draft.kind,
      audience: draft.kind == CheckInKind.manager ? draft.audience : null,
      focusNotes: draft.focusNotes,
      totals: const CheckInTotals(minutes: 90),
    );
    checkIns.add(checkIn);
    return checkIn;
  }

  @override
  Future<CheckIn> updateCheckIn(
    CheckIn checkIn, {
    CheckInSummarySource source = CheckInSummarySource.manual,
    bool overwriteManualEdits = false,
  }) async {
    updateRequests.add(checkIn);
    updateSources.add(source);
    _maybeFail(failure);
    final index = checkIns.indexWhere((item) => item.id == checkIn.id);
    if (index == -1) throw CheckInFailure('That check-in no longer exists.');
    checkIns[index] = checkIn;
    return checkIn;
  }

  @override
  Future<CheckInPrompt> buildPrompt(String id) async {
    promptRequests.add(id);
    _maybeFail(promptFailure);
    final index = checkIns.indexWhere((item) => item.id == id);
    if (index == -1) throw CheckInFailure('That check-in no longer exists.');
    final checkIn = checkIns[index];
    return CheckInPrompt(
      prompt: 'Use only the data supplied. ${checkIn.promptVariant.label}',
      variant: checkIn.promptVariant,
      promptVersion: checkIn.promptVersion,
    );
  }

  @override
  Future<CheckIn> finalizeCheckIn(String id) async {
    finalizeRequests.add(id);
    _maybeFail(failure);
    final index = checkIns.indexWhere((item) => item.id == id);
    if (index == -1) throw CheckInFailure('That check-in no longer exists.');
    final updated = checkIns[index].copyWith(
      state: CheckInState.final_,
      updatedAt: DateTime(2026, 10, 23, 13),
    );
    checkIns[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteCheckIn(String id) async {
    deleteRequests.add(id);
    _maybeFail(failure);
    final index = checkIns.indexWhere((item) => item.id == id);
    if (index == -1) throw CheckInFailure('That check-in no longer exists.');
    final checkIn = checkIns[index];
    if (checkIn.isManager && checkIn.isFinal) {
      throw const CheckInFailure(
        'That check-in cannot be changed in its current state.',
      );
    }
    checkIns.removeAt(index);
  }
}
