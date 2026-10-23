import 'dart:async';

import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';

/// In-memory period-report service used by widget and state tests.
class FakeSummaryApi implements SummaryApi {
  FakeSummaryApi({PeriodReport? report})
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
  Object? failure;
  int calls = 0;
  String lastFrom = '';
  String lastTo = '';
  bool lastCurrentWeek = false;

  /// When set, the next call waits for it, which lets tests observe loading.
  Completer<PeriodReport>? gate;

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
    if (gate != null) {
      final pending = gate!;
      gate = null;
      return pending.future;
    }
    if (failure != null) throw failure!;
    return report;
  }
}
