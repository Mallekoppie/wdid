import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/demo_repository.dart';
import '../data/repository.dart';
import '../models/app_settings.dart';
import '../models/check_in.dart';
import '../models/drafts.dart';
import '../models/enums.dart';
import '../models/initiative.dart';
import '../models/note.dart';
import '../models/work_item.dart';
import '../utils/analytics.dart';
import '../utils/attribution.dart';
import '../utils/time_utils.dart';

enum AppStatus { loading, ready, error }

class ActiveTimer {
  ActiveTimer({
    required this.attribution,
    required this.description,
    required this.startedAt,
  });

  final AttributionChoice attribution;
  String description;
  final DateTime startedAt;
  Duration pausedAccumulated = Duration.zero;
  DateTime? pausedAt;

  bool get isPaused => pausedAt != null;

  Duration elapsedAt(DateTime now) {
    final end = pausedAt ?? now;
    final elapsed = end.difference(startedAt) - pausedAccumulated;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
}

class AppState extends ChangeNotifier {
  AppState(this.repository);

  final WdidRepository repository;

  AppStatus status = AppStatus.loading;
  String? loadError;

  List<Initiative> initiatives = const [];
  List<WorkItem> workItems = const [];
  List<CheckIn> checkIns = const [];
  List<Note> notes = const [];
  AppSettings settings = const AppSettings();

  ActiveTimer? activeTimer;
  AttributionChoice? lastAttribution;

  /// Screens listen to this to focus their search field on `/`.
  final ValueNotifier<int> searchFocusRequest = ValueNotifier<int>(0);

  Timer? _ticker;
  bool _disposed = false;

  bool get isDemo => repository is DemoWdidRepository;

  DateTime get today => dateOnly(DateTime.now());
  String get todayIso => isoDate(today);

  Future<void> load() async {
    status = AppStatus.loading;
    loadError = null;
    _notify();
    try {
      final results = await Future.wait<dynamic>([
        repository.listInitiatives(),
        repository.listWorkItems(),
        repository.listNotes(),
        repository.listCheckIns(),
        repository.getSettings(),
      ]);
      initiatives = List<Initiative>.from(results[0] as List<Initiative>);
      workItems = List<WorkItem>.from(results[1] as List<WorkItem>);
      notes = List<Note>.from(results[2] as List<Note>);
      checkIns = List<CheckIn>.from(results[3] as List<CheckIn>);
      settings = results[4] as AppSettings;
      _ensureAttribution();
      status = AppStatus.ready;
    } catch (error) {
      status = AppStatus.error;
      loadError = error.toString();
    }
    _notify();
  }

  Future<void> reload() => load();

  /// Presentation-only choices for capture forms.
  List<AttributionChoice> get attributionChoices =>
      AttributionChoice.forInitiatives(initiatives);

  Initiative? initiativeById(String? id) {
    if (id == null) return null;
    for (final initiative in initiatives) {
      if (initiative.id == id) return initiative;
    }
    return null;
  }

  Initiative? get lastUsedInitiative {
    final choice = lastAttribution;
    if (choice == null || !choice.isInitiative) return null;
    return initiativeById(choice.initiativeId);
  }

  List<WorkItem> get todayItems => entriesOnDay(workItems, today);

  int get todayMinutes => totalMinutes(todayItems);

  int get weekMinutes => totalMinutes(
        entriesForWeek(workItems, today, weekStart: settings.weekStart),
      );

  List<AllocationSlice> get weekAllocation => allocationFor(
        entriesForWeek(workItems, today, weekStart: settings.weekStart),
        initiatives,
      );

  List<Initiative> get openInitiatives =>
      initiatives.where((initiative) => !initiative.isArchived).toList();

  List<Initiative> get archivedInitiatives =>
      initiatives.where((initiative) => initiative.isArchived).toList();

  CheckIn? get latestCheckIn {
    CheckIn? latest;
    for (final checkIn in checkIns) {
      if (latest == null || checkIn.periodEnd.isAfter(latest.periodEnd)) {
        latest = checkIn;
      }
    }
    return latest;
  }

  int get daysSinceCheckIn {
    final latest = latestCheckIn;
    if (latest == null) return 0;
    final days = today.difference(dateOnly(latest.periodEnd)).inDays;
    return days < 0 ? 0 : days;
  }

  DateTime get defaultCheckInStart {
    final latest = latestCheckIn;
    if (latest != null) return dateOnly(latest.periodEnd);
    return startOfQuarter(today);
  }

  Note? get todayNote {
    for (final note in notes) {
      if (note.date == todayIso && note.initiativeId == null) return note;
    }
    return null;
  }

  List<Note> notesForInitiative(String initiativeId) => notes
      .where((note) => note.initiativeId == initiativeId)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<WorkItem> itemsForInitiative(String initiativeId) => workItems
      .where((item) => item.initiativeId == initiativeId)
      .toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  int minutesForInitiative(String initiativeId) =>
      initiativeMinutesIn(workItems, initiativeId);

