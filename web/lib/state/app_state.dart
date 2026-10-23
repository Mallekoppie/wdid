import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../data/category_api.dart';
import '../data/demo_repository.dart';
import '../data/entry_api.dart';
import '../data/repository.dart';
import '../data/settings_api.dart';
import '../data/summary_api.dart';
import '../data/timer_api.dart';
import '../models/app_settings.dart';
import '../models/check_in.dart';
import '../models/drafts.dart';
import '../models/enums.dart';
import '../models/initiative.dart';
import '../models/note.dart';
import '../models/period_report.dart';
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

/// One Log listing request. The Log screen rebuilds it whenever a filter
/// changes, and mutations reload through it so overlap flags stay current.
class LogQuery {
  const LogQuery({
    required this.fromDate,
    required this.toDate,
    this.categoryId = '',
    this.subcategoryId = '',
    this.query = '',
  });

  /// Inclusive local calendar dates; the service resolves their boundaries in
  /// the configured timezone.
  final String fromDate;
  final String toDate;
  final String categoryId;
  final String subcategoryId;
  final String query;
}

class AppState extends ChangeNotifier {
  AppState(
    this.repository, {
    this.categoryApi,
    this.settingsApi,
    this.entryApi,
    this.timerApi,
    this.summaryApi,
  });

  final WdidRepository repository;

  /// Service-backed taxonomy, preferences and work entries. Null keeps the
  /// demo adapter, which is how screens without a service contract still run.
  final CategoryApi? categoryApi;
  final SettingsApi? settingsApi;
  final EntryApi? entryApi;
  final TimerApi? timerApi;

  /// Authoritative period aggregation. Null while a screen still runs on the
  /// demo adapter; Today then falls back to the demo's local week rollup.
  final SummaryApi? summaryApi;

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

  /// The service's report for the current week, which owns the week bars and
  /// the header's weekly total. It is reloaded after every entry mutation.
  PeriodReport? weekReport;
  String? weekReportError;

  /// The authoritative report for the current quarter. The Initiatives
  /// portfolio renders project time and last activity from it rather than
  /// composing either from entry listings.
  PeriodReport? initiativesReport;
  bool initiativesLoading = false;
  String? initiativesError;
  bool _initiativesLoaded = false;

  /// The entries for the Log's current filter, newest first.
  List<WorkEntry> logEntries = const [];
  Set<String> logOverlappingIds = const {};
  bool logLoading = false;
  String? logError;
  LogQuery? _logQuery;
  int _logRequest = 0;
  int _weekRequest = 0;
  int _initiativesRequest = 0;

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
      unawaited(loadWeekReport());
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
      entries = _newestFirst(loaded.entries);
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

  /// Loads the service's authoritative report for the current week. The
  /// service resolves "this week" from the user's timezone and week start, so
  /// the device clock cannot shift the period.
  Future<void> loadWeekReport() async {
    final api = summaryApi;
    if (api == null) return;

    final request = ++_weekRequest;
    weekReportError = null;
    _notify();
    try {
      final report = await api.getPeriodReport(currentWeek: true);
      if (request != _weekRequest) return;
      weekReport = report;
    } catch (error) {
      if (request != _weekRequest) return;
      weekReportError = error.toString();
    } finally {
      if (request == _weekRequest) _notify();
    }
  }

  /// Loads the authoritative report for the current quarter, which owns the
  /// Initiatives portfolio's project time and last activity.
  Future<void> loadInitiativesReport() async {
    final api = summaryApi;
    if (api == null) return;

    final request = ++_initiativesRequest;
    initiativesLoading = true;
    initiativesError = null;
    _notify();
    try {
      final report = await api.getPeriodReport(
        fromDate: isoDate(startOfQuarter(today)),
        toDate: todayIso,
      );
      if (request != _initiativesRequest) return;
      initiativesReport = report;
      _initiativesLoaded = true;
    } catch (error) {
      if (request != _initiativesRequest) return;
      initiativesError = error.toString();
    } finally {
      if (request == _initiativesRequest) {
        initiativesLoading = false;
        _notify();
      }
    }
  }

