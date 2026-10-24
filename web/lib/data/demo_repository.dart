import 'dart:convert';

import '../models/app_settings.dart';
import '../models/check_in.dart';
import '../models/drafts.dart';
import '../models/enums.dart';
import '../models/initiative.dart';
import '../models/note.dart';
import '../models/work_item.dart';
import '../utils/analytics.dart';
import '../utils/time_utils.dart';
import 'repository.dart';

/// In-memory stand-in for the Go service.
///
/// This adapter exists so the UI can be built and reviewed before the service
/// contract is live. It never runs in the hosted product: [WdidApp] wires the
/// HTTP/gRPC client once `TimerService`, `WorkItemService`, `InitiativeService`,
/// `CheckInService`, `SummaryService`, and `SettingsService` are available.
class DemoWdidRepository implements WdidRepository {
  DemoWdidRepository({this.latency = const Duration(milliseconds: 180)}) {
    _seed();
  }

  final Duration latency;

  final List<Initiative> _initiatives = [];
  final List<WorkItem> _workItems = [];
  final List<CheckIn> _checkIns = [];
  final List<Note> _notes = [];
  AppSettings _settings = const AppSettings();
  int _sequence = 0;

  Future<void> _pause() => Future<void>.delayed(latency);

  String _id() {
    _sequence++;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'demo-$stamp-${_sequence.toString().padLeft(4, '0')}';
  }

  @override
  Future<List<Initiative>> listInitiatives() async {
    await _pause();
    return List.unmodifiable(_initiatives);
  }

  @override
  Future<Initiative> createInitiative(InitiativeDraft draft) async {
    await _pause();
    final now = DateTime.now();
    final initiative = Initiative(
      id: _id(),
      name: draft.name,
      summary: draft.summary,
      targetOutcome: draft.targetOutcome,
      status: draft.status,
      progress: draft.progress,
      startedAt: now,
      targetDate: draft.targetDate,
      links: draft.links,
      tags: draft.tags,
      createdAt: now,
      updatedAt: now,
    );
    _initiatives.insert(0, initiative);
    return initiative;
  }

  @override
  Future<Initiative> updateInitiative(Initiative initiative) async {
    await _pause();
    final index = _initiatives.indexWhere((item) => item.id == initiative.id);
    if (index == -1) {
      throw StateError('Initiative ${initiative.id} was not found');
    }
    final updated = initiative.copyWith(updatedAt: DateTime.now());
    _initiatives[index] = updated;
    return updated;
  }

  @override
  Future<List<WorkItem>> listWorkItems() async {
    await _pause();
    final items = List<WorkItem>.from(_workItems)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return items;
  }

  @override
  Future<WorkItem> createWorkItem(WorkItemDraft draft) async {
    await _pause();
    final now = DateTime.now();
    final endedAt = draft.startedAt.add(Duration(minutes: draft.minutes));
    final item = WorkItem(
      id: _id(),
      type: draft.type,
      initiativeId: draft.initiativeId,
      category: draft.category,
      categoryLabel: draft.categoryLabel,
      startedAt: draft.startedAt.toUtc(),
      endedAt: endedAt.toUtc(),
      minutes: draft.minutes,
      localDate: isoDate(draft.startedAt),
      summary: draft.summary,
      outcome: draft.outcome,
      notes: draft.notes,
      links: draft.links,
      tags: draft.tags,
      person: draft.person,
      team: draft.team,
      source: draft.source,
      createdAt: now,
      updatedAt: now,
    );
    _workItems.add(item);
    return item;
  }