  // --- Timer -------------------------------------------------------------

  void setAttribution(AttributionChoice choice) {
    lastAttribution = choice;
    _notify();
  }

  void startTimer({AttributionChoice? attribution, String description = ''}) {
    if (activeTimer != null) return;
    final choice = attribution ?? lastAttribution ?? _firstChoice();
    if (choice == null) {
      throw StateError('Create an initiative or category before starting a timer.');
    }
    lastAttribution = choice;
    activeTimer = ActiveTimer(
      attribution: choice,
      description: description.trim().isEmpty ? 'Focus block' : description.trim(),
      startedAt: DateTime.now(),
    );
    _startTicker();
    _notify();
  }

  void updateTimerDescription(String description) {
    final timer = activeTimer;
    if (timer == null) return;
    timer.description = description;
    _notify();
  }

  void pauseTimer() {
    final timer = activeTimer;
    if (timer == null || timer.isPaused) return;
    timer.pausedAt = DateTime.now();
    _stopTicker();
    _notify();
  }

  void resumeTimer() {
    final timer = activeTimer;
    if (timer == null || !timer.isPaused) return;
    final pausedAt = timer.pausedAt!;
    timer.pausedAccumulated += DateTime.now().difference(pausedAt);
    timer.pausedAt = null;
    _startTicker();
    _notify();
  }

  Future<WorkItem?> stopTimer() async {
    final timer = activeTimer;
    if (timer == null) return null;
    final now = DateTime.now();
    final elapsed = timer.elapsedAt(now);
    final minutes = elapsed.inMinutes < 1 ? 1 : elapsed.inMinutes;
    final draft = WorkItemDraft(
      type: timer.attribution.type,
      initiativeId: timer.attribution.initiativeId,
      category: timer.attribution.category,
      categoryLabel: timer.attribution.categoryLabel,
      startedAt: timer.startedAt,
      minutes: minutes,
      summary: timer.description,
      source: 'timer',
    );
    final item = await repository.createWorkItem(draft);
    activeTimer = null;
    _stopTicker();
    lastAttribution = timer.attribution;
    workItems = [...workItems, item]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _notify();
    return item;
  }

  Future<void> toggleTimer() async {
    if (activeTimer != null) {
      await stopTimer();
    } else {
      startTimer();
    }
  }

  void _startTicker() {
    _stopTicker();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (activeTimer != null && !activeTimer!.isPaused) _notify();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // --- Entry CRUD --------------------------------------------------------

  Future<WorkItem> createEntry(WorkItemDraft draft) async {
    final item = await repository.createWorkItem(draft);
    workItems = [...workItems, item]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (draft.type == WorkType.initiative && draft.initiativeId != null) {
      lastAttribution = AttributionChoice.initiative(
        draft.initiativeId!,
        initiativeById(draft.initiativeId!)?.name ?? 'Initiative',
      );
    } else if (draft.category != null) {
      lastAttribution = AttributionChoice.category(
        draft.category!,
        draft.categoryLabel ?? draft.category!,
      );
    }
    _notify();
    return item;
  }

  Future<WorkItem> quickAdd({
    required AttributionChoice attribution,
    required int minutes,
    required String summary,
    String outcome = '',
  }) {
    final startedAt = DateTime.now().subtract(Duration(minutes: minutes));
    return createEntry(
      WorkItemDraft(
        type: attribution.type,
        initiativeId: attribution.initiativeId,
        category: attribution.category,
        categoryLabel: attribution.categoryLabel ?? attribution.label,
        startedAt: startedAt,
        minutes: minutes,
        summary: summary,
        outcome: outcome,
        source: 'manual',
      ),
    );
  }

  Future<WorkItem> updateEntry(WorkItem item) async {
    final updated = await repository.updateWorkItem(item);
    workItems = [
      for (final existing in workItems)
        if (existing.id == updated.id) updated else existing,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _notify();
    return updated;
  }

  Future<void> deleteEntry(String id) async {
    await repository.deleteWorkItem(id);
    workItems = workItems.where((item) => item.id != id).toList();
    _notify();
  }

  Future<WorkItem> logSupport({
    required SupportMode mode,
    required String person,
    String? team,
    required int minutes,
    required String summary,
    String outcome = '',
    String? initiativeId,
    DateTime? startedAt,
  }) {
    return createEntry(
      WorkItemDraft(
        type: WorkType.category,
        initiativeId: initiativeId,
        category: mode.name,
        categoryLabel: mode.label,
        startedAt: startedAt ?? DateTime.now().subtract(Duration(minutes: minutes)),
        minutes: minutes,
        summary: summary,
        outcome: outcome,
        person: person,
        team: team,
        source: 'manual',
      ),
    );
  }

  // --- Initiatives -------------------------------------------------------

  Future<Initiative> createInitiative(InitiativeDraft draft) async {
    final initiative = await repository.createInitiative(draft);
    initiatives = [...initiatives, initiative];
    _notify();
    return initiative;
  }

  Future<Initiative> updateInitiative(Initiative initiative) async {
    final updated = await repository.updateInitiative(initiative);
    initiatives = [
      for (final existing in initiatives)
        if (existing.id == updated.id) updated else existing,
    ];
    _notify();
    return updated;
  }

  Future<Initiative> setInitiativeStatus(
    Initiative initiative,
    InitiativeStatus status,
  ) {
    return updateInitiative(initiative.copyWith(status: status));
  }

  Future<Initiative> setInitiativeProgress(Initiative initiative, int progress) {
    return updateInitiative(
      initiative.copyWith(progress: progress.clamp(0, 100)),
    );
  }

  // --- Notes -------------------------------------------------------------

  Future<Note> addNote({
    required String text,
    String? initiativeId,
    DateTime? date,
  }) async {
    final note = await repository.createNote(
      NoteDraft(
        date: isoDate(date ?? today),
        initiativeId: initiativeId,
        text: text,
      ),
    );
    notes = [note, ...notes];
    _notify();
    return note;
  }

  Future<Note> saveDayNote(String text) async {
    final existing = todayNote;
    if (existing == null) {
      return addNote(text: text);
    }
    final updated = await repository.updateNote(existing.copyWith(text: text));
    notes = [
      for (final note in notes)
        if (note.id == updated.id) updated else note,
    ];
    _notify();
    return updated;
  }

  // --- Check-ins ---------------------------------------------------------

  Future<CheckIn> createCheckIn(CheckInDraft draft) async {
    final checkIn = await repository.createCheckIn(draft);
    checkIns = [...checkIns, checkIn]
      ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));
    _notify();
    return checkIn;
  }

