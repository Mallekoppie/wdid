import 'dart:async';

import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/check_in.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/models/export_bundle.dart';
import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';

/// In-memory period-report service used by widget and state tests.
class FakeSummaryApi implements SummaryApi {
  FakeSummaryApi({PeriodReport? report, this.echoDates = false})
    : report =
          report ??
          const PeriodReport(
            fromDate: '2026-10-19',
            toDate: '2026-10-25',
            totalMinutes: 90,
            entryCount: 2,
            categories: [
              CategoryAllocation(
                categoryId: 'cat-1',
                name: 'Initiatives',
                role: CategoryRole.initiative,
                minutes: 60,
                entryCount: 1,
              ),
              CategoryAllocation(
                categoryId: 'cat-2',
                name: 'Support',
                role: CategoryRole.support,
                minutes: 30,
                entryCount: 1,
              ),
            ],
            subcategories: [
              SubcategoryAllocation(
                subcategoryId: 'sub-1',
                categoryId: 'cat-1',
                name: 'Billing migration',
                minutes: 60,
                entryCount: 1,
              ),
              SubcategoryAllocation(
                subcategoryId: 'sub-2',
                categoryId: 'cat-2',
                name: 'Unblock',
                minutes: 30,
                entryCount: 1,
              ),
            ],
          );

  PeriodReport report;

  /// When true the returned report carries the requested dates, which is what
  /// a real service does and what a live review checks before rendering.
  final bool echoDates;
  Object? failure;
  int calls = 0;
  String lastFrom = '';
  String lastTo = '';
  bool lastCurrentWeek = false;

  /// Every request in call order, so a test can pick out the non-week report
  /// a screen asked for.
  final List<({String from, String to, bool currentWeek})> requests = [];

  /// When set, the next call waits for it, which lets tests observe loading.
  Completer<PeriodReport>? gate;

  /// Export/prompt fixtures and the last request, so widget tests can verify
  /// the selected period or check-in reaches the service.
  ExportBundle bundle = const ExportBundle(
    directory: 'wdid-export-2026-10-19_2026-10-25',
    files: {
      'summary.md': '# wdid work report — 2026-10-19 to 2026-10-25\n',
      'data.json': '{}',
      'entries.csv': 'date,minutes\n',
      'support.csv': 'person,mode\n',
    },
  );
  String prompt = 'prompt:\n\n# wdid work report';
  String lastExportFrom = '';
  String lastExportTo = '';
  String lastExportCheckInId = '';
  String lastPromptFrom = '';
  String lastPromptTo = '';
  String lastPromptCheckInId = '';
  CheckInPromptVariant? lastPromptVariant;
  Object? exportFailure;

  /// Generation fixtures. The stream yields [generationDeltas] in order and
  /// then throws [generationFailure], which lets a test model a provider that
  /// fails after emitting partial text.
  List<SummaryDelta> generationDeltas = const [];
  Object? generationFailure;
  int generateCalls = 0;
  String lastGenerateCheckInId = '';
  bool lastOverwriteManualEdits = false;
  PromptTemplate? template;
  CheckInPromptVariant? lastTemplateVariant;

  @override
  Future<PeriodReport> getPeriodReport({
    String fromDate = '',
    String toDate = '',
    bool currentWeek = false,
  }) async {
    calls++;
    lastFrom = fromDate;
    lastTo = toDate;
    lastCurrentWeek = currentWeek;
    requests.add((from: fromDate, to: toDate, currentWeek: currentWeek));
    if (gate != null) {
      final pending = gate!;
      gate = null;
      return pending.future;
    }
    if (failure != null) throw failure!;
    if (!echoDates) return report;
    return PeriodReport(
      fromDate: fromDate,
      toDate: toDate,
      totalMinutes: report.totalMinutes,
      entryCount: report.entryCount,
      categories: report.categories,
      subcategories: report.subcategories,
      supportPeople: report.supportPeople,
      supportModes: report.supportModes,
      weeks: report.weeks,
      notes: report.notes,
      milestoneProgress: report.milestoneProgress,
    );
  }

  @override
  Future<ExportBundle> buildExport({
    String fromDate = '',
    String toDate = '',
    String checkInId = '',
  }) async {
    lastExportFrom = fromDate;
    lastExportTo = toDate;
    lastExportCheckInId = checkInId;
    if (exportFailure != null) throw exportFailure!;
    return bundle;
  }

  @override
  Future<CheckInPrompt> buildPrompt({
    String fromDate = '',
    String toDate = '',
    String checkInId = '',
    CheckInPromptVariant? variant,
  }) async {
    lastPromptFrom = fromDate;
    lastPromptTo = toDate;
    lastPromptCheckInId = checkInId;
    lastPromptVariant = variant;
    return CheckInPrompt(
      prompt: prompt,
      variant: variant ?? CheckInPromptVariant.managerOneOnOne,
      promptVersion: 'v1',
    );
  }

  @override
  Future<PromptTemplate> getPromptTemplate(
    CheckInPromptVariant variant,
  ) async {
    lastTemplateVariant = variant;
    return template ??
        PromptTemplate(
          template: 'You are preparing a summary for a check-in.',
          variant: variant,
          promptVersion: 'v1',
        );
  }

  @override
  Stream<SummaryDelta> generateSummary(
    String checkInId, {
    bool overwriteManualEdits = false,
  }) async* {
    generateCalls++;
    lastGenerateCheckInId = checkInId;
    lastOverwriteManualEdits = overwriteManualEdits;
    for (final delta in generationDeltas) {
      yield delta;
    }
    if (generationFailure != null) throw generationFailure!;
  }
}
