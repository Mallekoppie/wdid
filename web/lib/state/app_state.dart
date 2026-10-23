import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../data/category_api.dart';
import '../data/demo_repository.dart';
import '../data/entry_api.dart';
import '../data/repository.dart';
import '../data/settings_api.dart';
import '../data/timer_api.dart';
import '../models/app_settings.dart';
import '../models/check_in.dart';
import '../models/drafts.dart';
import '../models/enums.dart';
import '../models/initiative.dart';
import '../models/note.dart';
import '../models/taxonomy.dart';
import '../models/work_entry.dart';
import '../models/work_item.dart';
import '../utils/analytics.dart';
import '../utils/attribution.dart';
import '../utils/time_utils.dart';

enum AppStatus { loading, ready, error }

/// The timer as the UI renders it. In service mode it is a snapshot of the
/// server-owned timer; the client never advances the lifecycle by itself.
class ActiveTimer {
  ActiveTimer({
    required this.categoryId,
    this.subcategoryId = '',
    this.initiativeId,
    this.attribution,
    this.person = '',
    required this.description,
    required this.startedAt,
    required this.segmentStartedAt,
    this.accumulatedPaused = Duration.zero,
    this.pausedAt,
    this.baseElapsed,
    this.observedAt,
  });

  final String categoryId;
  final String subcategoryId;
  final String? initiativeId;

  /// Elapsed time at the moment the server built the snapshot, paired with
  /// [observedAt] so the UI ticks from server time instead of trusting the
  /// device clock.
  final Duration? baseElapsed;
  final DateTime? observedAt;

  /// Demo attribution, kept so the demo adapter can build a WorkItemDraft.
  final AttributionChoice? attribution;

  /// Required for support-role categories.
  final String person;
  String description;
  final DateTime startedAt;
  DateTime segmentStartedAt;
  Duration accumulatedPaused;
  DateTime? pausedAt;

  bool get isPaused => pausedAt != null;

  Duration elapsedAt(DateTime now) {
    if (pausedAt != null) return accumulatedPaused;

    final base = baseElapsed;
    final observed = observedAt;
    if (base != null && observed != null) {
      final delta = now.isAfter(observed)
          ? now.difference(observed)
          : Duration.zero;
      return base + delta;
    }

    final end = now.isAfter(segmentStartedAt) ? now : segmentStartedAt;
    return accumulatedPaused + end.difference(segmentStartedAt);
  }
}

/// What a stopped timer produced. A discarded timer has neither an entry nor
/// any minutes.
class StoppedTimer {
  const StoppedTimer({
    this.minutes = 0,
    this.summary = '',
    this.discarded = false,
  });

  final int minutes;
  final String summary;
  final bool discarded;
}

class AppState extends ChangeNotifier {
  AppState(
    this.repository, {
    this.categoryApi,
    this.settingsApi,
    this.entryApi,
    this.timerApi,
  });

  final WdidRepository repository;

  /// Service-backed taxonomy, preferences and work entries. Null keeps the
  /// demo adapter, which is how screens without a service contract still run.
  final CategoryApi? categoryApi;
  final SettingsApi? settingsApi;
  final EntryApi? entryApi;
  final TimerApi? timerApi;

  AppStatus status = AppStatus.loading;
  String? loadError;

  List<Initiative> initiatives = const [];
  List<WorkItem> workItems = const [];
  List<CheckIn> checkIns = const [];
  List<Note> notes = const [];
  AppSettings settings = const AppSettings();

  List<Category> categories = const [];
  List<Subcategory> subcategories = const [];
  bool taxonomyLoading = false;
  String? taxonomyError;
  bool preferencesLoading = false;
  String? preferencesError;
  AboutInfo? about;
  bool _taxonomyLoaded = false;

  /// The signed-in user's entries for today, newest first.
  List<WorkEntry> entries = const [];
  bool entriesLoading = false;
  String? entriesError;

  /// The last attribution used by quick capture, remembered for the next one.
  String? lastCategoryId;
  String? lastSubcategoryId;

  ActiveTimer? activeTimer;

