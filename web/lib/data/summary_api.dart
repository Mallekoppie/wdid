import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;

import '../models/check_in.dart';
import '../models/enums.dart';
import '../models/export_bundle.dart';
import '../models/period_report.dart';
import '../models/taxonomy.dart';
import '../src/generated/categories.pbenum.dart' as categories_generated;
import '../src/generated/check_ins.pbenum.dart' as check_ins_generated;
import '../src/generated/summaries.pbgrpc.dart' as generated;
import 'checkin_api.dart';
import 'grpc_channel.dart';
import 'grpc_errors.dart';

/// A user-facing period-report failure.
class SummaryFailure extends ServiceFailure {
  const SummaryFailure(super.message, {super.field});
}

/// Authoritative period aggregation consumed by Today, initiatives, support
/// rollups and check-ins.
abstract class SummaryApi {
  /// Aggregates the inclusive local calendar dates [fromDate] and [toDate].
  ///
  /// When [currentWeek] is true, the service resolves the user's current week
  /// from their timezone and week-start setting and the dates are ignored.
  Future<PeriodReport> getPeriodReport({
    String fromDate = '',
    String toDate = '',
    bool currentWeek = false,
  });

  /// Builds the export bundle for a period or, when [checkInId] is set, for
  /// that check-in's stored period. The files are returned to the caller and
  /// are never written to the database directory.
  Future<ExportBundle> buildExport({
    String fromDate = '',
    String toDate = '',
    String checkInId = '',
  });

  /// The versioned prompt block followed by summary.md for the same scope.
  Future<CheckInPrompt> buildPrompt({
    String fromDate = '',
    String toDate = '',
    String checkInId = '',
    CheckInPromptVariant? variant,
  });

  /// The versioned instruction alone, for the Settings preview. The text is
  /// service-owned.
  Future<PromptTemplate> getPromptTemplate(CheckInPromptVariant variant);

  /// Streams model output into the check-in's summary. Deltas arrive as text;
  /// the final delta carries the persisted check-in. A failure ends the stream
  /// without changing the stored summary.
  Stream<SummaryDelta> generateSummary(
    String checkInId, {
    bool overwriteManualEdits = false,
  });
}

/// The narrow generated-client surface, separated so field mapping and error
/// translation can be tested without a network channel.
abstract class SummaryRpc {
  Future<generated.GetPeriodReportResponse> getPeriodReport(
    generated.GetPeriodReportRequest request,
  );

  Future<generated.BuildExportResponse> buildExport(
    generated.BuildExportRequest request,
  );

  Future<generated.BuildPromptResponse> buildPrompt(
    generated.BuildPromptRequest request,
  );

  Future<generated.GetPromptTemplateResponse> getPromptTemplate(
    generated.GetPromptTemplateRequest request,
  );

  Stream<generated.GenerateSummaryDelta> generateSummary(
    generated.GenerateSummaryRequest request,
  );
}

/// The generated Connect client over gRPC-Web.
class GrpcSummaryRpc implements SummaryRpc {
  GrpcSummaryRpc({
    generated.SummaryServiceClient? client,
    String? Function()? token,
  }) : _client =
           client ??
           generated.SummaryServiceClient(
             openAppChannel(),
             interceptors: [bearerInterceptor(token ?? (() => null))],
           );

  final generated.SummaryServiceClient _client;

  @override
  Future<generated.GetPeriodReportResponse> getPeriodReport(
    generated.GetPeriodReportRequest request,
  ) => _client.getPeriodReport(request);

  @override
  Future<generated.BuildExportResponse> buildExport(
    generated.BuildExportRequest request,
  ) => _client.buildExport(request);

  @override
  Future<generated.BuildPromptResponse> buildPrompt(
    generated.BuildPromptRequest request,
  ) => _client.buildPrompt(request);

  @override
  Future<generated.GetPromptTemplateResponse> getPromptTemplate(
    generated.GetPromptTemplateRequest request,
  ) => _client.getPromptTemplate(request);

  @override
  Stream<generated.GenerateSummaryDelta> generateSummary(
    generated.GenerateSummaryRequest request,
  ) => _client.generateSummary(request);
}

