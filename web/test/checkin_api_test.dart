import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/checkin_api.dart';
import 'package:wdid_web/models/check_in.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/src/generated/check_ins.pb.dart' as generated;

duration.Duration minutes(int value) =>
    duration.Duration(seconds: Int64(value * 60));

generated.CheckIn wireCheckIn() => generated.CheckIn(
  id: 'checkin-1',
  kind: generated.CheckInKind.CHECK_IN_KIND_MANAGER,
  periodStart: '2026-10-01',
  periodEnd: '2026-10-20',
  state: generated.CheckInState.CHECK_IN_STATE_DRAFT,
  audience: generated.CheckInAudience.CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
  focusNotes: 'Ship the backfill.',
  additionalContext: 'Unrecorded customer call on Friday.',
  summaryMarkdown: '## Highlights',
  summaryModel: 'test/model',
  promptVersion: 'v1',
  generationPrompt: 'user:\nExact prompt sent',
  previousSummaryMarkdown: '## Previous\n- Restorable',
  totals: generated.CheckInTotals(
    total: minutes(90),
    byCategory: [generated.CheckInTotal(key: 'cat-1', duration: minutes(60))],
    bySubcategory: [
      generated.CheckInTotal(key: 'sub-1', duration: minutes(60)),
    ],
    supportByPerson: [
      generated.CheckInTotal(key: 'Priya', duration: minutes(30)),
    ],
    supportDuration: minutes(30),
    supportInteractions: 1,
  ),
  createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20, 12)),
  updatedAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 21, 9)),
);

class _FakeCheckInRpc implements CheckInRpc {
  final List<generated.ListCheckInsRequest> listRequests = [];
  final List<generated.GetCheckInRequest> getRequests = [];
  final List<generated.GetCheckInDefaultsRequest> defaultsRequests = [];
  final List<generated.CreateCheckInRequest> createRequests = [];
  final List<generated.UpdateCheckInRequest> updateRequests = [];
  final List<generated.BuildCheckInPromptRequest> promptRequests = [];
  final List<generated.FinalizeCheckInRequest> finalizeRequests = [];
  final List<generated.DeleteCheckInRequest> deleteRequests = [];

  generated.ListCheckInsResponse? listResponse;
  Object? failure;

  @override
  Future<generated.ListCheckInsResponse> listCheckIns(
    generated.ListCheckInsRequest request,
  ) async {
    listRequests.add(request);
    if (failure != null) throw failure!;
    final response =
        listResponse ??
        generated.ListCheckInsResponse(checkIns: [wireCheckIn()]);
    // A real paginated service stops returning a token past the last page;
    // echoing one forever would make the client's paging loop spin.
    if (request.pageToken.isEmpty) return response;
    return generated.ListCheckInsResponse(checkIns: response.checkIns);
  }

  @override
  Future<generated.GetCheckInResponse> getCheckIn(
    generated.GetCheckInRequest request,
  ) async {
    getRequests.add(request);
    if (failure != null) throw failure!;
    return generated.GetCheckInResponse(checkIn: wireCheckIn());
  }

  @override
  Future<generated.GetCheckInDefaultsResponse> getCheckInDefaults(
    generated.GetCheckInDefaultsRequest request,
  ) async {
    defaultsRequests.add(request);
    if (failure != null) throw failure!;
    return generated.GetCheckInDefaultsResponse(
      periodStart: '2026-09-01',
      periodEnd: '2026-10-22',
      lastFinalCheckInId: 'checkin-final',
    );
  }

  @override
  Future<generated.CreateCheckInResponse> createCheckIn(
    generated.CreateCheckInRequest request,
  ) async {
    createRequests.add(request);
    if (failure != null) throw failure!;
    return generated.CreateCheckInResponse(checkIn: wireCheckIn());
  }

  @override
  Future<generated.UpdateCheckInResponse> updateCheckIn(
    generated.UpdateCheckInRequest request,
  ) async {
    updateRequests.add(request);
    if (failure != null) throw failure!;
    return generated.UpdateCheckInResponse(checkIn: wireCheckIn());
  }

