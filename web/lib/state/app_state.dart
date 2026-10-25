import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../data/category_api.dart';
import '../data/checkin_api.dart';
import '../data/entry_api.dart';
import '../data/grpc_errors.dart';
import '../data/milestone_api.dart';
import '../data/note_api.dart';
import '../data/settings_api.dart';
import '../data/summary_api.dart';
import '../data/timer_api.dart';
import '../models/app_settings.dart';
import '../models/check_in.dart';
import '../models/drafts.dart';
import '../models/enums.dart';
import '../models/export_bundle.dart';
import '../models/link_ref.dart';
import '../models/milestone.dart';
import '../models/note.dart';
import '../models/period_report.dart';
import '../models/taxonomy.dart';
import '../models/work_entry.dart';
import '../utils/analytics.dart';
import '../utils/review_timeframe.dart';
import '../utils/time_utils.dart';

enum AppStatus { loading, ready, error }

/// The timer as the UI renders it. In service mode it is a snapshot of the
/// server-owned timer; the client never advances the lifecycle by itself.
class ActiveTimer {
  ActiveTimer({
    required this.categoryId,
    this.subcategoryId = '',
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

  /// Elapsed time at the moment the server built the snapshot, paired with
  /// [observedAt] so the UI ticks from server time instead of trusting the
  /// device clock.
  final Duration? baseElapsed;
  final DateTime? observedAt;

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

/// The attribution of a timer stopped by an interrupt, kept in memory so the
/// Today timer card and the stop snackbar can offer a fresh Resume timer.
///
/// This is UI state only: it never changes what the stopped entry stored, and
/// losing it on a reload is acceptable. Resuming consumes it.
class InterruptedTimer {
  const InterruptedTimer({
    required this.categoryId,
    this.subcategoryId = '',
    this.description = '',
    this.person = '',
  });

  final String categoryId;
  final String subcategoryId;
  final String description;

  /// Carried so resuming an interrupted support timer still satisfies the
  /// support-person requirement.
  final String person;
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
  AppState({
    this.categoryApi,
    this.settingsApi,
    this.entryApi,
    this.timerApi,
    this.summaryApi,
    this.noteApi,
    this.milestoneApi,
    this.checkInApi,
    this.roleCheck,
  });

  /// Resolves the signed-in account's admin role. Backups are instance-wide, so
  /// only an administrator may list, take or restore them.
  final bool Function()? roleCheck;

  /// The generated Connect clients. Production wires every one of them from
  /// `main.dart`; tests inject the in-memory fakes that implement the same
  /// interfaces.
  final CategoryApi? categoryApi;
  final SettingsApi? settingsApi;
  final EntryApi? entryApi;
  final TimerApi? timerApi;

  /// Authoritative period aggregation.
  final SummaryApi? summaryApi;

  /// Day notes and project notes.
  final NoteApi? noteApi;

  /// Project milestones.
  final MilestoneApi? milestoneApi;

  /// Manager check-ins and personal reviews.
  final CheckInApi? checkInApi;

  AppStatus status = AppStatus.loading;
  String? loadError;

  List<CheckIn> checkIns = const [];
  bool checkInsLoading = false;
  String? checkInsError;
  CheckInKind? checkInKindFilter;
  bool _checkInsLoaded = false;
  int _checkInsRequest = 0;

  /// The open check-in and the authoritative report for its period. The report
  /// owns category, project, support-by-person and weekly-rhythm aggregates, so
  /// the detail never adds entries up itself.
  CheckIn? checkInDetail;
  String? checkInDetailId;
  PeriodReport? checkInReport;
  bool checkInDetailLoading = false;
  String? checkInDetailError;
  int _checkInDetailRequest = 0;

  /// The live, unsaved review's authoritative report. It is keyed by its
  /// inclusive dates so a previous period never flashes while the next loads.
  PeriodReport? reviewReport;
  String? _reviewFromDate;
  String? _reviewToDate;
  bool reviewLoading = false;
  String? reviewError;
  int _reviewRequest = 0;

  /// The cadence period whose review prompt the user dismissed in this
  /// session. A dismissal lasts until the next weekly or monthly period.
  String? _dismissedReviewPromptPeriod;

  /// Today's notes loaded from the service, or every demo note. Day notes and
  /// project notes share the [Note] model.
  List<Note> notes = const [];
  bool notesLoading = false;
  String? notesError;

  /// The open project's notes, newest first, and the project they belong to.
  /// The id guard stops a previous project's notes from flashing while the
  /// next project loads.
  List<Note> projectNotes = const [];
  String? projectNotesProjectId;
  bool projectNotesLoading = false;
  String? projectNotesError;

  /// The open project's milestones, sorted by due date with undated ones last.
  /// The id guard stops a previous project's milestones from flashing.
  List<Milestone> projectMilestones = const [];
  String? projectMilestonesProjectId;
  bool projectMilestonesLoading = false;
  String? projectMilestonesError;

  AppSettings settings = const AppSettings();

  /// Instance-wide snapshots and status. Only administrators load them.
  List<BackupSnapshot> backups = const [];
  BackupStatusInfo? backupStatus;
  bool backupsLoading = false;
  String? backupsError;
  bool _backupsLoaded = false;

  List<Category> categories = const [];
  List<Subcategory> subcategories = const [];
  bool taxonomyLoading = false;
  String? taxonomyError;
  bool preferencesLoading = false;
  String? preferencesError;
  AboutInfo? about;

  /// Roster edits made while the real preferences were unavailable, keyed
  /// case-insensitively. A null value means remove. The last edit for a name
  /// wins, so an add followed by a remove never survives a late load.
  final Map<String, String?> _pendingRoster = {};

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

  /// The project detail's timeline, newest first, and the project it belongs
  /// to. The id guard stops a previous project's entries from flashing while
  /// the next project loads.
  List<WorkEntry> projectEntries = const [];
  String? projectEntriesProjectId;
  bool projectEntriesLoading = false;
  String? projectEntriesError;

  /// The entries for the Log's current filter, newest first.
  List<WorkEntry> logEntries = const [];
  Set<String> logOverlappingIds = const {};
  bool logLoading = false;
  String? logError;
  LogQuery? _logQuery;
  int _logRequest = 0;

  /// The Support screen's entries for its selected period, newest first. The
  /// listing is fetched per support-role category, so support work never mixes
  /// with an initiative's project timeline.
  List<WorkEntry> supportEntries = const [];

  /// The authoritative report for the Support screen's selected period. Its
  /// person and mode allocations are the rollups, so the screen never composes
  /// them from the loaded entries. Null until the first report arrives.
  PeriodReport? supportReport;
  bool supportLoading = false;
  String? supportError;
  String? _supportFromDate;
  String? _supportToDate;
  int _supportRequest = 0;
  int _weekRequest = 0;
  int _initiativesRequest = 0;
  int _projectEntriesRequest = 0;
  int _projectNotesRequest = 0;
  int _projectMilestonesRequest = 0;

  /// The last attribution used by quick capture, remembered for the next one.
  String? lastCategoryId;
  String? lastSubcategoryId;

  /// The most recently used support-role category. Kept separately from
  /// [lastCategoryId] so a later initiative capture does not erase which
  /// support category the one-tap support flows should start with.
  String? _lastSupportCategoryId;

  /// The interrupt's resume target. Memory only; cleared when resumed.
  InterruptedTimer? _interruptedTimer;

  ActiveTimer? activeTimer;

  /// The block limit reported by the service, used by the stop prompt.
  int blockLimitMinutes = 240;

  /// Screens listen to this to focus their search field on `/`.
  final ValueNotifier<int> searchFocusRequest = ValueNotifier<int>(0);

  Timer? _ticker;
  bool _disposed = false;

  /// True when the account carries the admin role. Backups cover the whole
  /// instance, so only an administrator manages them.
  bool get isAdmin => roleCheck?.call() ?? false;

  bool get hasBackupService => settingsApi != null;

  bool get canManageBackups => hasBackupService && isAdmin;

  DateTime get today => dateOnly(DateTime.now());
  String get todayIso => isoDate(today);

  Future<void> load() async {
    status = AppStatus.loading;
    loadError = null;
    _notify();
    try {
      if (categoryApi != null) await loadTaxonomy();
      if (settingsApi != null) await loadPreferences();
      if (noteApi != null) await loadNotes();
      if (checkInApi != null) await loadCheckIns(force: true);
      if (timerApi != null) {
        await syncTimer();
        _startTicker();
      }
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
    } catch (error) {
      taxonomyError = error.toString();
    } finally {
      taxonomyLoading = false;
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
    var replayPendingRoster = false;
    try {
      final snapshot = await api.getSettings();
      about = snapshot.about;
      final loaded = snapshot.settings.copyWith(
        version: snapshot.about.version,
        schemaVersion: snapshot.about.schemaVersion,
        license: snapshot.about.license,
      );
      if (_pendingRoster.isEmpty) {
        settings = loaded;
      } else {
        // Roster edits queued during the gate win over the server's copy, but
        // every other preference still comes from the server unchanged.
        settings = loaded.copyWith(
          supportPeople: List<String>.unmodifiable(
            _applyPendingRoster(loaded.supportPeople),
          ),
        );
        replayPendingRoster = true;
      }
    } catch (error) {
      preferencesError = error.toString();
    } finally {
      preferencesLoading = false;
      _notify();
    }
    // Replay after the loading gate opens so the write carries the real
    // preferences instead of the defaults.
    if (replayPendingRoster) await _persistSupportPeople();
  }

  /// Applies queued roster edits on top of the server's roster.
  List<String> _applyPendingRoster(List<String> base) {
    final people = [...base];
    _pendingRoster.forEach((key, name) {
      final index = people.indexWhere((person) => person.toLowerCase() == key);
      if (name == null) {
        if (index != -1) people.removeAt(index);
      } else if (index == -1) {
        people.add(name);
      }
    });
    return people;
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

  /// Loads one project's full work-entry timeline. EntryService filters by
  /// subcategory, so the detail never sifts through unrelated entries.
  Future<void> loadProjectEntries(String subcategoryId) async {
    final api = entryApi;
    if (api == null) return;

    final request = ++_projectEntriesRequest;
    if (projectEntriesProjectId != subcategoryId) {
      projectEntries = const [];
      projectEntriesProjectId = subcategoryId;
    }
    projectEntriesLoading = true;
    projectEntriesError = null;
    _notify();
    try {
      final listing = await api.listEntries(subcategoryId: subcategoryId);
      if (request != _projectEntriesRequest) return;
      projectEntries = _newestFirst(listing.entries);
    } catch (error) {
      if (request != _projectEntriesRequest) return;
      projectEntriesError = error.toString();
    } finally {
      if (request == _projectEntriesRequest) {
        projectEntriesLoading = false;
        _notify();
      }
    }
  }

  /// Loads today's notes from the service. Today's end-of-day note is one of
  /// them; a failure stays local to the note card instead of taking down the
  /// journal.
  Future<void> loadNotes() async {
    final api = noteApi;
    if (api == null) return;

    notesLoading = true;
    notesError = null;
    _notify();
    try {
      notes = _newestFirstNotes(await api.listNotes(date: todayIso));
    } catch (error) {
      notesError = error.toString();
    } finally {
      notesLoading = false;
      _notify();
    }
  }

  /// Loads one project's notes, newest first. NoteService filters by
  /// subcategory, so the detail never sifts through unrelated notes.
  Future<void> loadProjectNotes(String subcategoryId) async {
    final api = noteApi;
    if (api == null) return;

    final request = ++_projectNotesRequest;
    if (projectNotesProjectId != subcategoryId) {
      projectNotes = const [];
      projectNotesProjectId = subcategoryId;
    }
    projectNotesLoading = true;
    projectNotesError = null;
    _notify();
    try {
      final loaded = await api.listNotes(subcategoryId: subcategoryId);
      if (request != _projectNotesRequest) return;
      projectNotes = _newestFirstNotes(loaded);
    } catch (error) {
      if (request != _projectNotesRequest) return;
      projectNotesError = error.toString();
    } finally {
      if (request == _projectNotesRequest) {
        projectNotesLoading = false;
        _notify();
      }
    }
  }

  /// Loads one project's milestones. Completion counts come from the
  /// authoritative report, so this listing only carries the checkpoints.
  Future<void> loadProjectMilestones(String subcategoryId) async {
    final api = milestoneApi;
    if (api == null) return;

    final request = ++_projectMilestonesRequest;
    if (projectMilestonesProjectId != subcategoryId) {
      projectMilestones = const [];
      projectMilestonesProjectId = subcategoryId;
    }
    projectMilestonesLoading = true;
    projectMilestonesError = null;
    _notify();
    try {
      final loaded = await api.listMilestones(subcategoryId: subcategoryId);
      if (request != _projectMilestonesRequest) return;
      projectMilestones = _sortedMilestones(loaded);
    } catch (error) {
      if (request != _projectMilestonesRequest) return;
      projectMilestonesError = error.toString();
    } finally {
      if (request == _projectMilestonesRequest) {
        projectMilestonesLoading = false;
        _notify();
      }
    }
  }

  /// Reloads the open project's timeline only when [subcategoryId] is that
  /// project, so unrelated mutations do not clear what the user is reading.
  void _refreshProjectIfOpen(String subcategoryId) {
    final openId = projectEntriesProjectId;
    if (openId == null || openId != subcategoryId) return;
    unawaited(loadProjectEntries(openId));
  }

  void _refreshReports() {
    if (summaryApi == null) return;
    unawaited(loadWeekReport());
    // The portfolio only refreshes once a screen has asked for its report.
    if (_initiativesLoaded) unawaited(loadInitiativesReport());
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

  /// A project is the subcategory under an initiative-role category, so the
  /// detail route addresses the same record the portfolio lists.
  Subcategory? projectById(String id) {
    final subcategory = subcategoryById(id);
    if (subcategory == null) return null;
    return categoryById(subcategory.categoryId)?.role == CategoryRole.initiative
        ? subcategory
        : null;
  }

  bool get hasEntryService => entryApi != null;

  /// Entries loaded for today by the service, oldest first. The server owns
  /// the day boundary, so this never re-filters on the device's clock.
  List<WorkEntry> get todayEntries =>
      [...entries]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  int get todayEntryMinutes =>
      todayEntries.fold(0, (total, entry) => total + entry.minutes);

  /// The current week's total. It is only ever the report's total: while the
  /// report is missing, the header shows zero rather than a locally composed
  /// number.
  int get weekMinutes => weekReport?.totalMinutes ?? 0;

  /// Week bars in the shape the AllocationBars widget renders. The categories
  /// and minutes are the service's, never a recomputation from entries.
  List<AllocationSlice> get weekAllocation {
    final report = weekReport;
    return report == null ? const [] : allocationForReport(report);
  }

  /// True when the live taxonomy client is wired.
  bool get hasTaxonomyService => categoryApi != null;

  /// Categories whose reporting role makes their subcategories projects.
  /// Archived categories stay here so their historical projects remain
  /// visible; archiving only removes the category from creation selectors.
  List<Category> get initiativeCategories => [
    for (final category in categories)
      if (category.role == CategoryRole.initiative) category,
  ];

  /// Support is a reporting role, not a category name. Every support-role
  /// category stays here so its history is readable after archiving.
  List<Category> get supportCategories => [
    for (final category in categories)
      if (category.role == CategoryRole.support) category,
  ];

  /// Support modes are the subcategories of support-role categories, ordered
  /// as the taxonomy is. A mode's category decides how the entry is filed.
  List<Subcategory> get supportModes {
    final ordered = <Subcategory>[];
    for (final category in supportCategories) {
      final modes = subcategoriesFor(category.id)
        ..sort((first, second) {
          if (first.sortOrder != second.sortOrder) {
            return first.sortOrder.compareTo(second.sortOrder);
          }
          return first.name.toLowerCase().compareTo(second.name.toLowerCase());
        });
      ordered.addAll(modes);
    }
    return ordered;
  }

  /// The support modes a new entry can use, excluding archived rows and modes
  /// whose support category is archived (or no longer known). A mode under an
  /// archived category would re-file an entry somewhere no selector shows.
  List<Subcategory> get selectableSupportModes => [
    for (final mode in supportModes)
      if (!mode.archived && !(categoryById(mode.categoryId)?.archived ?? true))
        mode,
  ];

  /// Support-role categories a new timer can start under, excluding archived
  /// rows.
  List<Category> get selectableSupportCategories => [
    for (final category in supportCategories)
      if (!category.archived) category,
  ];

  /// The support category the one-tap support flows start with.
  ///
  /// This is the most recently used support category, then the remembered
  /// capture category when it is support, and finally the first selectable
  /// support category. With more than one support-role category the newest
  /// history wins; the ticket's explicit assumption.
  Category? get defaultSupportCategory {
    final selectable = selectableSupportCategories;
    if (selectable.isEmpty) return null;

    bool matches(Category category, String? id) =>
        id != null && category.id == id;

    for (final category in selectable) {
      if (matches(category, _lastSupportCategoryId)) return category;
    }
    for (final category in selectable) {
      if (matches(category, lastCategoryId)) return category;
    }
    return selectable.first;
  }

  /// The most recently used support category, if any.
  String? get lastSupportCategoryId => _lastSupportCategoryId;

  /// True when the category is a support-role category, so the caller can
  /// require a person and keep the entry off project timelines.
  bool isSupportCategory(String categoryId) =>
      categoryById(categoryId)?.role == CategoryRole.support;

  /// The mode label for an entry, resolved from the live taxonomy.
  String supportModeLabel(String subcategoryId) {
    if (subcategoryId.isEmpty) return 'No mode';
    return subcategoryById(subcategoryId)?.name ?? 'No mode';
  }

  /// The attribution of the timer an interrupt stopped, for "Resume …".
  /// Empty when there is no stash.
  String get interruptedTimerLabel {
    final stash = _interruptedTimer;
    if (stash == null) return '';
    final subcategory = subcategoryById(stash.subcategoryId);
    return [
      categoryById(stash.categoryId)?.name ?? 'Unknown category',
      if (subcategory != null) subcategory.name,
      if (stash.person.isNotEmpty) stash.person,
    ].join(' · ');
  }

  /// The attribution an interrupt saved for Resume, or null.
  InterruptedTimer? get interruptedTimer => _interruptedTimer;

  /// Stashes the attribution of the timer an interrupt stopped. A new
  /// interrupt overwrites any previous stash.
  void setInterruptedTimer(InterruptedTimer stash) {
    _interruptedTimer = stash;
    _notify();
  }

  /// Forgets the stash without starting anything.
  void clearInterruptedTimer() {
    if (_interruptedTimer == null) return;
    _interruptedTimer = null;
    _notify();
  }

  /// Starts a fresh timer with the stashed attribution and consumes the stash.
  /// The stopped block is never reused; this is new elapsed time.
  Future<void> resumeInterruptedTimer() async {
    final stash = _interruptedTimer;
    if (stash == null) return;
    // Preserve while starting so a failed start keeps the offer; consume only
    // once the new timer exists.
    await startTimer(
      categoryId: stash.categoryId,
      subcategoryId: stash.subcategoryId,
      description: stash.description,
      person: stash.person,
      preserveInterruptedTimer: true,
    );
    clearInterruptedTimer();
  }

  /// Starts a support timer with one tap: the default support category, no
  /// mode and no description. "Interrupt" is UI state only; the stored entry
  /// is an ordinary support entry. [preserveInterruptedTimer] keeps the
  /// interrupt stash when this start is the second half of an interruption.
  Future<void> startSupportTimer({
    required String person,
    Category? category,
    bool preserveInterruptedTimer = false,
  }) {
    final target = category ?? defaultSupportCategory;
    if (target == null) {
      throw const TimerFailure(
        'Add a support category before starting support.',
      );
    }
    return startTimer(
      categoryId: target.id,
      subcategoryId: '',
      description: '',
      person: person,
      preserveInterruptedTimer: preserveInterruptedTimer,
    );
  }

  void _rememberSupportCategory(String categoryId) {
    if (categoryId.isNotEmpty && isSupportCategory(categoryId)) {
      _lastSupportCategoryId = categoryId;
    }
  }

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

  /// The report's milestone completion for one project, or null when the
  /// project has no milestones. The report owns these counts so the UI never
  /// recomputes completion from the milestone listing.
  MilestoneProgress? milestoneProgressForProject(String subcategoryId) {
    for (final progress
        in initiativesReport?.milestoneProgress ??
            const <MilestoneProgress>[]) {
      if (progress.subcategoryId == subcategoryId) return progress;
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

  /// The boundary for the next manager check-in. Only a final manager check-in
  /// counts; personal reviews and drafts never move it.
  CheckIn? get latestFinalManagerCheckIn {
    CheckIn? latest;
    for (final checkIn in checkIns) {
      if (!checkIn.isManager || !checkIn.isFinal) continue;
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

  /// The local boundary: the day after the last final manager check-in, or
  /// the journal start date, or today.
  DateTime get defaultCheckInStart {
    final latest = latestFinalManagerCheckIn;
    if (latest != null) return addDays(latest.periodEnd, 1);
    final journal = DateTime.tryParse(settings.journalStartDate);
    if (journal != null) return dateOnly(journal);
    return today;
  }

  Note? get todayNote {
    for (final note in notes) {
      if (note.date == todayIso && note.initiativeId == null) return note;
    }
    return null;
  }

  /// A project's notes, newest first, from the per-project listing.
  List<Note> notesForProject(String projectId) {
    return projectNotesProjectId == projectId
        ? List<Note>.unmodifiable(projectNotes)
        : const [];
  }

  // --- Timer -------------------------------------------------------------

  /// The timer's display label, resolved from the live taxonomy.
  String timerLabel(ActiveTimer timer) {
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
      categoryById(timer.categoryId)?.role == CategoryRole.initiative;

  /// The initiative project the running timer is filed under, when its
  /// subcategory is one.
  String? timerInitiativeId(ActiveTimer timer) {
    final subcategoryId = timer.subcategoryId;
    if (subcategoryId.isEmpty) return null;
    return projectById(subcategoryId) == null ? null : subcategoryId;
  }

  /// Starts a timer. A manual start retires any interrupt stash, because the
  /// old Resume offer would otherwise point at a block the user has moved on
  /// from. The interrupt flow passes [preserveInterruptedTimer] so support can
  /// end before the interrupted work is offered again.
  Future<void> startTimer({
    String description = '',
    String categoryId = '',
    String subcategoryId = '',
    String person = '',
    bool preserveInterruptedTimer = false,
  }) async {
    final api = timerApi;
    if (api == null) {
      throw const ServicePendingException(
        'TimerService',
        'Starting a timer needs the service contract.',
      );
    }
    if (activeTimer != null) {
      // The snapshot may lag another tab by one poll. Ask the server before
      // refusing, otherwise a stopped timer blocks a legitimate start.
      await syncTimer();
      if (activeTimer != null) {
        throw const TimerFailure('A timer is already running.');
      }
    }

    {
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
      // Only a successful start retires the offer: a failed one keeps it
      // resumable.
      if (!preserveInterruptedTimer) _interruptedTimer = null;
      lastCategoryId = resolvedCategory;
      lastSubcategoryId = resolvedSubcategory;
      _rememberSupportCategory(resolvedCategory);
      _startTicker();
      _notify();
    }
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
    if (api == null) {
      throw const ServicePendingException(
        'TimerService',
        'Pausing a timer needs the service contract.',
      );
    }
    try {
      _applySnapshot(await api.pauseTimer());
    } catch (_) {
      await syncTimer();
      rethrow;
    }
    _refreshTicker();
    _notify();
  }

  Future<void> resumeTimer() async {
    final timer = activeTimer;
    if (timer == null || !timer.isPaused) return;

    final api = timerApi;
    if (api == null) {
      throw const ServicePendingException(
        'TimerService',
        'Resuming a timer needs the service contract.',
      );
    }
    try {
      _applySnapshot(await api.resumeTimer());
    } catch (_) {
      await syncTimer();
      rethrow;
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
    if (api == null) {
      throw const ServicePendingException(
        'TimerService',
        'Stopping a timer needs the service contract.',
      );
    }
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
      _rememberSupportCategory(entry.categoryId);
      // A saved block must appear in an already-loaded Log and Support view,
      // not only in Today and the reports.
      unawaited(refreshLog());
      _refreshSupportIfLoaded();
    }
    _refreshTicker();
    _refreshReports();
    if (entry != null) _refreshProjectIfOpen(entry.subcategoryId);
    _notify();
    return StoppedTimer(
      minutes: entry?.minutes ?? 0,
      summary: entry?.description ?? '',
      discarded: result.discarded,
    );
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

  /// Loads the Support screen's entries for an inclusive local-date range and
  /// the authoritative report that owns its rollups. Support is one or more
  /// support-role categories, so each is listed and the results are merged
  /// newest first. Archived categories stay included so their history remains
  /// readable.
  Future<void> loadSupport({
    required String fromDate,
    required String toDate,
  }) async {
    final api = entryApi;
    if (api == null) return;

    _supportFromDate = fromDate;
    _supportToDate = toDate;
    final request = ++_supportRequest;
    final categoryCount = supportCategories.length;
    supportLoading = true;
    supportError = null;
    supportReport = null;
    _notify();
    try {
      // The listings and the report are independent, so one round trip each
      // runs in parallel; Future.wait also attaches an error handler to both.
      final results = await Future.wait<Object?>([
        for (final category in supportCategories)
          api.listEntries(
            categoryId: category.id,
            fromDate: fromDate,
            toDate: toDate,
          ),
        if (summaryApi != null)
          summaryApi!.getPeriodReport(fromDate: fromDate, toDate: toDate),
      ]);
      if (request != _supportRequest) return;
      final listings = results.take(categoryCount).cast<EntryListing>();
      supportEntries = _newestFirst(
        listings.expand((listing) => listing.entries),
      );
      if (summaryApi != null) {
        supportReport = results.last as PeriodReport;
      }
    } catch (error) {
      if (request != _supportRequest) return;
      supportError = error.toString();
    } finally {
      if (request == _supportRequest) {
        supportLoading = false;
        _notify();
      }
    }
  }

  /// Reloads the Support screen's last period after a support entry changes.
  Future<void> refreshSupport() async {
    final from = _supportFromDate;
    final to = _supportToDate;
    if (from == null || to == null) return;
    await loadSupport(fromDate: from, toDate: to);
  }

  void _refreshSupportIfLoaded() {
    final from = _supportFromDate;
    final to = _supportToDate;
    if (from == null || to == null) return;
    unawaited(loadSupport(fromDate: from, toDate: to));
  }

  /// Loads the caller's check-ins from the service, newest first. A null
  /// [checkInKindFilter] lists both manager check-ins and personal reviews;
  /// the filter itself is applied by the service.
  Future<void> loadCheckIns({bool force = false}) async {
    final api = checkInApi;
    if (api == null) return;
    if (!force && _checkInsLoaded && !checkInsLoading) return;

    final request = ++_checkInsRequest;
    checkInsLoading = true;
    checkInsError = null;
    _notify();
    try {
      final loaded = await api.listCheckIns(kind: checkInKindFilter);
      if (request != _checkInsRequest) return;
      checkIns = [...loaded]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _checkInsLoaded = true;
    } catch (error) {
      if (request != _checkInsRequest) return;
      checkInsError = error.toString();
    } finally {
      if (request == _checkInsRequest) {
        checkInsLoading = false;
        _notify();
      }
    }
  }

  /// Narrows the check-in listing and reloads it from the service.
  Future<void> setCheckInKindFilter(CheckInKind? kind) async {
    if (checkInKindFilter == kind) return;
    checkInKindFilter = kind;
    _notify();
    await loadCheckIns(force: true);
  }

  /// Loads one check-in and the authoritative period report for its period.
  /// The report is what the detail renders; the client never composes its
  /// category, project, support or weekly totals from entries.
  Future<void> loadCheckInDetail(String id, {bool force = false}) async {
    final api = checkInApi;
    if (api == null) return;
    if (!force &&
        checkInDetailId == id &&
        (checkInDetail?.id == id || checkInDetailLoading)) {
      return;
    }

    final request = ++_checkInDetailRequest;
    if (checkInDetailId != id) {
      checkInDetail = null;
      checkInReport = null;
    }
    checkInDetailId = id;
    checkInDetailLoading = true;
    checkInDetailError = null;
    _notify();
    try {
      final loaded = await api.getCheckIn(id);
      PeriodReport? report;
      if (summaryApi != null) {
        report = await summaryApi!.getPeriodReport(
          fromDate: isoDate(loaded.periodStart),
          toDate: isoDate(loaded.periodEnd),
        );
      }
      if (request != _checkInDetailRequest) return;
      checkInDetail = loaded;
      checkInReport = report;
      _upsertCheckIn(loaded);
    } catch (error) {
      if (request != _checkInDetailRequest) return;
      checkInDetailError = error.toString();
    } finally {
      if (request == _checkInDetailRequest) {
        checkInDetailLoading = false;
        _notify();
      }
    }
  }

  CheckIn? checkInById(String id) {
    if (checkInDetail?.id == id) return checkInDetail;
    for (final checkIn in checkIns) {
      if (checkIn.id == id) return checkIn;
    }
    return null;
  }

  /// Loads the authoritative report for an unsaved review period. It is the
  /// same aggregate source a saved check-in detail reads, so the live review
  /// and the saved artifact agree. When no summary service is connected the
  /// screen explains that aggregates are unavailable; nothing is fabricated.
  Future<void> loadReviewReport(
    DateTime start,
    DateTime end, {
    bool force = false,
  }) async {
    final from = isoDate(start);
    final to = isoDate(end);
    if (from == _reviewFromDate &&
        to == _reviewToDate &&
        reviewReport != null &&
        !force) {
      return;
    }

    final api = summaryApi;
    final request = ++_reviewRequest;
    _reviewFromDate = from;
    _reviewToDate = to;
    reviewReport = null;
    reviewError = null;
    reviewLoading = api != null;
    _notify();
    if (api == null) return;

    try {
      final report = await api.getPeriodReport(fromDate: from, toDate: to);
      if (request != _reviewRequest) return;
      reviewReport = report;
    } catch (error) {
      if (request != _reviewRequest) return;
      reviewError = error.toString();
    } finally {
      if (request == _reviewRequest) {
        reviewLoading = false;
        _notify();
      }
    }
  }

  /// The saved personal review with the latest creation time, if any.
  CheckIn? get latestPersonalReview {
    CheckIn? latest;
    for (final checkIn in checkIns) {
      if (!checkIn.isPersonal) continue;
      if (latest == null || checkIn.createdAt.isAfter(latest.createdAt)) {
        latest = checkIn;
      }
    }
    return latest;
  }

  /// The current weekly or monthly cadence period, keyed by its first day.
  /// Dismissals and due-checks compare this key, so the prompt appears once
  /// per period rather than every time Today rebuilds.
  String get reviewPromptPeriodKey {
    switch (settings.reviewCadence) {
      case ReviewCadence.weekly:
        return 'week:${isoDate(startOfWeek(today, weekStart: settings.weekStart))}';
      case ReviewCadence.monthly:
        return 'month:${today.year}-${today.month.toString().padLeft(2, '0')}';
      case ReviewCadence.off:
        return '';
    }
  }

  /// True when the configured cadence has not yet produced a personal review
  /// in the current period and the prompt has not been dismissed. It is only a
  /// hint: nothing is created until the user saves a review.
  bool get reviewPromptDue {
    if (settings.reviewCadence == ReviewCadence.off) return false;
    if (!hasCheckInService) return false;
    final key = reviewPromptPeriodKey;
    if (key.isEmpty || _dismissedReviewPromptPeriod == key) return false;

    final periodStart = switch (settings.reviewCadence) {
      ReviewCadence.weekly => startOfWeek(today, weekStart: settings.weekStart),
      _ => DateTime(today.year, today.month, 1),
    };
    for (final checkIn in checkIns) {
      if (!checkIn.isPersonal) continue;
      if (!dateOnly(checkIn.createdAt).isBefore(periodStart)) return false;
    }
    return true;
  }

  /// The range the cadence prompt opens when the user accepts it.
  ReviewPeriod get reviewPromptPeriod => reviewPromptPeriodFor(
    settings.reviewCadence,
    today: today,
    boundaryStart: defaultCheckInStart,
    weekStart: settings.weekStart,
  );

  /// Silences the review prompt for the current cadence period only.
  void dismissReviewPrompt() {
    _dismissedReviewPromptPeriod = reviewPromptPeriodKey;
    _notify();
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
    _rememberSupportCategory(draft.categoryId);
    _refreshProjectIfOpen(entry.subcategoryId);
    _refreshSupportIfLoaded();
    _refreshReports();
    _notify();
    return entry;
  }

  Future<WorkEntry> updateWorkEntry(WorkEntry entry) async {
    final updated = await _entryApi().updateEntry(entry);
    entries = _replaceEntry(entries, updated);
    logEntries = _replaceEntry(logEntries, updated);
    _rememberSupportCategory(updated.categoryId);
    // The entry may have moved into or out of the open project.
    if (projectEntries.any((existing) => existing.id == updated.id)) {
      _refreshProjectIfOpen(projectEntriesProjectId!);
    } else {
      _refreshProjectIfOpen(updated.subcategoryId);
    }
    _refreshSupportIfLoaded();
    _refreshReports();
    _notify();
    return updated;
  }

  Future<void> deleteWorkEntry(String id) async {
    await _entryApi().deleteEntry(id);
    if (projectEntries.any((entry) => entry.id == id)) {
      _refreshProjectIfOpen(projectEntriesProjectId!);
    }
    entries = entries.where((entry) => entry.id != id).toList();
    logEntries = logEntries.where((entry) => entry.id != id).toList();
    _refreshSupportIfLoaded();
    _refreshReports();
    _notify();
  }

  /// Splits one entry into two contiguous halves. The original identity stays
  /// with the first half, so open editors and selections follow it.
  Future<SplitHalves> splitEntry(String id, int atMinutes) async {
    final halves = await _entryApi().splitEntry(id, atMinutes);
    if (projectEntries.any((entry) => entry.id == id)) {
      _refreshProjectIfOpen(projectEntriesProjectId!);
    }
    entries = _replaceWithHalves(entries, id, halves);
    logEntries = _replaceWithHalves(logEntries, id, halves);
    _refreshSupportIfLoaded();
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

  // --- Notes -------------------------------------------------------------

  Future<Note> addNote({
    required String text,
    String? initiativeId,
    DateTime? date,
  }) async {
    final draft = NoteDraft(
      date: isoDate(date ?? today),
      initiativeId: initiativeId,
      text: text,
    );
    final api = noteApi;
    if (api == null) {
      throw const ServicePendingException(
        'NoteService',
        'Saving a note needs the service contract.',
      );
    }
    final note = await api.createNote(draft);
    _upsertNote(note);
    return note;
  }

  /// Saves the end-of-day note for today. A day note is attached to the date
  /// only; it shares its model with project notes.
  Future<Note> saveDayNote(String text) async {
    final existing = todayNote;
    if (existing == null) {
      return addNote(text: text);
    }
    return updateNote(existing.copyWith(text: text));
  }

  Future<Note> updateNote(Note note) async {
    final api = noteApi;
    if (api == null) {
      throw const ServicePendingException(
        'NoteService',
        'Saving a note needs the service contract.',
      );
    }
    final updated = await api.updateNote(note);
    _upsertNote(updated);
    return updated;
  }

  Future<void> deleteNote(String id) async {
    final api = noteApi;
    if (api == null) {
      throw const ServicePendingException(
        'NoteService',
        'Deleting a note needs the service contract.',
      );
    }
    await api.deleteNote(id);
    notes = notes.where((note) => note.id != id).toList();
    projectNotes = projectNotes.where((note) => note.id != id).toList();
    _notify();
  }

  /// Replaces a note in both listings, or adds it at the top. Every listing is
  /// kept newest first so the UI never has to sort. [notes] is today's
  /// day-note listing, so a project note joins it only when it already belongs
  /// there.
  void _upsertNote(Note note) {
    final dayNoteForToday = note.initiativeId == null && note.date == todayIso;
    final tracked =
        dayNoteForToday || notes.any((existing) => existing.id == note.id);
    if (tracked) {
      notes = _newestFirstNotes(_replaceNote(notes, note));
    }
    if (projectNotesProjectId != null &&
        note.initiativeId == projectNotesProjectId) {
      projectNotes = _newestFirstNotes(_replaceNote(projectNotes, note));
    }
    _notify();
  }

  static List<Note> _replaceNote(List<Note> source, Note note) {
    final found = source.any((existing) => existing.id == note.id);
    if (!found) return [note, ...source];
    return [
      for (final existing in source)
        if (existing.id == note.id) note else existing,
    ];
  }

  static List<Note> _newestFirstNotes(Iterable<Note> source) =>
      [...source]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // --- Milestones --------------------------------------------------------

  MilestoneApi _milestoneApi() {
    final api = milestoneApi;
    if (api == null) {
      throw const ServicePendingException(
        'MilestoneService',
        'Project milestones need the service contract.',
      );
    }
    return api;
  }

  /// A project's milestones. The service orders them by due date with undated
  /// milestones last; the id guard keeps another project's list off screen.
  List<Milestone> milestonesForProject(String projectId) {
    if (projectMilestonesProjectId != projectId) return const [];
    return List<Milestone>.unmodifiable(projectMilestones);
  }

  Future<Milestone> addMilestone({
    required String projectId,
    required String title,
    String dueDate = '',
    bool done = false,
  }) async {
    final milestone = await _milestoneApi().createMilestone(
      MilestoneDraft(
        subcategoryId: projectId,
        title: title,
        dueDate: dueDate,
        done: done,
      ),
    );
    if (projectMilestonesProjectId == projectId) {
      projectMilestones = _sortedMilestones([...projectMilestones, milestone]);
    }
    _refreshReports();
    _notify();
    return milestone;
  }

  Future<Milestone> updateMilestone(Milestone milestone) async {
    final updated = await _milestoneApi().updateMilestone(milestone);
    if (projectMilestonesProjectId == updated.subcategoryId) {
      projectMilestones = _sortedMilestones([
        for (final existing in projectMilestones)
          if (existing.id == updated.id) updated else existing,
      ]);
    }
    _refreshReports();
    _notify();
    return updated;
  }

  /// Marks a milestone done or not done. It is the same update path, so the
  /// service stays the single writer.
  Future<Milestone> setMilestoneDone(Milestone milestone, bool done) =>
      updateMilestone(milestone.copyWith(done: done));

  Future<void> deleteMilestone(String id) async {
    await _milestoneApi().deleteMilestone(id);
    projectMilestones = projectMilestones
        .where((milestone) => milestone.id != id)
        .toList();
    _refreshReports();
    _notify();
  }

  static List<Milestone> _sortedMilestones(Iterable<Milestone> source) {
    return [...source]..sort((first, second) {
      final firstUndated = first.dueDate.isEmpty;
      final secondUndated = second.dueDate.isEmpty;
      if (firstUndated != secondUndated) return firstUndated ? 1 : -1;
      if (first.dueDate != second.dueDate) {
        return first.dueDate.compareTo(second.dueDate);
      }
      final created = first.createdAt.compareTo(second.createdAt);
      if (created != 0) return created;
      return first.id.compareTo(second.id);
    });
  }

  // --- Check-ins ---------------------------------------------------------

  bool get hasCheckInService => checkInApi != null;

  /// The server-computed period a new check-in starts with.
  Future<CheckInDefaults> getCheckInDefaults({
    CheckInKind kind = CheckInKind.manager,
  }) async {
    final api = checkInApi;
    if (api == null) {
      throw const ServicePendingException(
        'CheckInService',
        'Creating a check-in needs the service contract.',
      );
    }
    return api.getCheckInDefaults(kind: kind);
  }

  Future<CheckIn> createCheckIn(CheckInDraft draft) async {
    final api = checkInApi;
    if (api == null) {
      throw const ServicePendingException(
        'CheckInService',
        'Creating a check-in needs the service contract.',
      );
    }
    final checkIn = await api.createCheckIn(draft);
    _upsertCheckIn(checkIn);
    _checkInsLoaded = true;
    _notify();
    return checkIn;
  }

  /// Replaces the mutable fields. [source] tells the service whether the
  /// summary text is the user's own or generated; a generated summary needs
  /// [overwriteManualEdits] to replace a summary edited by hand.
  Future<CheckIn> updateCheckIn(
    CheckIn checkIn, {
    CheckInSummarySource source = CheckInSummarySource.manual,
    bool overwriteManualEdits = false,
  }) async {
    final api = checkInApi;
    if (api == null) {
      throw const ServicePendingException(
        'CheckInService',
        'Saving a check-in needs the service contract.',
      );
    }
    final updated = await api.updateCheckIn(
      checkIn,
      source: source,
      overwriteManualEdits: overwriteManualEdits,
    );
    if (checkInDetail?.id == updated.id) checkInDetail = updated;
    _upsertCheckIn(updated);
    _notify();
    return updated;
  }

  /// Changes the audience preset without touching the summary or the stored
  /// totals. The audience only selects the prompt variant.
  Future<CheckIn> setCheckInAudience(
    CheckIn checkIn,
    CheckInAudience audience,
  ) {
    return updateCheckIn(checkIn.copyWith(audience: audience));
  }

  Future<CheckIn> saveSummary(CheckIn checkIn, String markdown) {
    return updateCheckIn(
      checkIn.copyWith(
        summaryMarkdown: markdown,
        state: checkIn.state == CheckInState.final_
            ? CheckInState.final_
            : CheckInState.edited,
      ),
      source: CheckInSummarySource.manual,
    );
  }

  /// Whether the connected service can generate a summary. The check-in
  /// service alone is not enough: generation belongs to the summary contract.
  bool get canGenerateSummary => summaryApi != null;

  /// Streams a generated summary. Text deltas drive the editor; the final
  /// delta carries the persisted check-in with its model and prompt version.
  /// A failure ends the stream and leaves the stored summary untouched.
  Stream<SummaryDelta> generateSummaryStream(
    CheckIn checkIn, {
    bool overwriteManualEdits = false,
  }) {
    final api = summaryApi;
    if (api == null) {
      return Stream<SummaryDelta>.error(
        const ServicePendingException(
          'SummaryService',
          'AI summaries need the summary service contract.',
        ),
      );
    }
    return api
        .generateSummary(checkIn.id, overwriteManualEdits: overwriteManualEdits)
        .map((delta) {
          final updated = delta.checkIn;
          if (updated != null) _applyGeneratedCheckIn(updated);
          return delta;
        });
  }

  Future<CheckIn> generateSummary(CheckIn checkIn) async {
    CheckIn? generated;
    await for (final delta in generateSummaryStream(
      checkIn,
      overwriteManualEdits: true,
    )) {
      generated = delta.checkIn ?? generated;
    }
    if (generated == null) {
      throw StateError('The summary generation returned no check-in.');
    }
    return generated;
  }

  void _applyGeneratedCheckIn(CheckIn updated) {
    if (checkInDetail?.id == updated.id) checkInDetail = updated;
    _upsertCheckIn(updated);
    _notify();
  }

  /// The versioned instruction for one variant, previewed in Settings → AI.
  Future<PromptTemplate> promptTemplate(CheckInPromptVariant variant) async {
    final api = summaryApi;
    if (api == null) {
      throw const ServicePendingException(
        'SummaryService',
        'The prompt template is owned by the service.',
      );
    }
    return api.getPromptTemplate(variant);
  }

  Future<CheckIn> finalizeCheckIn(CheckIn checkIn) async {
    final api = checkInApi;
    if (api == null) {
      throw const ServicePendingException(
        'CheckInService',
        'Finalizing a check-in needs the service contract.',
      );
    }
    final updated = await api.finalizeCheckIn(checkIn.id);
    if (checkInDetail?.id == updated.id) checkInDetail = updated;
    _upsertCheckIn(updated);
    _notify();
    return updated;
  }

  /// Removes a saved personal review. The manager boundary is derived only
  /// from final manager check-ins, so a deletion never moves it.
  Future<void> deleteCheckIn(String id) async {
    final api = checkInApi;
    if (api == null) {
      throw const ServicePendingException(
        'CheckInService',
        'Deleting a check-in needs the service contract.',
      );
    }
    await api.deleteCheckIn(id);
    checkIns = [
      for (final checkIn in checkIns)
        if (checkIn.id != id) checkIn,
    ];
    if (checkInDetailId == id) {
      checkInDetail = null;
      checkInDetailId = null;
      checkInReport = null;
      checkInDetailError = null;
    }
    _notify();
  }

  /// Replaces a check-in in the listing, or inserts it newest first. The
  /// service owns ordering; this keeps the in-memory list consistent after a
  /// mutation without a refetch.
  void _upsertCheckIn(CheckIn checkIn) {
    final found = checkIns.any((existing) => existing.id == checkIn.id);
    final next = found
        ? [
            for (final existing in checkIns)
              if (existing.id == checkIn.id) checkIn else existing,
          ]
        : [checkIn, ...checkIns];
    checkIns = next..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// The variant prompt block for one check-in. The service owns the text.
  Future<CheckInPrompt> buildCheckInPrompt(CheckIn checkIn) async {
    final api = checkInApi;
    if (api == null) {
      throw const ServicePendingException(
        'CheckInService',
        'The check-in prompt needs the service contract.',
      );
    }
    return api.buildPrompt(checkIn.id);
  }

  /// The service-backed export and prompt capability.
  bool get hasSummaryService => summaryApi != null;
  bool get canExport => hasSummaryService;

  /// The prompt block for the same scope as [buildExport]. The service owns
  /// the instruction text and appends summary.md.
  Future<String> buildPrompt(
    DateTime start,
    DateTime end, {
    String checkInId = '',
    CheckInKind kind = CheckInKind.manager,
    CheckInAudience? audience,
  }) async {
    final api = summaryApi;
    if (api == null) {
      throw const ServicePendingException(
        'SummaryService',
        'The export prompt needs the summary service contract.',
      );
    }
    final prompt = await api.buildPrompt(
      fromDate: isoDate(start),
      toDate: isoDate(end),
      checkInId: checkInId,
      variant: checkInId.isEmpty ? _promptVariantFor(kind, audience) : null,
    );
    return prompt.prompt;
  }

  Future<ExportBundle> buildExport(
    DateTime start,
    DateTime end, {
    String checkInId = '',
  }) {
    final api = summaryApi;
    if (api == null) {
      throw const ServicePendingException(
        'SummaryService',
        'Export needs the summary service contract.',
      );
    }
    return api.buildExport(
      fromDate: isoDate(start),
      toDate: isoDate(end),
      checkInId: checkInId,
    );
  }

  CheckInPromptVariant? _promptVariantFor(
    CheckInKind kind,
    CheckInAudience? audience,
  ) {
    if (kind == CheckInKind.personal) {
      return CheckInPromptVariant.personalReview;
    }
    if (audience == CheckInAudience.performanceReview) {
      return CheckInPromptVariant.managerPerformanceReview;
    }
    return CheckInPromptVariant.managerOneOnOne;
  }

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
      final api = settingsApi;
      if (api == null) {
        throw const ServicePendingException(
          'SettingsService',
          'Saving preferences needs the service contract.',
        );
      }
      final saved = await api.updateSettings(updated);
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

  /// The account's roster of common support-person names. A person is a name,
  /// not an entity: editing this roster never rewrites historical entries.
  List<String> get supportPeople => settings.supportPeople;

  /// Adds a name to the roster, case-insensitively and only once. The local
  /// roster updates immediately; persistence is best-effort so capturing work
  /// never blocks on a settings write.
  Future<void> addSupportPerson(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _rosterContains(trimmed)) return;
    _pendingRoster[trimmed.toLowerCase()] = trimmed;
    await _saveSupportPeople([...settings.supportPeople, trimmed]);
  }

  /// Removes every case-insensitive match from the roster. Work entries keep
  /// their `person` string; removing a person changes only this roster.
  Future<void> removeSupportPerson(String name) async {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return;
    final remaining = [
      for (final person in settings.supportPeople)
        if (person.toLowerCase() != key) person,
    ];
    if (remaining.length == settings.supportPeople.length) return;
    _pendingRoster[key] = null;
    await _saveSupportPeople(remaining);
  }

  bool _rosterContains(String name) {
    final key = name.toLowerCase();
    return settings.supportPeople.any((person) => person.toLowerCase() == key);
  }

  Future<void> _saveSupportPeople(List<String> people) async {
    settings = settings.copyWith(
      supportPeople: List<String>.unmodifiable(people),
    );
    _notify();
    await _persistSupportPeople();
  }

  /// Writes the current settings when the real preferences are available.
  /// Queued roster edits survive a failed write and are replayed by the next
  /// successful load or write.
  Future<void> _persistSupportPeople() async {
    final api = settingsApi;
    // A write before the real preferences arrive would send defaults over
    // every stored preference, including the roster we are editing.
    if (api == null || preferencesLoading || preferencesError != null) return;

    final submitted = Map<String, String?>.of(_pendingRoster);
    try {
      final saved = await api.updateSettings(settings);
      settings = saved.copyWith(
        version: about?.version,
        schemaVersion: about?.schemaVersion,
        license: about?.license,
      );
      // Replayed edits are now stored. An edit made while the write was in
      // flight keeps its own entry and retries later.
      for (final entry in submitted.entries) {
        if (_pendingRoster[entry.key] == entry.value) {
          _pendingRoster.remove(entry.key);
        }
      }
      _notify();
    } catch (_) {
      // Keep the optimistic roster and pending edits. A failed settings write
      // must not surface as a capture error or poison the preferences screen.
    }
  }

  /// Loads the snapshot list and status. Non-admins never call the backup
  /// RPCs; the panel shows an explanatory read-only state instead.
  Future<void> loadBackups({bool force = false}) async {
    if (!canManageBackups) {
      backups = const [];
      backupStatus = null;
      backupsError = null;
      return;
    }
    if (_backupsLoaded && !force) return;

    final api = settingsApi;
    if (api == null) {
      backupsError = 'Backups need the settings service contract.';
      _notify();
      return;
    }

    backupsLoading = true;
    backupsError = null;
    _notify();
    try {
      final results = await Future.wait<dynamic>([
        api.getBackupStatus(),
        api.listBackups(),
      ]);
      backupStatus = results[0] as BackupStatusInfo;
      backups = List<BackupSnapshot>.from(results[1] as List<BackupSnapshot>);
      _backupsLoaded = true;
    } catch (error) {
      backupsError = error.toString();
    } finally {
      backupsLoading = false;
      _notify();
    }
  }

  /// Takes a manual snapshot. Manual snapshots are never removed by retention.
  Future<BackupStatusInfo> backupNow() async {
    final api = settingsApi;
    if (api == null) {
      throw const ServicePendingException(
        'SettingsService',
        'Taking a backup needs the service contract.',
      );
    }

    final result = await api.backupNow();
    backupStatus = result.status;
    backups = [
      result.backup,
      ...backups.where((snapshot) => snapshot.name != result.backup.name),
    ];
    settings = settings.copyWith(
      lastBackupAt: result.status.lastBackupAt ?? result.backup.createdAt,
      lastBackupBytes: result.status.lastBackupSizeBytes,
    );
    _backupsLoaded = true;
    _notify();
    return result.status;
  }

  /// Restores one snapshot. The service verifies it, preserves the current
  /// database and rebuilds indexes; the client refreshes every server-owned
  /// view afterwards because the data on screen may have rolled back.
  Future<RestoreBackupResult> restoreBackup(String name) async {
    final api = settingsApi;
    if (api == null) {
      throw const ServicePendingException(
        'SettingsService',
        'Restoring a backup needs the service contract.',
      );
    }

    final result = await api.restoreBackup(name);
    backupStatus = result.status;
    settings = settings.copyWith(
      lastBackupAt: result.status.lastBackupAt ?? result.backup.createdAt,
      lastBackupBytes: result.status.lastBackupSizeBytes,
    );
    _backupsLoaded = false;
    await reload();
    await loadBackups(force: true);
    return result;
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
