import '../models/period_report.dart';
import 'time_utils.dart';

/// Presentation-only shapes for the service-owned period report.
class AllocationSlice {
  const AllocationSlice({
    required this.key,
    required this.label,
    required this.minutes,
    this.tooltip,
  });

  final String key;
  final String label;
  final int minutes;

  /// Optional breakdown shown on hover, such as a category's subcategories.
  final String? tooltip;

  double shareOf(int total) => total == 0 ? 0 : minutes / total;
}

/// Maps an authoritative period report onto the bars Today renders. The
/// category's subcategory allocation becomes its hover breakdown.
List<AllocationSlice> allocationForReport(PeriodReport report) {
  final byCategory = <String, List<SubcategoryAllocation>>{};
  for (final subcategory in report.subcategories) {
    byCategory.putIfAbsent(subcategory.categoryId, () => []).add(subcategory);
  }

  return [
    for (final category in report.categories)
      AllocationSlice(
        key: category.categoryId,
        label: category.name,
        minutes: category.minutes,
        tooltip: _subcategoryBreakdown(byCategory[category.categoryId]),
      ),
  ];
}

String? _subcategoryBreakdown(List<SubcategoryAllocation>? subcategories) {
  if (subcategories == null || subcategories.isEmpty) return null;
  return subcategories
      .map(
        (subcategory) =>
            '${subcategory.name} · ${formatDuration(subcategory.minutes)}',
      )
      .join('\n');
}
