import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;

import '../models/period_report.dart';
import '../models/taxonomy.dart';
import '../src/generated/categories.pbenum.dart' as categories_generated;
import '../src/generated/summaries.pbgrpc.dart' as generated;
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
}

/// The narrow generated-client surface, separated so field mapping and error
/// translation can be tested without a network channel.
abstract class SummaryRpc {
  Future<generated.GetPeriodReportResponse> getPeriodReport(
    generated.GetPeriodReportRequest request,
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
}

/// Maps the wire report onto the UI model. Exposed so tests can check the
/// mapping without a network channel.
PeriodReport periodReportFromProto(generated.PeriodReport report) {
  return PeriodReport(
    fromDate: report.fromDate,
    toDate: report.toDate,
    totalMinutes: _minutes(report.total),
    entryCount: report.entryCount,
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