  void _refreshReports() {
    if (summaryApi == null) return;
    unawaited(loadWeekReport());
    // The portfolio only refreshes once a screen has asked for its report.
    if (_initiativesLoaded) unawaited(loadInitiativesReport());
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

  /// The current week's total. In service mode this is only ever the report's
  /// total: while the report is missing, the header shows zero rather than a
  /// locally composed number. The demo adapter keeps its local rollup.
  int get weekMinutes {
    if (summaryApi != null) return weekReport?.totalMinutes ?? 0;
    return totalMinutes(
      entriesForWeek(workItems, today, weekStart: settings.weekStart),
    );
  }

  /// Week bars in the shape the AllocationBars widget renders. The categories
  /// and minutes are the service's, never a recomputation from entries.
  List<AllocationSlice> get weekAllocation {
    if (summaryApi != null) {
      final report = weekReport;
      return report == null ? const [] : allocationForReport(report);
    }
    return allocationFor(
      entriesForWeek(workItems, today, weekStart: settings.weekStart),
      initiatives,
    );
  }

  List<Initiative> get openInitiatives =>
      initiatives.where((initiative) => !initiative.isArchived).toList();

  List<Initiative> get archivedInitiatives =>
      initiatives.where((initiative) => initiative.isArchived).toList();

  /// True when screens must read the live taxonomy instead of the demo seed.
  bool get hasTaxonomyService => categoryApi != null;

  /// Categories whose reporting role makes their subcategories projects.
  /// Archived categories stay here so their historical projects remain
  /// visible; archiving only removes the category from creation selectors.
  List<Category> get initiativeCategories => [
    for (final category in categories)
      if (category.role == CategoryRole.initiative) category,
  ];

  /// Initiative categories a new project can be filed under.
  List<Category> get selectableInitiativeCategories => [
    for (final category in initiativeCategories)
      if (!category.archived) category,
  ];

  bool _isInitiativeProject(Subcategory subcategory) =>
      categoryById(subcategory.categoryId)?.role == CategoryRole.initiative;

  List<Subcategory> get openProjects => [
    for (final subcategory in subcategories)
      if (!subcategory.archived && _isInitiativeProject(subcategory))
        subcategory,
  ]..sort(_byProjectOrder);

  List<Subcategory> get archivedProjects => [
    for (final subcategory in subcategories)
      if (subcategory.archived && _isInitiativeProject(subcategory))
        subcategory,
  ]..sort(_byProjectOrder);

  static int _byProjectOrder(Subcategory first, Subcategory second) {
    if (first.sortOrder != second.sortOrder) {
      return first.sortOrder.compareTo(second.sortOrder);
    }
    return first.name.toLowerCase().compareTo(second.name.toLowerCase());
  }

  /// The report's allocation for one project. Its time and last activity are
  /// authoritative, so the screen never adds entries itself.
  SubcategoryAllocation? allocationForProject(String subcategoryId) {
    for (final allocation
        in initiativesReport?.subcategories ??
            const <SubcategoryAllocation>[]) {
      if (allocation.subcategoryId == subcategoryId) return allocation;
    }
    return null;
  }

  /// Time the report attributes to initiative-role categories. It never
  /// includes support or other work, so it matches the portfolio's cards.
  int get initiativeMinutes {
    var minutes = 0;
    for (final category
        in initiativesReport?.categories ?? const <CategoryAllocation>[]) {
      if (category.role == CategoryRole.initiative) {
        minutes += category.minutes;
      }
    }
    return minutes;
  }

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
      _refreshReports();
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
        _refreshReports();
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

  /// Loads the Log's entries for one filter. Stale responses are dropped, so a
  /// fast sequence of filter changes always leaves the latest one on screen.
  Future<void> loadLog(LogQuery query) async {
    final api = entryApi;
    if (api == null) return;

    _logQuery = query;
    final request = ++_logRequest;
    logLoading = true;
    logError = null;
    _notify();
    try {
      final listing = await api.listEntries(
        fromDate: query.fromDate,
        toDate: query.toDate,
        categoryId: query.categoryId,
        subcategoryId: query.subcategoryId,
        query: query.query,
      );
      if (request != _logRequest) return;
      logEntries = _newestFirst(listing.entries);
      logOverlappingIds = listing.overlappingIds;
    } catch (error) {
      if (request != _logRequest) return;
      logError = error.toString();
    } finally {
      if (request == _logRequest) {
        logLoading = false;
        _notify();
      }
    }
  }

  /// Reloads whatever filter the Log last asked for, after a mutation.
  Future<void> refreshLog() async {
    final query = _logQuery;
    if (query == null) return;
    await loadLog(query);
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
  }) {
    final now = DateTime.now();
    return createWorkEntry(
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
  }

  /// Creates an entry with an explicit start, used by the Log's add form.
  Future<WorkEntry> createWorkEntry(EntryDraft draft) async {
    final entry = await _entryApi().createEntry(draft);
    if (entry.localDate == todayIso) {
      entries = _newestFirst([entry, ...entries]);
    }
    lastCategoryId = draft.categoryId;
    lastSubcategoryId = draft.subcategoryId;
    _refreshReports();
    _notify();
    return entry;
  }

  Future<WorkEntry> updateWorkEntry(WorkEntry entry) async {
    final updated = await _entryApi().updateEntry(entry);
    entries = _replaceEntry(entries, updated);
    logEntries = _replaceEntry(logEntries, updated);
    _refreshReports();
    _notify();
    return updated;
  }

  Future<void> deleteWorkEntry(String id) async {
    await _entryApi().deleteEntry(id);
    entries = entries.where((entry) => entry.id != id).toList();
    logEntries = logEntries.where((entry) => entry.id != id).toList();
    _refreshReports();
    _notify();
  }

  /// Splits one entry into two contiguous halves. The original identity stays
  /// with the first half, so open editors and selections follow it.
  Future<SplitHalves> splitEntry(String id, int atMinutes) async {
    final halves = await _entryApi().splitEntry(id, atMinutes);
    entries = _replaceWithHalves(entries, id, halves);
    logEntries = _replaceWithHalves(logEntries, id, halves);
    _refreshReports();
    _notify();
    return halves;
  }

  List<WorkEntry> _replaceEntry(List<WorkEntry> source, WorkEntry updated) {
    if (!source.any((entry) => entry.id == updated.id)) return source;
    return _newestFirst([
      for (final existing in source)
        if (existing.id == updated.id) updated else existing,
    ]);
  }

  List<WorkEntry> _replaceWithHalves(
    List<WorkEntry> source,
    String id,
    SplitHalves halves,
  ) {
    if (!source.any((entry) => entry.id == id)) return source;
    return _newestFirst([
      for (final existing in source)
        if (existing.id != id) existing,
      halves.first,
      halves.second,
    ]);
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

  /// Creates a project: a subcategory under an initiative-role category with
  /// the project fields the portfolio surfaces.
  Future<Subcategory> createProject({
    required Category category,
    required String name,
    String description = '',
    SubcategoryStatus status = SubcategoryStatus.active,
    int progress = 0,
    String targetOutcome = '',
    String targetDate = '',
    List<LinkRef> links = const [],
  }) async {
    final subcategory = await _categoryApi().createSubcategory(
      categoryId: category.id,
      name: name,
      description: description,
      status: status,
      progress: progress.clamp(0, 100),
      targetOutcome: targetOutcome,
      targetDate: targetDate,
      links: links,
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
      // Week start and timezone both move the period boundaries.
      _refreshReports();
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
