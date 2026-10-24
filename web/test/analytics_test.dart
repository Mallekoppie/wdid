import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/utils/analytics.dart';

void main() {
  test('report allocation uses service categories and subcategory tooltips', () {
    const report = PeriodReport(
      fromDate: '2026-10-17',
      toDate: '2026-10-17',
      totalMinutes: 100,
      entryCount: 3,
      categories: [
        CategoryAllocation(
          categoryId: 'cat-init',
          name: 'Initiatives',
          role: CategoryRole.initiative,
          minutes: 60,
          entryCount: 1,
        ),
        CategoryAllocation(
          categoryId: 'cat-support',
          name: 'Support',
          role: CategoryRole.support,
          minutes: 30,
          entryCount: 1,
        ),
        CategoryAllocation(
          categoryId: 'cat-other',
          name: 'Meetings',
          role: CategoryRole.other,
          minutes: 10,
          entryCount: 1,
        ),
      ],
      subcategories: [
        SubcategoryAllocation(
          subcategoryId: 'sub-billing',
          categoryId: 'cat-init',
          name: 'Billing migration',
          minutes: 60,
          entryCount: 1,
        ),
      ],
    );

    final slices = allocationForReport(report);

    expect(slices.map((slice) => slice.label), [
      'Initiatives',
      'Support',
      'Meetings',
    ]);
    expect(slices.map((slice) => slice.minutes), [60, 30, 10]);
    expect(slices.first.tooltip, contains('Billing migration · 1h'));
  });
}