  Future<CheckIn> updateCheckIn(CheckIn checkIn) async {
    final updated = await repository.updateCheckIn(checkIn);
    checkIns = [
      for (final existing in checkIns)
        if (existing.id == updated.id) updated else existing,
    ];
    _notify();
    return updated;
  }

  Future<CheckIn> saveSummary(CheckIn checkIn, String markdown) {
    return updateCheckIn(
      checkIn.copyWith(
        summaryMarkdown: markdown,
        state: checkIn.state == CheckInState.final_
            ? CheckInState.final_
            : CheckInState.edited,
      ),
    );
  }

  Future<CheckIn> generateSummary(CheckIn checkIn) async {
    final updated = await repository.generateSummary(checkIn.id);
    checkIns = [
      for (final existing in checkIns)
        if (existing.id == updated.id) updated else existing,
    ];
    _notify();
    return updated;
  }

  Future<CheckIn> finalizeCheckIn(CheckIn checkIn) {
    return updateCheckIn(checkIn.copyWith(state: CheckInState.final_));
  }

  Future<String> buildPrompt(DateTime start, DateTime end) =>
      repository.buildPrompt(start, end);

  Future<ExportBundle> buildExport(DateTime start, DateTime end) =>
      repository.buildExport(start, end);

  // --- Settings ----------------------------------------------------------

  Future<AppSettings> saveSettings(AppSettings updated) async {
    settings = updated;
    _notify();
    final saved = await repository.updateSettings(updated);
    settings = saved;
    _notify();
    return saved;
  }

  Future<void> setTheme(ThemePreference theme) async {
    settings = settings.copyWith(theme: theme);
    _notify();
    await repository.updateSettings(settings);
  }

  Future<void> setDensity(DensityPreference density) async {
    settings = settings.copyWith(density: density);
    _notify();
    await repository.updateSettings(settings);
  }

  Future<BackupStatus> backupNow() async {
    final status = await repository.backupNow();
    settings = settings.copyWith(
      lastBackupAt: status.createdAt,
      lastBackupBytes: status.bytes,
    );
    _notify();
    return status;
  }

  void requestSearchFocus() {
    searchFocusRequest.value++;
  }

  AttributionChoice? _firstChoice() {
    final choices = attributionChoices;
    if (choices.isEmpty) return null;
    for (final choice in choices) {
      if (choice.isInitiative) return choice;
    }
    return choices.first;
  }

  void _ensureAttribution() {
    final choices = attributionChoices;
    if (choices.isEmpty) {
      lastAttribution = null;
      return;
    }
    final current = lastAttribution;
    if (current == null) {
      lastAttribution = _firstChoice();
      return;
    }
    final valid = choices.any((choice) => choice.key == current.key);
    if (!valid) lastAttribution = _firstChoice();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    searchFocusRequest.dispose();
    super.dispose();
  }
}
