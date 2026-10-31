import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/src/generated/categories.pbenum.dart' as categories;
import 'package:wdid_web/src/generated/check_ins.pb.dart' as check_in_messages;
import 'package:wdid_web/src/generated/check_ins.pbenum.dart'
    as generated_check_ins;
import 'package:wdid_web/src/generated/summaries.pbgrpc.dart' as generated;

class FakeSummaryRpc implements SummaryRpc {
  Object? error;
  generated.GetPeriodReportResponse response =
      generated.GetPeriodReportResponse();
  generated.GetPeriodReportRequest? request;

  generated.BuildExportResponse exportResponse =
      generated.BuildExportResponse();
  generated.BuildExportRequest? exportRequest;

  generated.BuildPromptResponse promptResponse =
      generated.BuildPromptResponse();
  generated.BuildPromptRequest? promptRequest;

  generated.GetPromptTemplateResponse templateResponse =
      generated.GetPromptTemplateResponse();
  generated.GetPromptTemplateRequest? templateRequest;

  generated.GenerateSummaryRequest? generateRequest;
  List<generated.GenerateSummaryDelta> generationDeltas = const [];
  GrpcError? generationError;

  generated.RefineSummaryRequest? refineRequest;
  List<generated.GenerateSummaryDelta> refineDeltas = const [];
  GrpcError? refineError;

  generated.RevertSummaryRequest? revertRequest;
  generated.RevertSummaryResponse revertResponse =
      generated.RevertSummaryResponse();
  GrpcError? revertError;