/// Period reports over Connect/gRPC-Web.
class GrpcSummaryApi implements SummaryApi {
  GrpcSummaryApi({SummaryRpc? rpc}) : _rpc = rpc ?? GrpcSummaryRpc();

  final SummaryRpc _rpc;

  @override
  Future<PeriodReport> getPeriodReport({
    String fromDate = '',
    String toDate = '',
    bool currentWeek = false,
  }) async {
    try {
      final response = await _rpc.getPeriodReport(
        generated.GetPeriodReportRequest(
          fromDate: fromDate,
          toDate: toDate,
          currentWeek: currentWeek,
        ),
      );
      return periodReportFromProto(response.report);
    } on GrpcError catch (error) {
      final text = describeGrpcError(
        error,
        unavailable:
            'The service is unreachable. Check that the server is running.',
        unauthenticated: 'Sign in again to see your report.',
      );
      throw SummaryFailure(text.message, field: text.field);
    }
  }

  @override
  Future<ExportBundle> buildExport({
    String fromDate = '',
    String toDate = '',
    String checkInId = '',
  }) async {
    try {
      final response = await _rpc.buildExport(
        generated.BuildExportRequest(
          fromDate: fromDate,
          toDate: toDate,
          checkInId: checkInId,
        ),
      );
      return exportBundleFromProto(response);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CheckInPrompt> buildPrompt({
    String fromDate = '',
    String toDate = '',
    String checkInId = '',
    CheckInPromptVariant? variant,
  }) async {
    try {
      final response = await _rpc.buildPrompt(
        generated.BuildPromptRequest(
          fromDate: fromDate,
          toDate: toDate,
          checkInId: checkInId,
          variant: _promptVariantToProto(variant),
        ),
      );
      return CheckInPrompt(
        prompt: response.prompt,
        variant: _promptVariantFromProto(response.variant),
        promptVersion: response.promptVersion.isEmpty
            ? 'v1'
            : response.promptVersion,
      );
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<PromptTemplate> getPromptTemplate(
    CheckInPromptVariant variant,
  ) async {
    try {
      final response = await _rpc.getPromptTemplate(
        generated.GetPromptTemplateRequest(
          variant: _promptVariantToProto(variant),
        ),
      );
      return PromptTemplate(
        template: response.template,
        variant: _promptVariantFromProto(response.variant),
        promptVersion: response.promptVersion.isEmpty
            ? 'v1'
            : response.promptVersion,
      );
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Stream<SummaryDelta> generateSummary(
    String checkInId, {
    bool overwriteManualEdits = false,
  }) async* {
    try {
      final stream = _rpc.generateSummary(
        generated.GenerateSummaryRequest(
          checkInId: checkInId,
          overwriteManualEdits: overwriteManualEdits,
        ),
      );
      await for (final delta in stream) {
        yield SummaryDelta(
          text: delta.text,
          checkIn: delta.hasCheckIn() ? checkInFromProto(delta.checkIn) : null,
          model: delta.model,
          promptVersion: delta.promptVersion,
        );
      }
    } on GrpcError catch (error) {
      throw _generationFailure(error);
    }
  }

  SummaryFailure _failure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The service is unreachable. Check that the server is running.',
      unauthenticated: 'Sign in again to build the export.',
      notFound: 'That check-in no longer exists.',
    );
    return SummaryFailure(text.message, field: text.field);
  }

  /// A generation failure keeps its provider-side detail where it is safe to
  /// show: the existing summary is never lost and the message names the retry.
  SummaryFailure _generationFailure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The AI provider could not complete the summary. The existing '
          'summary is unchanged.',
      unauthenticated: 'Sign in again to generate a summary.',
      notFound: 'That check-in no longer exists.',
      failedPrecondition: 'This check-in cannot be generated right now.',
    );
    return SummaryFailure(text.message, field: text.field);
  }
}

/// Maps a generated bundle onto the UI model. Exposed so tests can check the
/// file set without a network channel.
ExportBundle exportBundleFromProto(generated.BuildExportResponse response) {
  return ExportBundle(
    directory: response.directory,
    files: {for (final file in response.files) file.name: file.content},
  );
}

check_ins_generated.CheckInPromptVariant _promptVariantToProto(
  CheckInPromptVariant? variant,
) => switch (variant) {
  CheckInPromptVariant.managerOneOnOne =>
    check_ins_generated
        .CheckInPromptVariant
        .CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE,
  CheckInPromptVariant.managerPerformanceReview =>
    check_ins_generated
        .CheckInPromptVariant
        .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW,
  CheckInPromptVariant.personalReview =>
    check_ins_generated
        .CheckInPromptVariant
        .CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW,
  null =>
    check_ins_generated
        .CheckInPromptVariant
        .CHECK_IN_PROMPT_VARIANT_UNSPECIFIED,
};

CheckInPromptVariant _promptVariantFromProto(
  check_ins_generated.CheckInPromptVariant variant,
) => switch (variant) {
  check_ins_generated
      .CheckInPromptVariant
      .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW =>
    CheckInPromptVariant.managerPerformanceReview,
  check_ins_generated
      .CheckInPromptVariant
      .CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW =>
    CheckInPromptVariant.personalReview,
  _ => CheckInPromptVariant.managerOneOnOne,
};

/// Maps the wire report onto the UI model. Exposed so tests can check the
/// mapping without a network channel.
PeriodReport periodReportFromProto(generated.PeriodReport report) {
  return PeriodReport(
    fromDate: report.fromDate,
    toDate: report.toDate,
    totalMinutes: _minutes(report.total),
    entryCount: report.entryCount,
    supportMinutes: _minutes(report.supportDuration),
    supportInteractions: report.supportInteractions,
    categories: [
      for (final category in report.categories)
        CategoryAllocation(
          categoryId: category.categoryId,
          name: category.name,
          role: _roleFromProto(category.role),
          minutes: _minutes(category.duration),
          entryCount: category.entryCount,
        ),
    ],
    subcategories: [
      for (final subcategory in report.subcategories)
        SubcategoryAllocation(
          subcategoryId: subcategory.subcategoryId,
          categoryId: subcategory.categoryId,
          name: subcategory.name,
          minutes: _minutes(subcategory.duration),
          entryCount: subcategory.entryCount,
          lastActivityDate: subcategory.lastActivityDate,
          lastActivityDescription: subcategory.lastActivityDescription,
        ),
    ],
    supportPeople: [
      for (final person in report.supportPeople)
        SupportPersonAllocation(
          person: person.person,
          minutes: _minutes(person.duration),
          interactions: person.interactions,
        ),
    ],
    supportModes: [
      for (final mode in report.supportModes)
        SupportModeAllocation(
          subcategoryId: mode.subcategoryId,
          name: mode.name,
          minutes: _minutes(mode.duration),
          interactions: mode.interactions,
        ),
    ],
    weeks: [
      for (final week in report.weeks)
        WeekRhythm(
          weekStartDate: week.weekStartDate,
          minutes: _minutes(week.duration),
          topCategoryId: week.topCategoryId,
          topCategoryName: week.topCategoryName,
        ),
    ],
    notes: [
      for (final note in report.notes)
        PeriodNote(
          id: note.id,
          date: note.date,
          subcategoryId: note.subcategoryId,
          text: note.text,
          createdAt: note.createdAt.toDateTime(),
        ),
    ],
    milestoneProgress: [
      for (final progress in report.milestoneProgress)
        MilestoneProgress(
          subcategoryId: progress.subcategoryId,
          total: progress.total,
          done: progress.done,
        ),
    ],
  );
}

int _minutes(duration.Duration value) => value.seconds.toInt() ~/ 60;

CategoryRole _roleFromProto(categories_generated.CategoryRole role) {
  switch (role) {
    case categories_generated.CategoryRole.CATEGORY_ROLE_INITIATIVE:
      return CategoryRole.initiative;
    case categories_generated.CategoryRole.CATEGORY_ROLE_SUPPORT:
      return CategoryRole.support;
    default:
      return CategoryRole.other;
  }
}