  @override
  Future<generated.BuildCheckInPromptResponse> buildPrompt(
    generated.BuildCheckInPromptRequest request,
  ) async {
    promptRequests.add(request);
    if (failure != null) throw failure!;
    return generated.BuildCheckInPromptResponse(
      prompt: 'You are preparing a 1:1.\n\n## Highlights',
      promptVersion: 'v1',
      variant: generated
          .CheckInPromptVariant
          .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW,
    );
  }

  @override
  Future<generated.FinalizeCheckInResponse> finalizeCheckIn(
    generated.FinalizeCheckInRequest request,
  ) async {
    finalizeRequests.add(request);
    if (failure != null) throw failure!;
    return generated.FinalizeCheckInResponse(
      checkIn: wireCheckIn()
        ..state = generated.CheckInState.CHECK_IN_STATE_FINAL,
    );
  }

  @override
  Future<generated.DeleteCheckInResponse> deleteCheckIn(
    generated.DeleteCheckInRequest request,
  ) async {
    deleteRequests.add(request);
    if (failure != null) throw failure!;
    return generated.DeleteCheckInResponse();
  }
}

void main() {
  test('lists both kinds or narrows the request by kind', () async {
    final rpc = _FakeCheckInRpc();
    final api = GrpcCheckInApi(rpc: rpc);

    final all = await api.listCheckIns();
    final managers = await api.listCheckIns(kind: CheckInKind.manager);

    expect(rpc.listRequests, hasLength(2));
    expect(
      rpc.listRequests.first.kind,
      generated.CheckInKind.CHECK_IN_KIND_UNSPECIFIED,
    );
    expect(
      rpc.listRequests.last.kind,
      generated.CheckInKind.CHECK_IN_KIND_MANAGER,
    );
    expect(all, hasLength(1));
    expect(managers.single.kind, CheckInKind.manager);
    expect(managers.single.audience, CheckInAudience.performanceReview);
    expect(managers.single.state, CheckInState.draft);
    expect(managers.single.focusNotes, 'Ship the backfill.');
    expect(
      managers.single.additionalContext,
      'Unrecorded customer call on Friday.',
    );
    expect(managers.single.generationPrompt, 'user:\nExact prompt sent');
    expect(
      managers.single.previousSummaryMarkdown,
      '## Previous\n- Restorable',
    );
    expect(managers.single.summaryModel, 'test/model');
    expect(managers.single.updatedAt, DateTime.utc(2026, 10, 21, 9));
    expect(managers.single.totals.minutes, 90);
    expect(managers.single.totals.byCategory['cat-1'], 60);
    expect(managers.single.totals.bySubcategory['sub-1'], 60);
    expect(managers.single.totals.supportByPerson['Priya'], 30);
    expect(managers.single.totals.supportMinutes, 30);
    expect(managers.single.totals.supportInteractions, 1);
  });

  test('follows list pagination until the token is empty', () async {
    final rpc = _FakeCheckInRpc()
      ..listResponse = generated.ListCheckInsResponse(
        checkIns: [wireCheckIn()],
        nextPageToken: '2',
      );
    final api = GrpcCheckInApi(rpc: rpc);

    await api.listCheckIns(kind: CheckInKind.personal);

    expect(rpc.listRequests, hasLength(2));
    expect(rpc.listRequests.first.pageToken, '');
    expect(rpc.listRequests.last.pageToken, '2');
    expect(
      rpc.listRequests.last.kind,
      generated.CheckInKind.CHECK_IN_KIND_PERSONAL,
    );
  });

  test('maps the server-computed defaults', () async {
    final rpc = _FakeCheckInRpc();
    final api = GrpcCheckInApi(rpc: rpc);

    final defaults = await api.getCheckInDefaults(kind: CheckInKind.manager);

    expect(
      rpc.defaultsRequests.single.kind,
      generated.CheckInKind.CHECK_IN_KIND_MANAGER,
    );
    expect(defaults.periodStart, DateTime(2026, 9, 1));
    expect(defaults.periodEnd, DateTime(2026, 10, 22));
    expect(defaults.lastFinalCheckInId, 'checkin-final');
  });

  test(
    'maps a create draft including kind, audience and focus notes',
    () async {
      final rpc = _FakeCheckInRpc();
      final api = GrpcCheckInApi(rpc: rpc);

      final created = await api.createCheckIn(
        CheckInDraft(
          periodStart: DateTime(2026, 10, 1),
          periodEnd: DateTime(2026, 10, 20),
          kind: CheckInKind.manager,
          audience: CheckInAudience.performanceReview,
          focusNotes: 'Focus',
        ),
      );

      final request = rpc.createRequests.single;
      expect(request.kind, generated.CheckInKind.CHECK_IN_KIND_MANAGER);
      expect(request.periodStart, '2026-10-01');
      expect(request.periodEnd, '2026-10-20');
      expect(
        request.audience,
        generated.CheckInAudience.CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
      );
      expect(request.focusNotes, 'Focus');
      expect(created.id, 'checkin-1');
    },
  );

  test('a personal draft never sends an audience', () async {
    final rpc = _FakeCheckInRpc();
    final api = GrpcCheckInApi(rpc: rpc);

    await api.createCheckIn(
      CheckInDraft(
        periodStart: DateTime(2026, 10, 1),
        periodEnd: DateTime(2026, 10, 20),
        kind: CheckInKind.personal,
        audience: CheckInAudience.oneOnOne,
      ),
    );

    expect(
      rpc.createRequests.single.audience,
      generated.CheckInAudience.CHECK_IN_AUDIENCE_UNSPECIFIED,
    );
  });

  test('updates and finalizes by id', () async {
    final rpc = _FakeCheckInRpc();
    final api = GrpcCheckInApi(rpc: rpc);
    final checkIn = CheckIn(
      id: 'checkin-1',
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 20),
      createdAt: DateTime.utc(2026, 10, 20),
      audience: CheckInAudience.oneOnOne,
      summaryMarkdown: 'Rewritten',
      additionalContext: 'A fact the ledger missed.',
    );

    await api.updateCheckIn(checkIn);
    final finalized = await api.finalizeCheckIn(checkIn.id);

    expect(rpc.updateRequests.single.id, 'checkin-1');
    expect(rpc.updateRequests.single.summaryMarkdown, 'Rewritten');
    // Context travels with the whole mutable check-in so a context-only save
    // leaves the summary, model and prompt version unchanged.
    expect(
      rpc.updateRequests.single.additionalContext,
      'A fact the ledger missed.',
    );
    expect(
      rpc.updateRequests.single.audience,
      generated.CheckInAudience.CHECK_IN_AUDIENCE_ONE_ON_ONE,
    );
    expect(rpc.finalizeRequests.single.id, 'checkin-1');
    expect(finalized.state, CheckInState.final_);
    expect(finalized.isReadOnly, isTrue);
  });

  test('saves a manual summary and maps the overwrite confirmation', () async {
    final rpc = _FakeCheckInRpc();
    final api = GrpcCheckInApi(rpc: rpc);
    final checkIn = CheckIn(
      id: 'checkin-1',
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 20),
      createdAt: DateTime.utc(2026, 10, 20),
      audience: CheckInAudience.performanceReview,
      summaryMarkdown: '## Manual',
    );

    await api.updateCheckIn(checkIn);
    expect(
      rpc.updateRequests.last.summarySource,
      generated.CheckInSummarySource.CHECK_IN_SUMMARY_SOURCE_MANUAL,
    );
    expect(rpc.updateRequests.last.overwriteManualEdits, isFalse);

    await api.updateCheckIn(
      checkIn,
      source: CheckInSummarySource.generated,
      overwriteManualEdits: true,
    );
    expect(
      rpc.updateRequests.last.summarySource,
      generated.CheckInSummarySource.CHECK_IN_SUMMARY_SOURCE_GENERATED,
    );
    expect(rpc.updateRequests.last.overwriteManualEdits, isTrue);
  });

  test('maps the prompt variant returned for the audience', () async {
    final rpc = _FakeCheckInRpc();
    final api = GrpcCheckInApi(rpc: rpc);

    final prompt = await api.buildPrompt('checkin-1');

    expect(rpc.promptRequests.single.id, 'checkin-1');
    expect(prompt.prompt, contains('1:1'));
    expect(prompt.promptVersion, 'v1');
    expect(prompt.variant, CheckInPromptVariant.managerPerformanceReview);
    expect(prompt.variant.label, 'Performance review');
  });

  test('deletes a personal review by id', () async {
    final rpc = _FakeCheckInRpc();
    final api = GrpcCheckInApi(rpc: rpc);

    await api.deleteCheckIn('checkin-personal');

    expect(rpc.deleteRequests.single.id, 'checkin-personal');
  });

  test('surfaces a refused delete as a check-in failure', () async {
    final rpc = _FakeCheckInRpc()
      ..failure = GrpcError.failedPrecondition(
        'a final manager check-in is read-only',
      );
    final api = GrpcCheckInApi(rpc: rpc);

    await expectLater(
      api.deleteCheckIn('checkin-final'),
      throwsA(
        isA<CheckInFailure>().having(
          (failure) => failure.message,
          'message',
          contains('read-only'),
        ),
      ),
    );
  });

  test('maps a validation failure onto the rejected field', () async {
    final rpc = _FakeCheckInRpc()
      ..failure = GrpcError.invalidArgument(
        'invalid_argument: periodEnd: must not be before periodStart',
      );
    final api = GrpcCheckInApi(rpc: rpc);

    await expectLater(
      api.createCheckIn(
        CheckInDraft(
          periodStart: DateTime(2026, 10, 20),
          periodEnd: DateTime(2026, 10, 1),
          audience: CheckInAudience.oneOnOne,
        ),
      ),
      throwsA(
        isA<CheckInFailure>()
            .having((failure) => failure.field, 'field', 'periodEnd')
            .having(
              (failure) => failure.message,
              'message',
              'periodEnd: must not be before periodStart',
            ),
      ),
    );
  });

  test('legacy totals fall back to the per-person rows', () {
    final legacy = generated.CheckInTotals(
      total: minutes(90),
      supportByPerson: [
        generated.CheckInTotal(key: 'Priya', duration: minutes(30)),
      ],
    );

    final totals = checkInTotalsFromProto(legacy);

    expect(totals.supportMinutes, 30);
    expect(totals.supportInteractions, 1);
  });

  test('fresh multi-person totals keep their authoritative values', () {
    final fresh = generated.CheckInTotals(
      supportByPerson: [
        generated.CheckInTotal(key: 'Priya', duration: minutes(45)),
        generated.CheckInTotal(key: 'Sam', duration: minutes(45)),
      ],
      supportDuration: minutes(45),
      supportInteractions: 2,
    );

    final totals = checkInTotalsFromProto(fresh);

    expect(totals.supportMinutes, 45);
    expect(totals.supportInteractions, 2);
  });

  test('legacy JSON totals fall back to the per-person rows', () {
    final totals = CheckInTotals.fromJson({
      'minutes': 90,
      'supportByPerson': {'Priya': 30},
    });

    expect(totals.supportMinutes, 30);
    expect(totals.supportInteractions, 1);
  });

  test('fresh JSON totals keep their authoritative values', () {
    final totals = CheckInTotals.fromJson({
      'minutes': 90,
      'supportByPerson': {'Priya': 45, 'Sam': 45},
      'supportMinutes': 45,
      'supportInteractions': 2,
    });

    expect(totals.supportMinutes, 45);
    expect(totals.supportInteractions, 2);
  });

  test('maps a final check-in rejection to a state message', () async {
    final rpc = _FakeCheckInRpc()
      ..failure = GrpcError.failedPrecondition(
        'a final manager check-in is read-only',
      );
    final api = GrpcCheckInApi(rpc: rpc);

    await expectLater(
      api.finalizeCheckIn('checkin-1'),
      throwsA(
        isA<CheckInFailure>().having(
          (failure) => failure.message,
          'message',
          contains('read-only'),
        ),
      ),
    );
  });
}
