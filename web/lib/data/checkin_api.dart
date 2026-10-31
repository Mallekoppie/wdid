import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;

import '../models/check_in.dart';
import '../models/drafts.dart';
import '../models/enums.dart';
import '../src/generated/check_ins.pb.dart' as generated;
import '../src/generated/check_ins.pbgrpc.dart' as generated_rpc;
import 'grpc_channel.dart';
import 'grpc_errors.dart';
import 'prompt_variant_mapping.dart';

/// A user-facing check-in failure, with the field the service rejected.
class CheckInFailure extends ServiceFailure {
  const CheckInFailure(super.message, {super.field});
}

/// Manager check-ins and personal reviews over Connect/gRPC-Web. The period
/// boundary and the stored aggregate snapshot are both computed by the service;
/// the detail screen still reads the authoritative period report for its live
/// category, project, support and rhythm totals.
abstract class CheckInApi {
  /// Lists check-ins newest first. A null [kind] lists both manager check-ins
  /// and personal reviews.
  Future<List<CheckIn>> listCheckIns({CheckInKind? kind});

  Future<CheckIn> getCheckIn(String id);

  /// The server-computed period for a new check-in: the day after the last
  /// final manager check-in, or the journal start date, through today.
  Future<CheckInDefaults> getCheckInDefaults({
    CheckInKind kind = CheckInKind.manager,
  });

  Future<CheckIn> createCheckIn(CheckInDraft draft);

  /// Replaces the mutable fields. [source] is `manual` for the user's own
  /// text; generated output must also set [overwriteManualEdits] to replace a
  /// summary that was edited by hand.
  Future<CheckIn> updateCheckIn(
    CheckIn checkIn, {
    CheckInSummarySource source = CheckInSummarySource.manual,
    bool overwriteManualEdits = false,
  });

  /// The prompt block for one check-in. The check-in's audience selects the
  /// variant; the instruction text comes from the service.
  Future<CheckInPrompt> buildPrompt(String id);

  /// Makes a manager check-in read-only and moves the next boundary.
  Future<CheckIn> finalizeCheckIn(String id);

  /// Removes a saved personal review. A final manager check-in is the boundary
  /// for the next period and is rejected by the service.
  Future<void> deleteCheckIn(String id);
}

/// The narrow generated-client surface, separated so field mapping and error
/// translation can be tested without a network channel.
abstract class CheckInRpc {
  Future<generated.ListCheckInsResponse> listCheckIns(
    generated.ListCheckInsRequest request,
  );

  Future<generated.GetCheckInResponse> getCheckIn(
    generated.GetCheckInRequest request,
  );

  Future<generated.GetCheckInDefaultsResponse> getCheckInDefaults(
    generated.GetCheckInDefaultsRequest request,
  );

  Future<generated.CreateCheckInResponse> createCheckIn(
    generated.CreateCheckInRequest request,
  );

  Future<generated.UpdateCheckInResponse> updateCheckIn(
    generated.UpdateCheckInRequest request,
  );

  Future<generated.BuildCheckInPromptResponse> buildPrompt(
    generated.BuildCheckInPromptRequest request,
  );

  Future<generated.FinalizeCheckInResponse> finalizeCheckIn(
    generated.FinalizeCheckInRequest request,
  );

  Future<generated.DeleteCheckInResponse> deleteCheckIn(
    generated.DeleteCheckInRequest request,
  );
}

/// The generated Connect client over gRPC-Web.
class GrpcCheckInRpc implements CheckInRpc {
  GrpcCheckInRpc({
    generated_rpc.CheckInServiceClient? client,
    ApiSession? session,
  }) : _client =
           client ??
           generated_rpc.CheckInServiceClient(
             openAppChannel(),
             interceptors: sessionInterceptors(session),
           );

  final generated_rpc.CheckInServiceClient _client;

  @override
  Future<generated.ListCheckInsResponse> listCheckIns(
    generated.ListCheckInsRequest request,
  ) => _client.listCheckIns(request);

  @override
  Future<generated.GetCheckInResponse> getCheckIn(
    generated.GetCheckInRequest request,
  ) => _client.getCheckIn(request);

  @override
  Future<generated.GetCheckInDefaultsResponse> getCheckInDefaults(
    generated.GetCheckInDefaultsRequest request,
  ) => _client.getCheckInDefaults(request);

  @override
  Future<generated.CreateCheckInResponse> createCheckIn(
    generated.CreateCheckInRequest request,
  ) => _client.createCheckIn(request);

  @override
  Future<generated.UpdateCheckInResponse> updateCheckIn(
    generated.UpdateCheckInRequest request,
  ) => _client.updateCheckIn(request);

