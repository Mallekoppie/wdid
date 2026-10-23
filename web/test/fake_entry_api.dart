import 'dart:async';

import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/utils/time_utils.dart';

/// In-memory work-entry service used by widget and state tests.
class FakeEntryApi implements EntryApi {
  FakeEntryApi({List<WorkEntry>? entries}) : entries = entries ?? [];

  final List<WorkEntry> entries;
  final List<EntryDraft> drafts = [];

  EntryFailure? listFailure;
  EntryFailure? createFailure;

  /// When set, the first list call waits for it, which lets tests observe the
  /// loading state.
  Completer<List<WorkEntry>>? listGate;

  int? listCalls;
  int? updateCalls;
  int _sequence = 0;

  String _id() {
    _sequence++;
    return 'entry-$_sequence';
  }

  @override
  Future<List<WorkEntry>> listEntries({
    String localDate = '',
    bool today = false,
    DateTime? from,
    DateTime? to,
    String categoryId = '',
    String subcategoryId = '',
    String person = '',
    String query = '',
  }) async {
    listCalls = (listCalls ?? 0) + 1;
    if (listGate != null) {
      final gate = listGate!;
      listGate = null;
      final gated = await gate.future;
      entries
        ..clear()
        ..addAll(gated);
    }
    if (listFailure != null) throw listFailure!;
    final day = today ? isoDate(DateTime.now()) : localDate;
    final matches = entries.where(
      (entry) =>
          (day.isEmpty || entry.localDate == day) &&
          (categoryId.isEmpty || entry.categoryId == categoryId) &&
          (subcategoryId.isEmpty || entry.subcategoryId == subcategoryId),
    );
    return matches.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
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
    final updated = entry.copyWith(updatedAt: DateTime.now().toUtc());
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
    entries.removeWhere((entry) => entry.id == id);
  }
}
