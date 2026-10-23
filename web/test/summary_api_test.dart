import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/src/generated/categories.pbenum.dart' as categories;
import 'package:wdid_web/src/generated/summaries.pbgrpc.dart' as generated;

class FakeSummaryRpc implements SummaryRpc {
  Object? error;
  generated.GetPeriodReportResponse response =
      generated.GetPeriodReportResponse();
  generated.GetPeriodReportRequest? request;

  @override
  Future<generated.GetPeriodReportResponse> getPeriodReport(
    generated.GetPeriodReportRequest request,
  ) async {
    this.request = request;
    if (error != null) throw error!;
    return response;
  }
}

duration.Duration minutes(int value) =>
    duration.Duration(seconds: Int64(value * 60));

generated.PeriodReport protoReport() {
  final createdAt = Timestamp.fromDateTime(DateTime.utc(2026, 10, 19, 12));
  return generated.PeriodReport(
    fromDate: '2026-10-19',
    toDate: '2026-10-19',
    total: minutes(90),
    entryCount: 2,
    categories: [
      generated.CategoryAllocation(
        categoryId: 'cat-1',
        name: 'Initiatives',
        role: categories.CategoryRole.CATEGORY_ROLE_INITIATIVE,
        duration: minutes(60),
        entryCount: 1,
      ),
      generated.CategoryAllocation(
        categoryId: 'cat-2',
        name: 'Support',
        role: categories.CategoryRole.CATEGORY_ROLE_SUPPORT,
        duration: minutes(30),
        entryCount: 1,
      ),
    ],
    subcategories: [
      generated.SubcategoryAllocation(
        subcategoryId: 'sub-1',
        categoryId: 'cat-1',
        name: 'Billing migration',
        duration: minutes(60),
        entryCount: 1,
        lastActivityDate: '2026-10-19',
        lastActivityDescription: 'Backfill skeleton',
      ),
    ],
    supportPeople: [
      generated.SupportPersonAllocation(
        person: 'Priya',
        duration: minutes(30),
        interactions: 1,
      ),
    ],
    supportModes: [
      generated.SupportModeAllocation(
        subcategoryId: 'sub-2',
        name: 'Unblock',
        duration: minutes(30),
        interactions: 1,
      ),
    ],
    weeks: [
      generated.WeekRhythm(
        weekStartDate: '2026-10-19',
        duration: minutes(90),
        topCategoryId: 'cat-1',
        topCategoryName: 'Initiatives',
      ),
    ],
    notes: [
      generated.PeriodNote(
        id: 'note-1',
        date: '2026-10-19',
        text: 'Shipped the backfill',
        createdAt: createdAt,
      ),
    ],
  );
}

void main() {
  test(
    'getPeriodReport sends the range and maps the authoritative totals',
    () async {
      final rpc = FakeSummaryRpc()
        ..response = generated.GetPeriodReportResponse(report: protoReport());

      final report = await GrpcSummaryApi(rpc: rpc)
          .getPeriodReport(fromDate: '2026-10-19', toDate: '2026-10-19');

      expect(rpc.request!.fromDate, '2026-10-19');
      expect(rpc.request!.toDate, '2026-10-19');

      expect(report.fromDate, '2026-10-19');
      expect(report.toDate, '2026-10-19');
      expect(report.totalMinutes, 90);
      expect(report.entryCount, 2);
      expect(report.categories, hasLength(2));
      expect(report.categories.first.name, 'Initiatives');
      expect(report.categories.first.role, CategoryRole.initiative);
      expect(report.categories.first.minutes, 60);
      expect(report.categories.first.entryCount, 1);
      expect(report.categories.last.role, CategoryRole.support);
      expect(report.subcategories.single.name, 'Billing migration');
      expect(report.subcategories.single.lastActivityDate, '2026-10-19');
      expect(
        report.subcategories.single.lastActivityDescription,
        'Backfill skeleton',
      );
      expect(report.supportPeople.single.person, 'Priya');
      expect(report.supportPeople.single.minutes, 30);
      expect(report.supportPeople.single.interactions, 1);
      expect(report.supportModes.single.name, 'Unblock');
      expect(report.weeks.single.weekStartDate, '2026-10-19');
      expect(report.weeks.single.topCategoryName, 'Initiatives');
      expect(report.notes.single.id, 'note-1');
      expect(report.notes.single.date, '2026-10-19');
      expect(report.notes.single.createdAt, DateTime.utc(2026, 10, 19, 12));
    },
  );

  test('getPeriodReport can ask the server for its current week', () async {
    final rpc = FakeSummaryRpc()
      ..response = generated.GetPeriodReportResponse(report: protoReport());

    await GrpcSummaryApi(rpc: rpc).getPeriodReport(currentWeek: true);

    expect(rpc.request!.currentWeek, isTrue);
    expect(rpc.request!.fromDate, isEmpty);
    expect(rpc.request!.toDate, isEmpty);
  });

  test('an empty report maps to zero totals rather than an error', () async {
    final rpc = FakeSummaryRpc()
      ..response = generated.GetPeriodReportResponse(
        report: generated.PeriodReport(
          fromDate: '2026-01-01',
          toDate: '2026-01-07',
          weeks: [
            generated.WeekRhythm(weekStartDate: '2025-12-29'),
            generated.WeekRhythm(weekStartDate: '2026-01-05'),
          ],
        ),
      );

    final report = await GrpcSummaryApi(rpc: rpc)
        .getPeriodReport(fromDate: '2026-01-01', toDate: '2026-01-07');

    expect(report.totalMinutes, 0);
    expect(report.entryCount, 0);
    expect(report.categories, isEmpty);
    expect(report.supportPeople, isEmpty);
    expect(report.weeks, hasLength(2));
    expect(report.weeks.first.minutes, 0);
  });

  test('reports service failures with a user-facing message', () async {
    final rpc = FakeSummaryRpc()..error = GrpcError.unavailable('offline');

    expect(
      () =>
          GrpcSummaryApi(rpc: rpc)
              .getPeriodReport(fromDate: '2026-10-19', toDate: '2026-10-19'),
      throwsA(
        isA<SummaryFailure>().having(
          (failure) => failure.message,
          'message',
          contains('unreachable'),
        ),
      ),
    );
  });
}