  @override
  Future<generated.BuildCheckInPromptResponse> buildPrompt(
    generated.BuildCheckInPromptRequest request,
  ) => _client.buildCheckInPrompt(request);

  @override
  Future<generated.FinalizeCheckInResponse> finalizeCheckIn(
    generated.FinalizeCheckInRequest request,
  ) => _client.finalizeCheckIn(request);

  @override
  Future<generated.DeleteCheckInResponse> deleteCheckIn(
    generated.DeleteCheckInRequest request,
  ) => _client.deleteCheckIn(request);
}

/// Check-ins over Connect/gRPC-Web.
class GrpcCheckInApi implements CheckInApi {
  GrpcCheckInApi({CheckInRpc? rpc}) : _rpc = rpc ?? GrpcCheckInRpc();

  static const _pageSize = 200;

  final CheckInRpc _rpc;

  @override
  Future<List<CheckIn>> listCheckIns({CheckInKind? kind}) async {
    try {
      final checkIns = <CheckIn>[];
      var pageToken = '';
      do {
        final response = await _rpc.listCheckIns(
          generated.ListCheckInsRequest(
            kind: kind == null
                ? generated.CheckInKind.CHECK_IN_KIND_UNSPECIFIED
                : _kindToProto(kind),
            pageSize: _pageSize,
            pageToken: pageToken,
          ),
        );
        checkIns.addAll(response.checkIns.map(checkInFromProto));
        pageToken = response.nextPageToken;
      } while (pageToken.isNotEmpty);
      return checkIns;
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CheckIn> getCheckIn(String id) async {
    try {
      final response = await _rpc.getCheckIn(
        generated.GetCheckInRequest(id: id),
      );
      return checkInFromProto(response.checkIn);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CheckInDefaults> getCheckInDefaults({
    CheckInKind kind = CheckInKind.manager,
  }) async {
    try {
      final response = await _rpc.getCheckInDefaults(
        generated.GetCheckInDefaultsRequest(kind: _kindToProto(kind)),
      );
      return checkInDefaultsFromProto(response);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CheckIn> createCheckIn(CheckInDraft draft) async {
    try {
      final response = await _rpc.createCheckIn(
        generated.CreateCheckInRequest(
          kind: _kindToProto(draft.kind),
          periodStart: _isoDate(draft.periodStart),
          periodEnd: _isoDate(draft.periodEnd),
          audience: draft.kind == CheckInKind.manager
              ? _audienceToProto(draft.audience)
              : generated.CheckInAudience.CHECK_IN_AUDIENCE_UNSPECIFIED,
          focusNotes: draft.focusNotes,
        ),
      );
      return checkInFromProto(response.checkIn);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CheckIn> updateCheckIn(
    CheckIn checkIn, {
    CheckInSummarySource source = CheckInSummarySource.manual,
    bool overwriteManualEdits = false,
  }) async {
    try {
      final response = await _rpc.updateCheckIn(
        generated.UpdateCheckInRequest(
          id: checkIn.id,
          periodStart: _isoDate(checkIn.periodStart),
          periodEnd: _isoDate(checkIn.periodEnd),
          audience: checkIn.kind == CheckInKind.manager
              ? _audienceToProto(checkIn.audience)
              : generated.CheckInAudience.CHECK_IN_AUDIENCE_UNSPECIFIED,
          focusNotes: checkIn.focusNotes,
          additionalContext: checkIn.additionalContext,
          summaryMarkdown: checkIn.summaryMarkdown,
          summaryModel: checkIn.summaryModel ?? '',
          promptVersion: checkIn.promptVersion,
          summarySource: _summarySourceToProto(source),
          overwriteManualEdits: overwriteManualEdits,
        ),
      );
      return checkInFromProto(response.checkIn);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CheckInPrompt> buildPrompt(String id) async {
    try {
      final response = await _rpc.buildPrompt(
        generated.BuildCheckInPromptRequest(id: id),
      );
      return CheckInPrompt(
        prompt: response.prompt,
        variant: promptVariantFromProto(response.variant),
        promptVersion: response.promptVersion.isEmpty
            ? 'v1'
            : response.promptVersion,
      );
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CheckIn> finalizeCheckIn(String id) async {
    try {
      final response = await _rpc.finalizeCheckIn(
        generated.FinalizeCheckInRequest(id: id),
      );
      return checkInFromProto(response.checkIn);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteCheckIn(String id) async {
    try {
      await _rpc.deleteCheckIn(generated.DeleteCheckInRequest(id: id));
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  CheckInFailure _failure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The service is unreachable. Check that the server is running.',
      unauthenticated: 'Sign in again to manage check-ins.',
      notFound: 'That check-in no longer exists.',
      failedPrecondition:
          'That check-in cannot be changed in its current state.',
    );
    return CheckInFailure(text.message, field: text.field);
  }
}

/// Maps the wire check-in onto the UI model.
CheckIn checkInFromProto(generated.CheckIn checkIn) => CheckIn(
  id: checkIn.id,
  kind: _kindFromProto(checkIn.kind),
  periodStart: DateTime.parse(checkIn.periodStart),
  periodEnd: DateTime.parse(checkIn.periodEnd),
  state: _stateFromProto(checkIn.state),
  audience: _audienceFromProto(checkIn.audience),
  focusNotes: checkIn.focusNotes,
  additionalContext: checkIn.additionalContext,
  summaryMarkdown: checkIn.summaryMarkdown,
  summaryModel: checkIn.summaryModel.isEmpty ? null : checkIn.summaryModel,
  promptVersion: checkIn.promptVersion.isEmpty ? 'v1' : checkIn.promptVersion,
  generationPrompt: checkIn.generationPrompt,
  previousSummaryMarkdown: checkIn.previousSummaryMarkdown,
  totals: checkInTotalsFromProto(checkIn.totals),
  createdAt: checkIn.createdAt.toDateTime(),
  updatedAt: checkIn.hasUpdatedAt() ? checkIn.updatedAt.toDateTime() : null,
);

CheckInTotals checkInTotalsFromProto(generated.CheckInTotals totals) {
  final supportByPerson = _totalsMap(totals.supportByPerson);
  return CheckInTotals(
    minutes: _minutes(totals.total),
    byCategory: _totalsMap(totals.byCategory),
    bySubcategory: _totalsMap(totals.bySubcategory),
    supportByPerson: supportByPerson,
    supportMinutes: CheckInTotals.effectiveSupportMinutes(
      _minutes(totals.supportDuration),
      supportByPerson,
    ),
    supportInteractions: CheckInTotals.effectiveSupportInteractions(
      totals.supportInteractions,
      supportByPerson,
    ),
  );
}

Map<String, int> _totalsMap(Iterable<generated.CheckInTotal> totals) => {
  for (final total in totals) total.key: _minutes(total.duration),
};

CheckInDefaults checkInDefaultsFromProto(
  generated.GetCheckInDefaultsResponse response,
) => CheckInDefaults(
  periodStart: DateTime.parse(response.periodStart),
  periodEnd: DateTime.parse(response.periodEnd),
  lastFinalCheckInId: response.lastFinalCheckInId,
);

int _minutes(duration.Duration value) => value.seconds.toInt() ~/ 60;

generated.CheckInKind _kindToProto(CheckInKind kind) => switch (kind) {
  CheckInKind.manager => generated.CheckInKind.CHECK_IN_KIND_MANAGER,
  CheckInKind.personal => generated.CheckInKind.CHECK_IN_KIND_PERSONAL,
};

CheckInKind _kindFromProto(generated.CheckInKind kind) => switch (kind) {
  generated.CheckInKind.CHECK_IN_KIND_PERSONAL => CheckInKind.personal,
  _ => CheckInKind.manager,
};

generated.CheckInAudience _audienceToProto(CheckInAudience? audience) =>
    switch (audience) {
      CheckInAudience.oneOnOne =>
        generated.CheckInAudience.CHECK_IN_AUDIENCE_ONE_ON_ONE,
      CheckInAudience.performanceReview =>
        generated.CheckInAudience.CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW,
      null => generated.CheckInAudience.CHECK_IN_AUDIENCE_UNSPECIFIED,
    };

CheckInAudience? _audienceFromProto(generated.CheckInAudience audience) =>
    switch (audience) {
      generated.CheckInAudience.CHECK_IN_AUDIENCE_ONE_ON_ONE =>
        CheckInAudience.oneOnOne,
      generated.CheckInAudience.CHECK_IN_AUDIENCE_PERFORMANCE_REVIEW =>
        CheckInAudience.performanceReview,
      _ => null,
    };

generated.CheckInSummarySource _summarySourceToProto(
  CheckInSummarySource source,
) => switch (source) {
  CheckInSummarySource.manual =>
    generated.CheckInSummarySource.CHECK_IN_SUMMARY_SOURCE_MANUAL,
  CheckInSummarySource.generated =>
    generated.CheckInSummarySource.CHECK_IN_SUMMARY_SOURCE_GENERATED,
};

CheckInState _stateFromProto(generated.CheckInState state) => switch (state) {
  generated.CheckInState.CHECK_IN_STATE_GENERATED => CheckInState.generated,
  generated.CheckInState.CHECK_IN_STATE_EDITED => CheckInState.edited,
  generated.CheckInState.CHECK_IN_STATE_FINAL => CheckInState.final_,
  _ => CheckInState.draft,
};

String _isoDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
