import 'dart:async';

import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/utils/time_utils.dart';

/// The ids of entries whose half-open time spans intersect another entry.
/// Mirrors the service's overlap detection so widget tests exercise the same
/// marking behaviour.
Set<String> overlappingEntryIds(Iterable<WorkEntry> entries) {
  final list = entries.toList();
  final flagged = <String>{};
  for (var i = 0; i < list.length; i++) {
    final first = list[i];
    final firstEnd = first.startedAt.add(Duration(minutes: first.minutes));
    if (!firstEnd.isAfter(first.startedAt)) continue;
    for (var j = i + 1; j < list.length; j++) {
      final second = list[j];
      final secondEnd = second.startedAt.add(Duration(minutes: second.minutes));
      if (!secondEnd.isAfter(second.startedAt)) continue;
      if (first.startedAt.isBefore(secondEnd) &&
          second.startedAt.isBefore(firstEnd)) {
        flagged
          ..add(first.id)
          ..add(second.id);
      }
    }
  }
  return flagged;
}

/// In-memory work-entry service used by widget and state tests.
class FakeEntryApi implements EntryApi {
  FakeEntryApi({List<WorkEntry>? entries}) : entries = entries ?? [];

  final List<WorkEntry> entries;
  final List<EntryDraft> drafts = [];

  EntryFailure? listFailure;
  EntryFailure? createFailure;
  EntryFailure? splitFailure;

  /// When set, the first list call waits for it, which lets tests observe the
  /// loading state.
  Completer<List<WorkEntry>>? listGate;

  /// Like [listGate], but only for Log queries (those without `today`).
  Completer<List<WorkEntry>>? logGate;

  int? listCalls;
  int? updateCalls;
  int? splitCalls;
  int? deleteCalls;
  DateTime? lastFrom;
  DateTime? lastTo;
  String lastFromDate = '';
  String lastToDate = '';
  String lastCategoryId = '';
  String lastSubcategoryId = '';
  String lastQuery = '';
  int _sequence = 0;

  String _id() {
    _sequence++;
    return 'entry-$_sequence';
  }

  @override
  Future<EntryListing> listEntries({
    String localDate = '',
    bool today = false,
    DateTime? from,
    DateTime? to,
    String fromDate = '',
    String toDate = '',
    String categoryId = '',
    String subcategoryId = '',
    String person = '',
    String query = '',
  }) async {
    listCalls = (listCalls ?? 0) + 1;
    if (!today) {
      lastFrom = from;
      lastTo = to;
      lastFromDate = fromDate;
      lastToDate = toDate;
      lastCategoryId = categoryId;
      lastSubcategoryId = subcategoryId;
      lastQuery = query;
    }
    if (listGate != null) {
      final gate = listGate!;
      listGate = null;
      final gated = await gate.future;
      entries
        ..clear()
        ..addAll(gated);
    }
    if (!today && logGate != null) {
      final gate = logGate!;
      logGate = null;
      final gated = await gate.future;
      entries
        ..clear()
        ..addAll(gated);
    }
    if (listFailure != null) throw listFailure!;
    final day = today ? isoDate(DateTime.now()) : localDate;
    final needle = query.trim().toLowerCase();
    final matches =
        entries
            .where(
              (entry) =>
                  (day.isEmpty || entry.localDate == day) &&
                  (categoryId.isEmpty || entry.categoryId == categoryId) &&
                  (subcategoryId.isEmpty ||
                      entry.subcategoryId == subcategoryId) &&
                  (person.isEmpty ||
                      entry.person.toLowerCase() ==
                          person.trim().toLowerCase()) &&
                  (fromDate.isEmpty ||
                      entry.localDate.compareTo(fromDate) >= 0) &&
                  (toDate.isEmpty || entry.localDate.compareTo(toDate) <= 0) &&
                  (from == null || !entry.startedAt.isBefore(from)) &&
                  (to == null || entry.startedAt.isBefore(to)) &&
                  (needle.isEmpty ||
                      '${entry.description} ${entry.outcome}'
                          .toLowerCase()
                          .contains(needle)),
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    // Overlaps are detected against every stored entry, matching the service:
    // filtering one side of a pair does not hide the marker on the other.
    final flagged = overlappingEntryIds(entries);
    return EntryListing(
      entries: matches,
      overlappingIds: {
        for (final entry in matches)
          if (flagged.contains(entry.id)) entry.id,
      },
    );
  }

  @override
  Future<WorkEntry> createEntry(EntryDraft draft) async {
    drafts.add(draft);
    if (createFailure != null) throw createFailure!;
    final startedAt = draft.startedAt.toUtc();
    final endedAt = startedAt.add(Duration(minutes: draft.minutes));
    final now = DateTime.now().toUtc();
    final entry = WorkEntry(
      id: _id(),
      categoryId: draft.categoryId,
      subcategoryId: draft.subcategoryId,
      description: draft.description,
      outcome: draft.outcome,
      startedAt: startedAt,
      endedAt: endedAt,
      minutes: draft.minutes,
      localDate: isoDate(startedAt.toLocal()),
      person: draft.person,
      team: draft.team,
      tags: draft.tags,
      links: draft.links,
      source: draft.source,
      createdAt: now,
      updatedAt: now,
    );
    entries.add(entry);
    return entry;
  }

  @override
  Future<WorkEntry> updateEntry(WorkEntry entry) async {
    updateCalls = (updateCalls ?? 0) + 1;
    if (createFailure != null) throw createFailure!;
    final updated = entry.copyWith(
      endedAt: entry.startedAt.add(Duration(minutes: entry.minutes)),
      updatedAt: DateTime.now().toUtc(),
    );
    final index = entries.indexWhere((existing) => existing.id == entry.id);
    if (index == -1) {
      entries.add(updated);
    } else {
      entries[index] = updated;
    }
    return updated;
  }

  @override
  Future<void> deleteEntry(String id) async {
    deleteCalls = (deleteCalls ?? 0) + 1;
    entries.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<SplitHalves> splitEntry(String id, int atMinutes) async {
    splitCalls = (splitCalls ?? 0) + 1;
    if (splitFailure != null) throw splitFailure!;
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index == -1) {
      throw const EntryFailure('That entry no longer exists.');
    }
    final entry = entries[index];
    if (atMinutes < 1 || atMinutes >= entry.minutes) {
      throw const EntryFailure(
        'must leave at least one minute on each side',
        field: 'atMinutes',
      );
    }

    final now = DateTime.now().toUtc();
    final first = entry.copyWith(
      minutes: atMinutes,
      endedAt: entry.startedAt.add(Duration(minutes: atMinutes)),
      updatedAt: now,
    );
    final second = WorkEntry(
      id: _id(),
      categoryId: entry.categoryId,
      subcategoryId: entry.subcategoryId,
      description: entry.description,
      outcome: entry.outcome,
      startedAt: first.endedAt,
      endedAt: first.endedAt.add(Duration(minutes: entry.minutes - atMinutes)),
      minutes: entry.minutes - atMinutes,
      localDate: entry.localDate,
      person: entry.person,
      team: entry.team,
      tags: entry.tags,
      links: entry.links,
      source: entry.source,
      createdAt: now,
      updatedAt: now,
    );
    entries[index] = first;
    entries.add(second);
    return SplitHalves(first: first, second: second);
  }
}