  /// The block limit reported by the service, used by the stop prompt.
  int blockLimitMinutes = 240;
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
      if (categoryApi != null || settingsApi != null) {
        await Future.wait([loadTaxonomy(), loadPreferences()]);
      }
      if (timerApi != null) {
        await syncTimer();
        _startTicker();
      }
      _ensureAttribution();
      status = AppStatus.ready;
      _notify();
      unawaited(loadEntries());
    } catch (error) {
      status = AppStatus.error;
      loadError = error.toString();
    }
    _notify();
  }

  Future<void> reload() => load();

  /// Loads the service-backed taxonomy. Failures stay local to the Categories
  /// panel instead of taking down the whole journal.
  Future<void> loadTaxonomy() async {
    final api = categoryApi;
    if (api == null) return;

    taxonomyLoading = true;
    taxonomyError = null;
    _notify();
    try {
      final results = await Future.wait<dynamic>([
        api.listCategories(),
        api.listSubcategories(),
      ]);
      categories = List<Category>.from(results[0] as List<Category>);
      subcategories = List<Subcategory>.from(results[1] as List<Subcategory>);
      _taxonomyLoaded = true;
    } catch (error) {
      taxonomyError = error.toString();
    } finally {
      taxonomyLoading = false;
      _ensureAttribution();
      _notify();
    }
  }

  /// Loads the per-user preferences and About information.
  Future<void> loadPreferences() async {
    final api = settingsApi;
    if (api == null) return;

    preferencesLoading = true;
    preferencesError = null;
    _notify();
    try {
      final snapshot = await api.getSettings();
      about = snapshot.about;
      settings = snapshot.settings.copyWith(
        version: snapshot.about.version,
        schemaVersion: snapshot.about.schemaVersion,
        license: snapshot.about.license,
      );
    } catch (error) {
      preferencesError = error.toString();
    } finally {
      preferencesLoading = false;
      _notify();
    }
  }

  /// Loads today's work entries from the service. Failures stay local to the
  /// Today list instead of taking down the whole journal.
  Future<void> loadEntries() async {
    final api = entryApi;
    if (api == null) return;

    entriesLoading = true;
    entriesError = null;
    _notify();
    try {
      final loaded = await api.listEntries(today: true);
      entries = _newestFirst(loaded);
      // Prefill the capture selector from the most recent entry, so a reload
      // keeps the last used pair without adding a preference field.
      if (entries.isNotEmpty) {
        lastCategoryId ??= entries.first.categoryId;
        lastSubcategoryId ??= entries.first.subcategoryId;
      }
    } catch (error) {
      entriesError = error.toString();
    } finally {
      entriesLoading = false;
      _notify();
    }
  }

  /// Presentation-only choices for capture forms. Once a live taxonomy is
  /// loaded it is the source, so a newly created or renamed category appears
  /// in every entry selector immediately.
  List<AttributionChoice> get attributionChoices {
    if (categoryApi != null && _taxonomyLoaded) {
      return [
        for (final category in categories)
          if (!category.archived)
            AttributionChoice.category(
              category.id,
              category.name,
              categoryLabel: category.name,
            ),
      ];
    }
    return AttributionChoice.forInitiatives(initiatives);
  }

  List<Subcategory> subcategoriesFor(String categoryId) => subcategories
      .where((subcategory) => subcategory.categoryId == categoryId)
      .toList();

  /// The subcategories an entry selector offers, excluding archived rows.
  List<Subcategory> selectableSubcategoriesFor(String categoryId) =>
      subcategoriesFor(categoryId)
          .where((subcategory) => !subcategory.archived)
          .toList();

  /// The categories an entry selector offers, excluding archived rows.
  List<Category> get selectableCategories =>
      categories.where((category) => !category.archived).toList();

  Category? categoryById(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Subcategory? subcategoryById(String id) {
    for (final subcategory in subcategories) {
      if (subcategory.id == id) return subcategory;
    }
    return null;
  }

  bool get hasEntryService => entryApi != null;

  /// Entries loaded for today by the service, oldest first. The server owns
  /// the day boundary, so this never re-filters on the device's clock.
  List<WorkEntry> get todayEntries =>
      [...entries]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  int get todayEntryMinutes =>
      todayEntries.fold(0, (total, entry) => total + entry.minutes);

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

  List<Note> notesForInitiative(String initiativeId) =>
      notes.where((note) => note.initiativeId == initiativeId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<WorkItem> itemsForInitiative(String initiativeId) =>
      workItems.where((item) => item.initiativeId == initiativeId).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  int minutesForInitiative(String initiativeId) =>
      initiativeMinutesIn(workItems, initiativeId);

  // --- Timer -------------------------------------------------------------

  void setAttribution(AttributionChoice choice) {
    lastAttribution = choice;
    _notify();
  }

  /// The timer's display label, resolved from the live taxonomy. Demo timers
  /// carry their attribution label directly.
  String timerLabel(ActiveTimer timer) {
    final attribution = timer.attribution;
    if (attribution != null) return attribution.label;

    final category = categoryById(timer.categoryId);
    final subcategory = timer.subcategoryId.isEmpty
        ? null
        : subcategoryById(timer.subcategoryId);
    return [
      if (category != null)
        category.name
      else if (timer.categoryId.isNotEmpty)
        timer.categoryId,
      if (subcategory != null) subcategory.name,
    ].join(' · ');
  }

  bool timerIsInitiative(ActiveTimer timer) =>
      timer.attribution?.isInitiative ??
      categoryById(timer.categoryId)?.role == CategoryRole.initiative;

  String? timerInitiativeId(ActiveTimer timer) =>
      timer.attribution?.initiativeId;

  Future<void> startTimer({
    AttributionChoice? attribution,
    String description = '',
    String categoryId = '',
    String subcategoryId = '',
    String person = '',
  }) async {
    final api = timerApi;
    if (activeTimer != null) {
      // The snapshot may lag another tab by one poll. Ask the server before
      // refusing, otherwise a stopped timer blocks a legitimate start.
      if (api != null) await syncTimer();
      if (activeTimer != null) {
        throw const TimerFailure('A timer is already running.');
      }
    }

    if (api != null) {
      final resolvedCategory = categoryId.isNotEmpty
          ? categoryId
          : (lastCategoryId ?? '');
      var resolvedSubcategory = categoryId.isNotEmpty
          ? subcategoryId
          : (lastSubcategoryId ?? '');
      if (resolvedSubcategory.isNotEmpty &&
          subcategoryById(resolvedSubcategory)?.categoryId !=
              resolvedCategory) {
        resolvedSubcategory = '';
      }
      if (resolvedCategory.isEmpty) {
        throw const TimerFailure(
          'Choose a category on Today before starting the timer.',
        );
      }
      if (categoryById(resolvedCategory)?.role == CategoryRole.support &&
          person.trim().isEmpty) {
        throw const TimerFailure('Who are you supporting? Add a person first.');
      }
      try {
        _applySnapshot(
          await api.startTimer(
            categoryId: resolvedCategory,
            subcategoryId: resolvedSubcategory,
            description: description.trim(),
            person: person.trim(),
          ),
        );
      } catch (_) {
        // A second tab may have started or stopped a timer; align first.
        await syncTimer();
        rethrow;
      }
      lastCategoryId = resolvedCategory;
      lastSubcategoryId = resolvedSubcategory;
      _startTicker();
      _notify();
      return;
    }

    final choice = attribution ?? lastAttribution ?? _firstChoice();
    if (choice == null) {
      throw StateError(
        'Create an initiative or category before starting a timer.',
      );
    }
    lastAttribution = choice;
    final now = DateTime.now();
    activeTimer = ActiveTimer(
      categoryId: choice.category ?? choice.initiativeId ?? '',
      initiativeId: choice.initiativeId,
      attribution: choice,
      description: description.trim().isEmpty
          ? 'Focus block'
          : description.trim(),
      startedAt: now,
      segmentStartedAt: now,
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

  Future<void> pauseTimer() async {
    final timer = activeTimer;
    if (timer == null || timer.isPaused) return;

    final api = timerApi;
    if (api != null) {
      try {
        _applySnapshot(await api.pauseTimer());
      } catch (_) {
        await syncTimer();
        rethrow;
      }
    } else {
      timer.accumulatedPaused += DateTime.now().difference(
        timer.segmentStartedAt,
      );
      timer.pausedAt = DateTime.now();
    }
    _refreshTicker();
    _notify();
  }

  Future<void> resumeTimer() async {
    final timer = activeTimer;
    if (timer == null || !timer.isPaused) return;

    final api = timerApi;
    if (api != null) {
      try {
        _applySnapshot(await api.resumeTimer());
      } catch (_) {
        await syncTimer();
        rethrow;
      }
    } else {
      timer.pausedAt = null;
      timer.segmentStartedAt = DateTime.now();
    }
    _refreshTicker();
    _notify();
  }

  Future<StoppedTimer?> stopTimer({
    TimerStopAction action = TimerStopAction.save,
  }) async {
    final timer = activeTimer;
    if (timer == null) return null;

    final api = timerApi;
    if (api != null) {
      final StopTimerResult result;
      try {
        result = await api.stopTimer(action: action);
      } on TimerConflict {
        // The timer is still running; the caller asks the user what to do.
        rethrow;
      } catch (_) {
        await syncTimer();
        rethrow;
      }

      activeTimer = null;
      final entry = result.entry;
      if (entry != null) {
        entries = _newestFirst([entry, ...entries]);
        lastCategoryId = entry.categoryId;
        lastSubcategoryId = entry.subcategoryId;
      }
      _refreshTicker();
      _notify();
      return StoppedTimer(
        minutes: entry?.minutes ?? 0,
        summary: entry?.description ?? '',
        discarded: result.discarded,
      );
    }

    final now = DateTime.now();
    final elapsed = timer.elapsedAt(now);
    final minutes = elapsed.inMinutes < 1 ? 1 : elapsed.inMinutes;
    final attribution = timer.attribution;
    final draft = WorkItemDraft(
      type: attribution?.type ?? WorkType.category,
      initiativeId: attribution?.initiativeId,
      category: attribution?.category ?? timer.categoryId,
      categoryLabel: attribution?.categoryLabel ?? timer.categoryId,
      startedAt: timer.startedAt,
      minutes: minutes,
      summary: timer.description,
      source: 'timer',
    );
    final item = await repository.createWorkItem(draft);
    activeTimer = null;
    _stopTicker();
    lastAttribution = attribution ?? lastAttribution;
    workItems = [...workItems, item]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _notify();
    return StoppedTimer(minutes: item.minutes, summary: item.summary);
  }

  Future<void> toggleTimer() async {
    if (activeTimer != null) {
      await stopTimer();
    } else {
      await startTimer();
    }
  }

  /// Reads the server's timer snapshot. The client polls this so a refresh or
  /// a second tab follows the same timer instead of keeping its own state.
  Future<void> syncTimer() async {
    final api = timerApi;
    if (api == null) return;

    try {
      final status = await api.getActiveTimer();
      if (status.blockLimitMinutes > 0) {
        blockLimitMinutes = status.blockLimitMinutes;
      }
      final snapshot = status.timer;
      if (snapshot == null) {
        if (activeTimer == null) return;
        activeTimer = null;
        // Another tab stopped the timer; its saved entry belongs in Today.
        unawaited(loadEntries());
      } else {
        _applySnapshot(snapshot);
      }
      _notify();
    } catch (_) {
      // A transient poll failure keeps the last server snapshot. Mutations
      // surface their own errors.
    }
  }

  void _applySnapshot(TimerSnapshot snapshot) {
    activeTimer = ActiveTimer(
      categoryId: snapshot.categoryId,
      subcategoryId: snapshot.subcategoryId,
      description: snapshot.description,
      person: snapshot.person,
      startedAt: snapshot.startedAt,
      segmentStartedAt: snapshot.segmentStartedAt,
      accumulatedPaused: snapshot.accumulatedPaused,
      pausedAt: snapshot.pausedAt ?? (snapshot.paused ? DateTime.now() : null),
      baseElapsed: snapshot.elapsed,
      observedAt: DateTime.now(),
    );
  }

  void _refreshTicker() {
    if (timerApi != null) {
      _startTicker();
      return;
    }
    if (activeTimer != null && !activeTimer!.isPaused) {
      _startTicker();
    } else {
      _stopTicker();
    }
  }

  void _startTicker() {
    _stopTicker();
    var ticks = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      ticks++;
      if (activeTimer != null && !activeTimer!.isPaused) _notify();
      if (timerApi != null && ticks % 15 == 0) unawaited(syncTimer());
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

  // --- Service-backed entries -------------------------------------------

  EntryApi _entryApi() {
    final api = entryApi;
    if (api == null) {
      throw const ServicePendingException(
        'EntryService',
        'Work entries need the service contract.',
      );
    }
    return api;
  }

  /// Captures one line of work against a category and optional subcategory.
  /// The pair is remembered for the next capture.
  Future<WorkEntry> quickCapture({
    required String categoryId,
    String subcategoryId = '',
    required String description,
    required int minutes,
    String outcome = '',
    String person = '',
  }) async {
    final now = DateTime.now();
    final entry = await _entryApi().createEntry(
      EntryDraft(
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        description: description,
        outcome: outcome,
        startedAt: now.subtract(Duration(minutes: minutes)),
        minutes: minutes,
        person: person,
        source: EntrySource.manual,
      ),
    );

    entries = _newestFirst([entry, ...entries]);
    lastCategoryId = categoryId;
    lastSubcategoryId = subcategoryId;
    _notify();
    return entry;
  }

  Future<WorkEntry> updateWorkEntry(WorkEntry entry) async {
    final updated = await _entryApi().updateEntry(entry);
    entries = _newestFirst([
      for (final existing in entries)
        if (existing.id == updated.id) updated else existing,
    ]);
    _notify();
    return updated;
  }

  Future<void> deleteWorkEntry(String id) async {
    await _entryApi().deleteEntry(id);
    entries = entries.where((entry) => entry.id != id).toList();
    _notify();
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
        startedAt:
            startedAt ?? DateTime.now().subtract(Duration(minutes: minutes)),
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

  Future<Initiative> setInitiativeProgress(
    Initiative initiative,
    int progress,
  ) {
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

  // --- Categories --------------------------------------------------------

  CategoryApi _categoryApi() {
    final api = categoryApi;
    if (api == null) {
      throw const ServicePendingException(
        'CategoryService',
        'Settings → Categories needs the service contract.',
      );
    }
    return api;
  }

  Future<Category> createCategory({
    required String name,
    required CategoryRole role,
    String color = '',
  }) async {
    final category = await _categoryApi().createCategory(
      name: name,
      role: role,
      color: color,
      sortOrder: categories.length,
    );
    categories = [...categories, category];
    _notify();
    return category;
  }

  Future<Category> saveCategory(Category category) async {
    final updated = await _categoryApi().updateCategory(category);
    _replaceCategory(updated);
    _notify();
    return updated;
  }

  Future<Category> renameCategory(Category category, String name) =>
      saveCategory(category.copyWith(name: name.trim()));

  Future<Category> archiveCategory(
    Category category, {
    bool archived = true,
  }) async {
    final updated = await _categoryApi().archiveCategory(
      category.id,
      archived: archived,
    );
    _replaceCategory(updated);
    _notify();
    return updated;
  }

  Future<void> deleteCategory(Category category) async {
    await _categoryApi().deleteCategory(category.id);
    categories = categories
        .where((existing) => existing.id != category.id)
        .toList();
    subcategories = subcategories
        .where((existing) => existing.categoryId != category.id)
        .toList();
    _notify();
  }

  Future<Subcategory> createSubcategory({
    required Category category,
    required String name,
    SubcategoryStatus status = SubcategoryStatus.active,
  }) async {
    final subcategory = await _categoryApi().createSubcategory(
      categoryId: category.id,
      name: name,
      status: status,
      sortOrder: subcategoriesFor(category.id).length,
    );
    subcategories = [...subcategories, subcategory];
    _notify();
    return subcategory;
  }

  Future<Subcategory> saveSubcategory(Subcategory subcategory) async {
    final updated = await _categoryApi().updateSubcategory(subcategory);
    _replaceSubcategory(updated);
    _notify();
    return updated;
  }

  Future<Subcategory> renameSubcategory(Subcategory subcategory, String name) {
    return saveSubcategory(subcategory.copyWith(name: name.trim()));
  }

  Future<Subcategory> archiveSubcategory(
    Subcategory subcategory, {
    bool archived = true,
  }) async {
    final updated = await _categoryApi().archiveSubcategory(
      subcategory.id,
      archived: archived,
    );
    _replaceSubcategory(updated);
    _notify();
    return updated;
  }

  Future<void> deleteSubcategory(Subcategory subcategory) async {
    await _categoryApi().deleteSubcategory(subcategory.id);
    subcategories = subcategories
        .where((existing) => existing.id != subcategory.id)
        .toList();
    _notify();
  }

  // --- Settings ----------------------------------------------------------

  Future<AppSettings> saveSettings(AppSettings updated) async {
    final previous = settings;
    settings = updated;
    _notify();
    try {
      final saved = settingsApi != null
          ? await settingsApi!.updateSettings(updated)
          : await repository.updateSettings(updated);
      settings = saved.copyWith(
        version: about?.version,
        schemaVersion: about?.schemaVersion,
        license: about?.license,
      );
      _notify();
      return settings;
    } catch (error) {
      settings = previous;
      _notify();
      rethrow;
    }
  }

  Future<void> setTheme(ThemePreference theme) {
    return saveSettings(settings.copyWith(theme: theme));
  }

  Future<void> setDensity(DensityPreference density) {
    return saveSettings(settings.copyWith(density: density));
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

  List<WorkEntry> _newestFirst(Iterable<WorkEntry> items) =>
      items.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  void _replaceCategory(Category updated) {
    categories = [
      for (final existing in categories)
        if (existing.id == updated.id) updated else existing,
    ];
  }

  void _replaceSubcategory(Subcategory updated) {
    subcategories = [
      for (final existing in subcategories)
        if (existing.id == updated.id) updated else existing,
    ];
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
