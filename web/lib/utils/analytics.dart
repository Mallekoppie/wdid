import '../models/enums.dart';
import '../models/initiative.dart';
import '../models/work_item.dart';
import 'time_utils.dart';

/// Presentation-only rollups over data returned by the service.
///
/// The service remains authoritative for reporting and exports. These helpers
/// only shape already-fetched entries for display.
class AllocationSlice {
  const AllocationSlice({
    required this.key,
    required this.label,
    required this.minutes,
  });

  final String key;
  final String label;
  final int minutes;

  double shareOf(int total) => total == 0 ? 0 : minutes / total;
}

int totalMinutes(Iterable<WorkItem> items) =>
    items.fold(0, (sum, item) => sum + item.minutes);

List<WorkItem> entriesInRange(
  Iterable<WorkItem> items,
  DateTime start,
  DateTime end,
) {
  final from = isoDate(start);
  final to = isoDate(end);
  return items
      .where((item) => item.localDate.compareTo(from) >= 0 && item.localDate.compareTo(to) <= 0)
      .toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
}

List<WorkItem> entriesOnDay(Iterable<WorkItem> items, DateTime day) {
  final key = isoDate(day);
  return items.where((item) => item.localDate == key).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
}

List<WorkItem> entriesForWeek(
  Iterable<WorkItem> items,
  DateTime day, {
  int weekStart = 1,
}) {
  final start = startOfWeek(day, weekStart: weekStart);
  return entriesInRange(items, start, addDays(start, 6));
}

Map<String, List<WorkItem>> groupByDay(Iterable<WorkItem> items) {
  final map = <String, List<WorkItem>>{};
  for (final item in items) {
    map.putIfAbsent(item.localDate, () => []).add(item);
  }
  for (final group in map.values) {
    group.sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }
  return map;
}

List<AllocationSlice> allocationFor(
  Iterable<WorkItem> items,
  List<Initiative> initiatives,
) {
  final totals = <String, int>{};
  final labels = <String, String>{};

  for (final item in items) {
    late final String key;
    late final String label;
    if (item.isSupport) {
      key = 'support';
      label = 'Support';
    } else if (item.type == WorkType.initiative && item.initiativeId != null) {
      key = 'initiative:${item.initiativeId}';
      label = item.attributionLabel(initiatives);
    } else {
      key = 'category:${item.category ?? 'other'}';
      label = item.categoryLabel ?? 'Other work';
    }
    labels[key] = label;
    totals[key] = (totals[key] ?? 0) + item.minutes;
  }

  final slices = totals.entries
      .map(
        (entry) => AllocationSlice(
          key: entry.key,
          label: labels[entry.key] ?? entry.key,
          minutes: entry.value,
        ),
      )
      .toList()
    ..sort((a, b) => b.minutes.compareTo(a.minutes));
  return slices;
}

int initiativeMinutesIn(Iterable<WorkItem> items, String initiativeId) =>
    items
        .where((item) => item.initiativeId == initiativeId)
        .fold(0, (sum, item) => sum + item.minutes);

int supportMinutes(Iterable<WorkItem> items) => items
    .where((item) => item.isSupport)
    .fold(0, (sum, item) => sum + item.minutes);

int supportInteractions(Iterable<WorkItem> items) =>
    items.where((item) => item.isSupport).length;

Set<String> supportPeople(Iterable<WorkItem> items) => items
    .where((item) => item.isSupport && (item.person?.isNotEmpty ?? false))
    .map((item) => item.person!)
    .toSet();

Map<SupportMode, int> supportByMode(Iterable<WorkItem> items) {
  final result = <SupportMode, int>{};
  for (final item in items.where((item) => item.isSupport)) {
    final mode = item.supportMode ?? SupportMode.other;
    result[mode] = (result[mode] ?? 0) + item.minutes;
  }
  return result;
}

Map<String, int> supportByPerson(Iterable<WorkItem> items) {
  final result = <String, int>{};
  for (final item in items.where((item) => item.isSupport)) {
    final person = item.person;
    if (person == null || person.isEmpty) continue;
    result[person] = (result[person] ?? 0) + item.minutes;
  }
  return result;
}

int distinctDays(Iterable<WorkItem> items) =>
    items.map((item) => item.localDate).toSet().length;

int initiativesTouched(Iterable<WorkItem> items) => items
    .where((item) => item.initiativeId != null)
    .map((item) => item.initiativeId!)
    .toSet()
    .length;

DateTime? lastActivity(Iterable<WorkItem> items, String initiativeId) {
  DateTime? latest;
  for (final item in items.where((item) => item.initiativeId == initiativeId)) {
    if (latest == null || item.startedAt.isAfter(latest)) {
      latest = item.startedAt;
    }
  }
  return latest;
}