  @override
  Future<generated.GetPeriodReportResponse> getPeriodReport(
    generated.GetPeriodReportRequest request,
  ) async {
    this.request = request;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<generated.BuildExportResponse> buildExport(
    generated.BuildExportRequest request,
  ) async {
    exportRequest = request;
    if (error != null) throw error!;
    return exportResponse;
  }

  @override
  Future<generated.BuildPromptResponse> buildPrompt(
    generated.BuildPromptRequest request,
  ) async {
    promptRequest = request;
    if (error != null) throw error!;
    return promptResponse;
  }

  @override
  Future<generated.GetPromptTemplateResponse> getPromptTemplate(
    generated.GetPromptTemplateRequest request,
  ) async {
    templateRequest = request;
    if (error != null) throw error!;
    return templateResponse;
  }

  @override
  Stream<generated.GenerateSummaryDelta> generateSummary(
    generated.GenerateSummaryRequest request,
  ) async* {
    generateRequest = request;
    for (final delta in generationDeltas) {
      yield delta;
    }
    if (generationError != null) throw generationError!;
  }

  @override
  Stream<generated.GenerateSummaryDelta> refineSummary(
    generated.RefineSummaryRequest request,
  ) async* {
    refineRequest = request;
    for (final delta in refineDeltas) {
      yield delta;
    }
    if (refineError != null) throw refineError!;
  }

  @override
  Future<generated.RevertSummaryResponse> revertSummary(
    generated.RevertSummaryRequest request,
  ) async {
    revertRequest = request;
    if (revertError != null) throw revertError!;
    return revertResponse;
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
    supportDuration: minutes(30),
    supportInteractions: 1,
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
      expect(report.supportMinutes, 30);
      expect(report.supportInteractions, 1);
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

  test('buildExport sends the scope and maps the four bundle files', () async {
    final rpc = FakeSummaryRpc()
      ..exportResponse = generated.BuildExportResponse(
        directory: 'wdid-export-2026-10-19_2026-10-25',
        files: [
          generated.ExportFile(name: 'summary.md', content: '# report'),
          generated.ExportFile(name: 'data.json', content: '{}'),
          generated.ExportFile(name: 'entries.csv', content: 'date,minutes\n'),
          generated.ExportFile(name: 'support.csv', content: 'person,mode\n'),
        ],
      );

    final bundle = await GrpcSummaryApi(rpc: rpc).buildExport(
      fromDate: '2026-10-19',
      toDate: '2026-10-25',
      checkInId: 'checkin-1',
    );

    expect(rpc.exportRequest!.fromDate, '2026-10-19');
    expect(rpc.exportRequest!.toDate, '2026-10-25');
    expect(rpc.exportRequest!.checkInId, 'checkin-1');
    expect(bundle.directory, 'wdid-export-2026-10-19_2026-10-25');
    expect(bundle.files.keys, [
      'summary.md',
      'data.json',
      'entries.csv',
      'support.csv',
    ]);
    expect(bundle.files['summary.md'], '# report');
  });

  test('buildPrompt sends the variant and maps the versioned prompt', () async {
    final rpc = FakeSummaryRpc()
      ..promptResponse = generated.BuildPromptResponse(
        prompt: 'instruction\n\n# wdid work report',
        promptVersion: 'v1',
        variant: generated_check_ins
            .CheckInPromptVariant
            .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW,
      );

    final prompt = await GrpcSummaryApi(rpc: rpc).buildPrompt(
      fromDate: '2026-10-19',
      toDate: '2026-10-25',
      checkInId: 'checkin-1',
      variant: CheckInPromptVariant.managerPerformanceReview,
    );

    expect(rpc.promptRequest!.checkInId, 'checkin-1');
    expect(
      rpc.promptRequest!.variant,
      generated_check_ins
          .CheckInPromptVariant
          .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW,
    );
    expect(prompt.prompt, 'instruction\n\n# wdid work report');
    expect(prompt.promptVersion, 'v1');
    expect(prompt.variant, CheckInPromptVariant.managerPerformanceReview);
  });

  test('generateSummary maps streamed text and the final check-in', () async {
    final createdAt = Timestamp.fromDateTime(DateTime.utc(2026, 10, 19, 12));
    final rpc = FakeSummaryRpc()
      ..generationDeltas = [
        generated.GenerateSummaryDelta(text: '## Highlights\n'),
        generated.GenerateSummaryDelta(text: '- Cut invoicing\n'),
        generated.GenerateSummaryDelta(
          model: 'provider-model',
          promptVersion: 'v1',
          checkIn: check_in_messages.CheckIn(
            id: 'checkin-1',
            kind: generated_check_ins.CheckInKind.CHECK_IN_KIND_MANAGER,
            periodStart: '2026-10-19',
            periodEnd: '2026-10-19',
            summaryMarkdown: '## Highlights\n- Cut invoicing',
            summaryModel: 'provider-model',
            promptVersion: 'v1',
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        ),
      ];

    final deltas = await GrpcSummaryApi(rpc: rpc)
        .generateSummary('checkin-1', overwriteManualEdits: true)
        .toList();

    expect(rpc.generateRequest!.checkInId, 'checkin-1');
    expect(rpc.generateRequest!.overwriteManualEdits, isTrue);
    expect(deltas, hasLength(3));
    expect(deltas.first.text, '## Highlights\n');
    expect(deltas[1].text, '- Cut invoicing\n');
    expect(deltas.last.isFinal, isTrue);
    expect(deltas.last.checkIn!.summaryMarkdown, contains('Cut invoicing'));
    expect(deltas.last.checkIn!.summaryModel, 'provider-model');
    expect(deltas.last.model, 'provider-model');
    expect(deltas.last.promptVersion, 'v1');
  });

  test('generateSummary surfaces a provider failure as a retryable error', () async {
    final rpc = FakeSummaryRpc()
      ..generationDeltas = [generated.GenerateSummaryDelta(text: 'partial')]
      ..generationError = GrpcError.unavailable('provider offline');

    expect(
      () => GrpcSummaryApi(
        rpc: rpc,
      ).generateSummary('checkin-1').toList(),
      throwsA(
        isA<SummaryFailure>().having(
          (failure) => failure.message,
          'message',
          contains('existing summary is unchanged'),
        ),
      ),
    );
  });

  test(
    'refineSummary sends the feedback and maps the refined stream',
    () async {
      final createdAt = Timestamp.fromDateTime(DateTime.utc(2026, 10, 19, 12));
      final rpc = FakeSummaryRpc()
        ..refineDeltas = [
          generated.GenerateSummaryDelta(text: '## Refined\n'),
          generated.GenerateSummaryDelta(
            model: 'provider-model',
            promptVersion: 'custom',
            checkIn: check_in_messages.CheckIn(
              id: 'checkin-1',
              kind: generated_check_ins.CheckInKind.CHECK_IN_KIND_MANAGER,
              periodStart: '2026-10-19',
              periodEnd: '2026-10-19',
              summaryMarkdown: '## Refined\n- Tighter',
              summaryModel: 'provider-model',
              promptVersion: 'custom',
              generationPrompt: 'user:\nrefine transcript',
              previousSummaryMarkdown: '## Hand edit\n- Mine',
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          ),
        ];

      final deltas = await GrpcSummaryApi(rpc: rpc)
          .refineSummary('checkin-1', 'Make it shorter')
          .toList();

      expect(rpc.refineRequest!.checkInId, 'checkin-1');
      expect(rpc.refineRequest!.feedback, 'Make it shorter');
      expect(deltas, hasLength(2));
      expect(deltas.first.text, '## Refined\n');
      expect(deltas.last.isFinal, isTrue);
      expect(deltas.last.checkIn!.summaryMarkdown, '## Refined\n- Tighter');
      expect(deltas.last.checkIn!.promptVersion, 'custom');
      expect(deltas.last.checkIn!.generationPrompt, 'user:\nrefine transcript');
      expect(
        deltas.last.checkIn!.previousSummaryMarkdown,
        '## Hand edit\n- Mine',
      );
      expect(deltas.last.model, 'provider-model');
    },
  );

  test(
    'refineSummary surfaces a provider failure as a retryable error',
    () async {
      final rpc = FakeSummaryRpc()
        ..refineDeltas = [generated.GenerateSummaryDelta(text: 'partial')]
        ..refineError = GrpcError.unavailable('provider offline');

      expect(
        () =>
            GrpcSummaryApi(rpc: rpc)
                .refineSummary('checkin-1', 'Tighten it')
                .toList(),
        throwsA(
          isA<SummaryFailure>().having(
            (failure) => failure.message,
            'message',
            contains('existing summary is unchanged'),
          ),
        ),
      );
    },
  );

  test(
    'revertSummary maps the returned check-in and clears the slot',
    () async {
      final createdAt = Timestamp.fromDateTime(DateTime.utc(2026, 10, 19, 12));
      final rpc = FakeSummaryRpc()
        ..revertResponse = generated.RevertSummaryResponse(
          checkIn: check_in_messages.CheckIn(
            id: 'checkin-1',
            kind: generated_check_ins.CheckInKind.CHECK_IN_KIND_MANAGER,
            periodStart: '2026-10-19',
            periodEnd: '2026-10-19',
            summaryMarkdown: '## Previous\n- Restored',
            previousSummaryMarkdown: '',
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );

      final checkIn = await GrpcSummaryApi(rpc: rpc).revertSummary('checkin-1');

      expect(rpc.revertRequest!.checkInId, 'checkin-1');
      expect(checkIn.summaryMarkdown, '## Previous\n- Restored');
      expect(checkIn.previousSummaryMarkdown, isEmpty);
    },
  );

  test(
    'revertSummary surfaces a state rejection as a summary failure',
    () async {
      final rpc = FakeSummaryRpc()
        ..revertError = GrpcError.failedPrecondition('nothing to revert');

      expect(
        () => GrpcSummaryApi(rpc: rpc).revertSummary('checkin-1'),
        throwsA(
          isA<SummaryFailure>().having(
            (failure) => failure.message,
            'message',
            contains('nothing to revert'),
          ),
        ),
      );
    },
  );

  test('getPromptTemplate previews the service-owned instruction', () async {
    final rpc = FakeSummaryRpc()
      ..templateResponse = generated.GetPromptTemplateResponse(
        template: 'You are preparing a personal review.',
        promptVersion: 'v1',
        variant: generated_check_ins
            .CheckInPromptVariant
            .CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW,
      );

    final template = await GrpcSummaryApi(
      rpc: rpc,
    ).getPromptTemplate(CheckInPromptVariant.personalReview);

    expect(
      rpc.templateRequest!.variant,
      generated_check_ins
          .CheckInPromptVariant
          .CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW,
    );
    expect(template.template, 'You are preparing a personal review.');
    expect(template.promptVersion, 'v1');
    expect(template.variant, CheckInPromptVariant.personalReview);
  });
}
