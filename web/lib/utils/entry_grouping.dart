import '../models/work_entry.dart';
import 'time_utils.dart';

/// Groups work entries by their local day, newest day first. Entries inside a
/// day keep the input order, so a newest-first listing stays newest first.
Map<String, List<WorkEntry>> groupEntriesByLocalDay(
  Iterable<WorkEntry> entries,
) {
  final grouped = <String, List<WorkEntry>>{};
  for (final entry in entries) {
    final day = entry.localDate.isNotEmpty
        ? entry.localDate
        : isoDate(entry.startedLocal);
    grouped.putIfAbsent(day, () => []).add(entry);
  }
  final ordered = <String, List<WorkEntry>>{};
  for (final day in grouped.keys.toList()..sort((a, b) => b.compareTo(a))) {
    ordered[day] = grouped[day]!;
  }
  return ordered;
}