  @override
  Future<WorkItem> updateWorkItem(WorkItem item) async {
    await _pause();
    final index = _workItems.indexWhere((entry) => entry.id == item.id);
    if (index == -1) {
      throw StateError('Work item ${item.id} was not found');
    }
    final updated = item.copyWith(
      endedAt: item.startedAt.add(Duration(minutes: item.minutes)),
      localDate: isoDate(item.startedAt),
      updatedAt: DateTime.now(),
    );
    _workItems[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteWorkItem(String id) async {
    await _pause();
    _workItems.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<Note>> listNotes() async {
    await _pause();
    final notes = List<Note>.from(_notes)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notes;
  }

  @override
  Future<Note> createNote(NoteDraft draft) async {
    await _pause();
    final note = Note(
      id: _id(),
      date: draft.date,
      initiativeId: draft.initiativeId,
      text: draft.text,
      createdAt: DateTime.now(),
    );
    _notes.add(note);
    return note;
  }

  @override
  Future<Note> updateNote(Note note) async {
    await _pause();
    final index = _notes.indexWhere((item) => item.id == note.id);
    if (index == -1) {
      throw StateError('Note ${note.id} was not found');
    }
    _notes[index] = note;
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    await _pause();
    _notes.removeWhere((note) => note.id == id);
  }

  @override
  Future<List<CheckIn>> listCheckIns() async {
    await _pause();
    final checkIns = List<CheckIn>.from(_checkIns)
      ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));
    return checkIns;
  }

  @override
  Future<CheckIn> createCheckIn(CheckInDraft draft) async {
    await _pause();
    final entries = entriesInRange(
      _workItems,
      draft.periodStart,
      draft.periodEnd,
    );
    final checkIn = CheckIn(
      id: _id(),
      periodStart: dateOnly(draft.periodStart),
      periodEnd: dateOnly(draft.periodEnd),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      kind: draft.kind,
      audience: draft.kind == CheckInKind.manager ? draft.audience : null,
      focusNotes: draft.focusNotes,
      totals: _totalsFor(entries),
    );
    _checkIns.add(checkIn);
    return checkIn;
  }

  @override
  Future<CheckIn> updateCheckIn(CheckIn checkIn) async {
    await _pause();
    final index = _checkIns.indexWhere((item) => item.id == checkIn.id);
    if (index == -1) {
      throw StateError('Check-in ${checkIn.id} was not found');
    }
    _checkIns[index] = checkIn;
    return checkIn;
  }

  @override
  Future<void> deleteCheckIn(String id) async {
    await _pause();
    final index = _checkIns.indexWhere((item) => item.id == id);
    if (index == -1) {
      throw StateError('Check-in $id was not found');
    }
    final checkIn = _checkIns[index];
    if (checkIn.isManager && checkIn.isFinal) {
      throw StateError('A final manager check-in is read-only');
    }
    _checkIns.removeAt(index);
  }

  @override
  Future<CheckIn> generateSummary(String checkInId) async {
    await _pause();
    final index = _checkIns.indexWhere((item) => item.id == checkInId);
    if (index == -1) {
      throw StateError('Check-in $checkInId was not found');
    }
    final checkIn = _checkIns[index];
    final entries = entriesInRange(
      _workItems,
      checkIn.periodStart,
      checkIn.periodEnd,
    );
    final allocation = allocationFor(entries, _initiatives);
    final support = entries.where((entry) => entry.isSupport).toList();
    final outcomes = entries
        .where((entry) => entry.outcome.isNotEmpty)
        .take(6)
        .map((entry) => '- ${entry.outcome}')
        .join('\n');
    final supportPeople = supportByPerson(support).entries
        .map((entry) => '- ${entry.key}: ${formatDuration(entry.value)}')
        .join('\n');
    final lines = [
      '## Highlights',
      if (outcomes.isNotEmpty)
        outcomes
      else
        '- No outcome evidence recorded yet.',
      '',
      '## Time allocation',
      for (final slice in allocation.take(5))
        '- ${slice.label}: ${formatDuration(slice.minutes)}',
      '',
      '## Collaboration',
      if (supportPeople.isNotEmpty)
        supportPeople
      else
        '- No support work logged in this period.',
      '',
      '## Risks and gaps',
      '- Demo summary generated by the local adapter.',
      '- Replace with SummaryService output once the service is connected.',
    ];
    final updated = checkIn.copyWith(
      state: CheckInState.generated,
      summaryMarkdown: lines.join('\n'),
      summaryModel: 'demo/local-adapter',
      promptVersion: 'v1',
    );
    _checkIns[index] = updated;
    return updated;
  }

  @override
  Future<CheckInPrompt> buildPrompt(
    DateTime periodStart,
    DateTime periodEnd, {
    CheckInKind kind = CheckInKind.manager,
    CheckInAudience? audience,
  }) async {
    await _pause();
    final checkIn = _findCheckIn(periodStart, periodEnd);
    final summary = checkIn?.summaryMarkdown.isNotEmpty == true
        ? checkIn!.summaryMarkdown
        : _fallbackSummary(periodStart, periodEnd);
    final variant = kind == CheckInKind.personal
        ? CheckInPromptVariant.personalReview
        : audience == CheckInAudience.performanceReview
        ? CheckInPromptVariant.managerPerformanceReview
        : CheckInPromptVariant.managerOneOnOne;
    return CheckInPrompt(
      prompt: '${_promptInstructions[variant]}\n\n$summary',
      variant: variant,
      promptVersion: 'v1',
    );
  }

  @override
  Future<ExportBundle> buildExport(
    DateTime periodStart,
    DateTime periodEnd,
  ) async {
    await _pause();
    final entries = entriesInRange(_workItems, periodStart, periodEnd);
    final support = entries.where((entry) => entry.isSupport).toList();
    final checkIn = _findCheckIn(periodStart, periodEnd);
    final summary = checkIn?.summaryMarkdown.isNotEmpty == true
        ? checkIn!.summaryMarkdown
        : _fallbackSummary(periodStart, periodEnd);
    final data = {
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'person': 'Alex',
      'period': {'start': isoDate(periodStart), 'end': isoDate(periodEnd)},
      'initiatives': _initiatives.map((item) => item.toJson()).toList(),
      'entries': entries.map((item) => item.toJson()).toList(),
      'support': support.map((item) => item.toJson()).toList(),
      'notes': _notes
          .where((note) => note.date.compareTo(isoDate(periodStart)) >= 0)
          .map((note) => note.toJson())
          .toList(),
      'totals': _totalsFor(entries).toJson(),
    };
    return ExportBundle(
      directory: 'wdid-export-${isoDate(periodStart)}_${isoDate(periodEnd)}',
      files: {
        'summary.md': summary,
        'data.json': const JsonEncoder.withIndent('  ').convert(data),
        'entries.csv': _entriesCsv(entries, includeSupport: false),
        'support.csv': _entriesCsv(support, includeSupport: true),
      },
    );
  }

  @override
  Future<AppSettings> getSettings() async {
    await _pause();
    return _settings;
  }

  @override
  Future<AppSettings> updateSettings(AppSettings settings) async {
    await _pause();
    _settings = settings;
    return _settings;
  }

  @override
  Future<BackupStatus> backupNow() async {
    await _pause();
    final now = DateTime.now();
    _settings = _settings.copyWith(
      lastBackupAt: now,
      lastBackupBytes: 1_284_000 + _sequence * 512,
    );
    return BackupStatus(createdAt: now, bytes: _settings.lastBackupBytes);
  }

  CheckIn? _findCheckIn(DateTime start, DateTime end) {
    for (final checkIn in _checkIns) {
      if (isoDate(checkIn.periodStart) == isoDate(start) &&
          isoDate(checkIn.periodEnd) == isoDate(end)) {
        return checkIn;
      }
    }
    return null;
  }

  CheckInTotals _totalsFor(Iterable<WorkItem> entries) {
    final byInitiative = <String, int>{};
    final byCategory = <String, int>{};
    final supportByPerson = <String, int>{};
    var minutes = 0;
    for (final entry in entries) {
      minutes += entry.minutes;
      if (entry.initiativeId != null) {
        byInitiative[entry.initiativeId!] =
            (byInitiative[entry.initiativeId!] ?? 0) + entry.minutes;
      } else {
        final category = entry.category ?? 'other';
        byCategory[category] = (byCategory[category] ?? 0) + entry.minutes;
      }
      final person = entry.person;
      if (person != null && person.isNotEmpty) {
        supportByPerson[person] =
            (supportByPerson[person] ?? 0) + entry.minutes;
      }
    }
    return CheckInTotals(
      minutes: minutes,
      byInitiative: byInitiative,
      byCategory: byCategory,
      supportByPerson: supportByPerson,
    );
  }

  String _fallbackSummary(DateTime start, DateTime end) {
    final entries = entriesInRange(_workItems, start, end);
    final total = formatDuration(totalMinutes(entries));
    return '## Overview\n$total logged across ${distinctDays(entries)} days '
        'from ${isoDate(start)} to ${isoDate(end)}.\n\n'
        '> Generate a check-in summary to replace this placeholder.';
  }

  String _entriesCsv(List<WorkItem> entries, {required bool includeSupport}) {
    final buffer = StringBuffer(
      'date,start,end,minutes,type,initiative,category,summary,outcome,person,team,tags\n',
    );
    for (final entry in entries) {
      buffer.writeln(
        [
          entry.localDate,
          formatTime(entry.startedLocal),
          formatTime(entry.endedLocal),
          entry.minutes.toString(),
          includeSupport ? 'support' : entry.type.name,
          entry.initiativeId ?? '',
          entry.categoryLabel ?? entry.category ?? '',
          _csv(entry.summary),
          _csv(entry.outcome),
          entry.person ?? '',
          entry.team ?? '',
          entry.tags.join(' '),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  /// Demo-mode copies of the service's prompt variants. The generated text is
  /// never the contract; it only keeps the demo usable offline.
  static const Map<CheckInPromptVariant, String> _promptInstructions = {
    CheckInPromptVariant.managerOneOnOne: '''
You are preparing a software engineer for a 1:1 with their manager.

Produce five to seven highlight bullets, per-project progress and evidence, a
collaboration paragraph, time allocation observations, risks or gaps, and three
ready-to-paste bullets in the first person.

Use only the data provided. Do not invent achievements, metrics or names.
Output Markdown. Cite links only when they are present in the data.''',
    CheckInPromptVariant.managerPerformanceReview: '''
You are preparing evidence for a formal performance review of a software
engineer.

Produce evidence bullets tied to measurable outcomes, per-project scope and
impact, concrete collaboration examples, time allocation evidence, growth
areas, and three ready-to-paste performance review bullets.

Use only the data provided. Do not invent achievements, metrics or names.
Output Markdown. Cite links only when they are present in the data.''',
    CheckInPromptVariant.personalReview: '''
You are reviewing your own working period.

Describe where the time went, what moved, what did not, patterns worth
changing, and up to three concrete changes for the next period.

Use only the data provided. Do not invent achievements, metrics or names.
Output Markdown. Cite links only when they are present in the data.''',
  };

  void _seed() {
    final now = DateTime.now();
    final today = dateOnly(now);

    DateTime at(int daysAgo, int hour, int minute) => today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: hour, minutes: minute));

    final billing = Initiative(
      id: 'init-billing',
      name: 'Billing migration',
      summary: 'Move invoicing to the new pipeline without a cutover freeze.',
      targetOutcome: 'Invoice generation under 5 minutes',
      status: InitiativeStatus.active,
      progress: 64,
      startedAt: now.subtract(const Duration(days: 104)),
      targetDate: now.add(const Duration(days: 43)),
      tags: const ['billing', 'migration'],
      links: const [
        LinkRef(label: 'Epic', url: 'https://example.dev/epics/412'),
      ],
      createdAt: now.subtract(const Duration(days: 110)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );
    final platform = Initiative(
      id: 'init-platform',
      name: 'Platform hardening',
      summary: 'Reduce delivery risk in the shared build and deploy path.',
      targetOutcome: 'Zero P1s from dependencies this quarter',
      status: InitiativeStatus.active,
      progress: 47,
      startedAt: now.subtract(const Duration(days: 82)),
      targetDate: now.add(const Duration(days: 68)),
      tags: const ['platform', 'reliability'],
      createdAt: now.subtract(const Duration(days: 82)),
      updatedAt: now.subtract(const Duration(days: 9)),
    );
    final ops = Initiative(
      id: 'init-ops',
      name: 'Customer ops automation',
      summary: 'Remove repetitive manual steps from weekly customer reporting.',
      targetOutcome: 'Weekly report assembled without manual steps',
      status: InitiativeStatus.planned,
      progress: 10,
      startedAt: now.subtract(const Duration(days: 21)),
      tags: const ['automation'],
      createdAt: now.subtract(const Duration(days: 21)),
      updatedAt: now.subtract(const Duration(days: 6)),
    );
    final deps = Initiative(
      id: 'init-deps',
      name: 'Dependency upgrades',
      summary: 'Clear the backlog of runtime and build dependency upgrades.',
      targetOutcome: 'All runtime dependencies on supported versions',
      status: InitiativeStatus.done,
      progress: 100,
      startedAt: now.subtract(const Duration(days: 140)),
      targetDate: now.subtract(const Duration(days: 12)),
      tags: const ['maintenance'],
      createdAt: now.subtract(const Duration(days: 140)),
      updatedAt: now.subtract(const Duration(days: 12)),
    );
    final legacy = Initiative(
      id: 'init-legacy',
      name: 'Legacy invoicing retirement',
      summary: 'Shut down the previous invoicing service.',
      targetOutcome: 'Old invoicing service deleted',
      status: InitiativeStatus.archived,
      progress: 100,
      startedAt: now.subtract(const Duration(days: 240)),
      targetDate: now.subtract(const Duration(days: 40)),
      createdAt: now.subtract(const Duration(days: 240)),
      updatedAt: now.subtract(const Duration(days: 40)),
    );
    _initiatives.addAll([billing, platform, ops, deps, legacy]);

    void entry({
      required int daysAgo,
      required int hour,
      required int minute,
      required int minutes,
      required String summary,
      String? initiativeId,
      String? category,
      String? categoryLabel,
      String outcome = '',
      String? person,
      String? team,
      List<String> tags = const [],
      String source = 'manual',
    }) {
      final started = at(daysAgo, hour, minute);
      _workItems.add(
        WorkItem(
          id: _id(),
          type: initiativeId == null ? WorkType.category : WorkType.initiative,
          initiativeId: initiativeId,
          category: category,
          categoryLabel: categoryLabel,
          startedAt: started.toUtc(),
          endedAt: started.add(Duration(minutes: minutes)).toUtc(),
          minutes: minutes,
          localDate: isoDate(started),
          summary: summary,
          outcome: outcome,
          tags: tags,
          person: person,
          team: team,
          source: source,
          createdAt: started,
          updatedAt: started,
        ),
      );
    }

    // Today's feed, matching the Today screen design.
    entry(
      daysAgo: 0,
      hour: 9,
      minute: 15,
      minutes: 42,
      initiativeId: billing.id,
      summary: 'Backfill script skeleton',
      outcome: 'Script runs against staging',
      tags: const ['migration'],
      source: 'timer',
    );
    entry(
      daysAgo: 0,
      hour: 10,
      minute: 0,
      minutes: 30,
      category: SupportMode.review.name,
      categoryLabel: 'Review',
      summary: 'Reviewed event bus design',
      outcome: 'Three risks identified before implementation',
      person: 'Priya',
      team: 'Payments',
    );
    entry(
      daysAgo: 0,
      hour: 10,
      minute: 30,
      minutes: 45,
      initiativeId: billing.id,
      summary: 'Reviewed migration plan',
      outcome: 'Two rollback gaps closed',
    );
    entry(
      daysAgo: 0,
      hour: 11,
      minute: 15,
      minutes: 45,
      category: 'meetings',
      categoryLabel: 'Meetings',
      summary: 'Sprint planning',
    );
    entry(
      daysAgo: 0,
      hour: 13,
      minute: 30,
      minutes: 60,
      initiativeId: platform.id,
      summary: 'Upgraded dependency batch',
      outcome: 'Zero P1 advisories remain',
      tags: const ['deps'],
    );
    entry(
      daysAgo: 0,
      hour: 14,
      minute: 30,
      minutes: 45,
      category: SupportMode.unblock.name,
      categoryLabel: 'Unblock',
      summary: 'Rotated CI service account',
      outcome: 'Deployment pipeline unblocked',
      person: 'Sam',
      team: 'Platform',
    );

    // History for the log, rollups, and check-ins.
    final initiativePool = [billing, platform, ops, deps];
    final summaries = [
      'Backfill validation',
      'Migration dry run',
      'Build cache cleanup',
      'Alert routing review',
      'Report automation spike',
      'Retry policy tests',
      'Deploy pipeline review',
      'Dependency audit',
    ];
    final outcomes = [
      'Verified against staging data',
      'Cut runtime by 18%',
      'Closed two rollback gaps',
      'Removed a manual approval step',
      'No regressions in smoke tests',
    ];
    final people = ['Priya', 'Sam', 'Jo', 'Morgan', 'Taylor'];
    final teams = ['Payments', 'Platform', 'Infra', 'Customer Ops'];
    final supportModes = [
      SupportMode.review,
      SupportMode.pair,
      SupportMode.unblock,
      SupportMode.mentor,
      SupportMode.incident,
    ];

    for (var daysAgo = 1; daysAgo < 84; daysAgo++) {
      final date = at(daysAgo, 9, 0);
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        continue;
      }
      final count = 1 + (daysAgo % 3);
      for (var index = 0; index < count; index++) {
        final initiative =
            initiativePool[(daysAgo + index) % initiativePool.length];
        final hour = [9, 10, 13, 15][(daysAgo + index) % 4];
        final minutes = [30, 45, 60, 25][(daysAgo + index) % 4];
        entry(
          daysAgo: daysAgo,
          hour: hour,
          minute: (index * 10) % 50,
          minutes: minutes,
          initiativeId: initiative.id,
          summary: summaries[(daysAgo + index) % summaries.length],
          outcome: outcomes[(daysAgo + index) % outcomes.length],
        );
        if ((daysAgo + index) % 6 == 0) {
          final mode = supportModes[(daysAgo + index) % supportModes.length];
          entry(
            daysAgo: daysAgo,
            hour: hour + 1,
            minute: 30,
            minutes: [20, 30, 45][daysAgo % 3],
            category: mode.name,
            categoryLabel: mode.label,
            summary:
                'Supported ${people[daysAgo % people.length]} on ${summaries[(daysAgo + 2) % summaries.length].toLowerCase()}',
            outcome: outcomes[(daysAgo + 2) % outcomes.length],
            person: people[daysAgo % people.length],
            team: teams[daysAgo % teams.length],
          );
        }
      }
    }

    final finalEntries = entriesInRange(
      _workItems,
      now.subtract(const Duration(days: 98)),
      now.subtract(const Duration(days: 35)),
    );
    final generatedEntries = entriesInRange(
      _workItems,
      now.subtract(const Duration(days: 34)),
      now.subtract(const Duration(days: 7)),
    );

    _checkIns.addAll([
      CheckIn(
        id: 'checkin-final',
        periodStart: dateOnly(now.subtract(const Duration(days: 98))),
        periodEnd: dateOnly(now.subtract(const Duration(days: 35))),
        createdAt: now.subtract(const Duration(days: 35)),
        state: CheckInState.final_,
        focusNotes:
            'Billing migration and platform reliability were the focus.',
        summaryMarkdown: '''
## Highlights
- Cut staging invoice generation from 7 minutes to 3 minutes.
- Closed two rollback gaps in the migration plan.
- Removed one manual approval from the weekly customer report.
- Unblocked the platform team on CI credentials twice.

## Time allocation
- Billing migration: 38h 20m
- Platform hardening: 22h 10m
- Support: 14h 30m

## Collaboration
- Priya: design reviews and event bus risk analysis.
- Sam: CI and deployment unblocking.

## Risks and gaps
- Cutover rehearsal is still pending.
''',
        summaryModel: 'demo/seed',
        totals: _totalsFor(finalEntries),
      ),
      CheckIn(
        id: 'checkin-generated',
        periodStart: dateOnly(now.subtract(const Duration(days: 34))),
        periodEnd: dateOnly(now.subtract(const Duration(days: 7))),
        createdAt: now.subtract(const Duration(days: 7)),
        state: CheckInState.generated,
        focusNotes: 'Finish the backfill path and reduce deploy friction.',
        summaryMarkdown: '''
## Highlights
- Backfill script now runs against staging.
- Dependency batch upgraded with no P1 advisories.
- Deployment pipeline reviewed and simplified.

## Time allocation
- Billing migration: 18h 05m
- Platform hardening: 12h 40m
- Support: 5h 20m

## Collaboration
- Sam: unblocked CI service account access.
- Priya: reviewed the event bus design before implementation.

## Risks and gaps
- Production cutover date is not fixed yet.
''',
        summaryModel: 'demo/seed',
        totals: _totalsFor(generatedEntries),
      ),
    ]);

    _notes.addAll([
      Note(
        id: _id(),
        date: isoDate(today),
        text: 'Backfill work is now stable enough to track by initiative.',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      Note(
        id: _id(),
        date: isoDate(today.subtract(const Duration(days: 2))),
        initiativeId: billing.id,
        text: 'Rollback plan needs a rehearsal before the cutover window is booked.',
        createdAt: now.subtract(const Duration(days: 2, hours: 3)),
      ),
      Note(
        id: _id(),
        date: isoDate(today.subtract(const Duration(days: 9))),
        initiativeId: platform.id,
        text: 'Dependency bot is quiet after the batch upgrade.',
        createdAt: now.subtract(const Duration(days: 9, hours: 4)),
      ),
    ]);

    _settings = _settings.copyWith(
      lastBackupAt: now.subtract(const Duration(hours: 3, minutes: 12)),
      lastBackupBytes: 1_284_352,
    );
  }
}
