import 'dart:async';

import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/taxonomy.dart';
import '../models/work_entry.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../utils/entry_grouping.dart';
import '../utils/people.dart';
import '../utils/time_utils.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/forms/date_range_dialog.dart';
import '../widgets/forms/entry_form.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';

enum _LogPreset {
  today('Today'),
  week('This week'),
  last7('Last 7 days'),
  month('This month'),
  sinceManagerCheckIn('Since last manager check-in'),
  custom('Custom range');

  const _LogPreset(this.label);
  final String label;
}

/// The period a preset covers. The last manager check-in starts the day after
/// its period end, because the check-in already accounted for that day; before
/// any check-in the journal start date is the floor.
DateTimeRange _logRange(
  _LogPreset preset,
  AppState state,
  DateTimeRange? custom,
) {
  final today = state.today;
  return switch (preset) {
    _LogPreset.today => DateTimeRange(start: today, end: today),
    _LogPreset.week => DateTimeRange(
      start: startOfWeek(today, weekStart: state.settings.weekStart),
      end: today,
    ),
    _LogPreset.last7 => DateTimeRange(start: addDays(today, -6), end: today),
    _LogPreset.month => DateTimeRange(
      start: DateTime(today.year, today.month),
      end: today,
    ),
    _LogPreset.sinceManagerCheckIn => DateTimeRange(
      start: _sinceCheckInStart(state, today),
      end: today,
    ),
    _LogPreset.custom =>
      custom ?? DateTimeRange(start: addDays(today, -6), end: today),
  };
}

DateTime _journalStart(AppState state) {
  final parsed = DateTime.tryParse(state.settings.journalStartDate);
  return parsed == null ? startOfQuarter(state.today) : dateOnly(parsed);
}

/// CheckIn does not carry a kind or final flag until the manager check-in
/// ticket lands, so the latest saved check-in is the best boundary available.
DateTime _sinceCheckInStart(AppState state, DateTime today) {
  final checkIn = state.latestCheckIn;
  final start = checkIn == null
      ? _journalStart(state)
      : addDays(dateOnly(checkIn.periodEnd), 1);
  return start.isAfter(today) ? today : start;
}

/// The Log answers "what happened?". Every read and write goes through the
/// generated EntryService.
class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ServiceLogView();
  }
}

// --- Service-backed log ----------------------------------------------------

class _ServiceLogView extends StatefulWidget {
  const _ServiceLogView();

  @override
  State<_ServiceLogView> createState() => _ServiceLogViewState();
}

class _ServiceLogViewState extends State<_ServiceLogView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  AppState? _state;
  bool _initialized = false;
  _LogPreset _preset = _LogPreset.week;
  DateTimeRange? _customRange;
  String _categoryId = '';
  String _subcategoryId = '';
  Timer? _searchDebounce;
  WorkEntry? _editing;
  bool _adding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.of(context);
    if (!identical(state, _state)) {
      _state?.searchFocusRequest.removeListener(_focusSearch);
      _state = state;
      state.searchFocusRequest.addListener(_focusSearch);
    }
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
  }

  @override
  void dispose() {
    _state?.searchFocusRequest.removeListener(_focusSearch);
    _searchDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  DateTimeRange _range(AppState state) =>
      _logRange(_preset, state, _customRange);

  LogQuery _query(AppState state) {
    final range = _range(state);
    return LogQuery(
      fromDate: isoDate(range.start),
      toDate: isoDate(range.end),
      categoryId: _categoryId,
      subcategoryId: _subcategoryId,
      query: _search.text.trim(),
    );
  }

  void _load() {
    final state = _state;
    if (state == null || !state.hasEntryService) return;
    unawaited(state.loadLog(_query(state)));
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _load);
    setState(() {});
  }

  Future<void> _pickCustomRange(AppState state) async {
    final initial =
        _customRange ??
        DateTimeRange(start: addDays(state.today, -6), end: state.today);
    final picked = await showDateRangeDialog(
      context,
      initialRange: initial,
      today: state.today,
      presets: dateRangePresets<_LogPreset>(
        periods: _LogPreset.values,
        custom: _LogPreset.custom,
        labelOf: (preset) => preset.label,
        rangeOf: (preset) => _logRange(preset, state, null),
      ),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _preset = _LogPreset.custom;
      });
      _load();
    }
  }

  void _clearFilters(AppState state) {
    setState(() {
      _categoryId = '';
      _subcategoryId = '';
      _search.clear();
      _editing = null;
    });
    _load();
  }

  Future<void> _delete(WorkEntry entry) async {
    final state = AppStateScope.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          '“${entry.description.isEmpty ? 'Untitled entry' : entry.description}” '
          'will be removed from the journal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await state.deleteWorkEntry(entry.id);
      await state.refreshLog();
      if (!mounted) return;
      setState(() => _editing = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the entry: $error')),
      );
    }
  }

  Future<void> _split(WorkEntry entry) async {
    final state = AppStateScope.read(context);
    if (entry.minutes < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An entry needs at least two minutes to split.'),
        ),
      );
      return;
    }
    final atMinutes = await showDialog<int>(
      context: context,
      builder: (context) => _SplitDialog(entry: entry),
    );
    if (atMinutes == null || !mounted) return;

    try {
      await state.splitEntry(entry.id, atMinutes);
      await state.refreshLog();
      if (!mounted) return;
      setState(() => _editing = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Entry split into ${formatDuration(atMinutes)} and '
            '${formatDuration(entry.minutes - atMinutes)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not split the entry: $error')),
      );
    }
  }

  Future<void> _saved() async {
    if (!mounted) return;
    setState(() => _editing = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Entry updated')));
  }

  Future<void> _added() async {
    if (!mounted) return;
    setState(() => _adding = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Entry saved')));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final range = _range(state);
    final editing = _editing;
    final visibleEntries = [...state.logEntries];
    // A reload must never make an open editor disappear. If the new result no
    // longer includes the edited row, keep showing it until the user saves or
    // cancels, so the draft is not silently discarded.
    if (editing != null &&
        !visibleEntries.any((entry) => entry.id == editing.id)) {
      visibleEntries.add(editing);
    }
    final grouped = groupEntriesByLocalDay(visibleEntries);
    for (final day in grouped.values) {
      day.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    }
    final days = grouped.keys.toList();
    final total = grouped.values
        .expand((day) => day)
        .fold<int>(0, (sum, entry) => sum + entry.minutes);
    final filtersActive =
        _categoryId.isNotEmpty ||
        _subcategoryId.isNotEmpty ||
        _search.text.trim().isNotEmpty;
    // Reviewing a filtered view is when the next entry most often belongs to
    // the same slice, so the inline form starts from the active taxonomy.
    final entrySeed = _taxonomySeed(state);
    // Keep the rows mounted while a draft is open; the loading panel would
    // destroy the inline editor's state.
    final showLoading = state.logLoading && editing == null;
    final showError = state.logError != null && editing == null;

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              children: [
                Text('Log', style: theme.textTheme.headlineSmall),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => setState(() => _adding = true),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add entry'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 900;
                  final fields = <Widget>[
                    AppDropdown<_LogPreset>(
                      value: _preset,
                      label: 'Period',
                      icon: Icons.date_range_outlined,
                      height: AppSizes.controlHeight,
                      items: [
                        for (final preset in _LogPreset.values)
                          DropdownMenuItem(
                            value: preset,
                            child: Text(preset.label),
                          ),
                      ],
                      onChanged: (preset) {
                        if (preset == null) return;
                        if (preset == _LogPreset.custom) {
                          unawaited(_pickCustomRange(state));
                        } else {
                          setState(() => _preset = preset);
                          _load();
                        }
                      },
                    ),
                    AppDropdown<String>(
                      value: _categoryId,
                      label: 'Category',
                      icon: Icons.category_outlined,
                      height: AppSizes.controlHeight,
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All categories'),
                        ),
                        for (final category in state.categories)
                          DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _categoryId = value;
                          if (_subcategoryId.isNotEmpty &&
                              state
                                      .subcategoryById(_subcategoryId)
                                      ?.categoryId !=
                                  value) {
                            _subcategoryId = '';
                          }
                        });
                        _load();
                      },
                    ),
                    AppDropdown<String>(
                      value: _subcategoryId,
                      label: 'Subcategory',
                      icon: Icons.subdirectory_arrow_right,
                      height: AppSizes.controlHeight,
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All subcategories'),
                        ),
                        for (final subcategory in _subcategoryOptions(state))
                          DropdownMenuItem(
                            value: subcategory.id,
                            child: Text(_subcategoryLabel(state, subcategory)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _subcategoryId = value);
                        _load();
                      },
                    ),
                    // The row shares one control height, so the search box is
                    // pinned to it rather than growing with its icon targets.
                    SizedBox(
                      height: AppSizes.controlHeight,
                      child: TextField(
                        controller: _search,
                        focusNode: _searchFocus,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search entries…  /',
                          visualDensity: VisualDensity.standard,
                          prefixIcon: const Icon(Icons.search, size: 17),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _search.clear();
                                    _load();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close, size: 15),
                                ),
                        ),
                      ),
                    ),
                  ];
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, field) in fields.indexed) ...[
                          if (index > 0) const SizedBox(height: AppSpacing.sm),
                          field,
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 200, child: fields[0]),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(width: 170, child: fields[1]),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(width: 190, child: fields[2]),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: fields[3]),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (_preset == _LogPreset.custom) ...[
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_pickCustomRange(state)),
                    icon: const Icon(Icons.date_range_outlined, size: 15),
                    label: Text(
                      '${formatShortDate(range.start)} – '
                      '${formatShortDate(range.end)}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Text(
                  formatRange(range.start, range.end),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
                const Spacer(),
                if (state.logOverlappingIds.isNotEmpty) ...[
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${state.logOverlappingIds.length} overlapping',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Text(
                  '${formatDuration(total)} · ${days.length} '
                  '${days.length == 1 ? 'day' : 'days'} shown',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_adding)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New entry', style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                      EntryForm(
                        entry: null,
                        initialStart: DateTime.now(),
                        initialCategoryId: entrySeed.categoryId,
                        initialSubcategoryId: entrySeed.subcategoryId,
                        onCancel: () => setState(() => _adding = false),
                        onSaved: (_) => _added(),
                      ),
                    ],
                  ),
                ),
              ),
            if (showLoading)
              const Panel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text('Loading entries…'),
                      ],
                    ),
                  ),
                ),
              )
            else if (showError)
              Panel(
                tone: PanelTone.warning,
                child: Column(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 28,
                      color: scheme.error,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Could not load the log',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      state.logError!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(state.refreshLog()),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (days.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.search_off,
                  title: filtersActive
                      ? 'No entries match these filters'
                      : 'Nothing logged in this period',
                  message: filtersActive
                      ? 'Try a wider period or clear the filters.'
                      : 'Capture work on Today or widen the date range.',
                  action: filtersActive
                      ? TextButton.icon(
                          onPressed: () => _clearFilters(state),
                          icon: const Icon(Icons.filter_alt_off, size: 16),
                          label: const Text('Clear filters'),
                        )
                      : FilledButton.icon(
                          onPressed: () => setState(() => _adding = true),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add entry'),
                        ),
                ),
              )
            else
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final day in days) ...[
                      _DayGroupHeader(
                        day: DateTime.parse(day),
                        minutes: grouped[day]!.fold(
                          0,
                          (sum, entry) => sum + entry.minutes,
                        ),
                      ),
                      for (final entry in grouped[day]!)
                        _ServiceEntryRow(
                          key: ValueKey(entry.id),
                          entry: entry,
                          category: state.categoryById(entry.categoryId),
                          subcategory: state.subcategoryById(
                            entry.subcategoryId,
                          ),
                          overlapping: state.logOverlappingIds.contains(
                            entry.id,
                          ),
                          editing: _editing?.id == entry.id,
                          onEdit: () => setState(() => _editing = entry),
                          onCancelEdit: () => setState(() => _editing = null),
                          onSaved: _saved,
                          onSplit: () => unawaited(_split(entry)),
                          onDelete: () => unawaited(_delete(entry)),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The active taxonomy filters as a form seed. A subcategory filter also
  /// names its parent, so the pair stays consistent. The form itself rejects
  /// values it cannot offer, such as an archived category.
  ({String? categoryId, String? subcategoryId}) _taxonomySeed(AppState state) {
    final subcategory = state.subcategoryById(_subcategoryId);
    if (subcategory != null) {
      return (
        categoryId: subcategory.categoryId,
        subcategoryId: subcategory.id,
      );
    }
    return (
      categoryId: _categoryId.isEmpty ? null : _categoryId,
      subcategoryId: null,
    );
  }

  List<Subcategory> _subcategoryOptions(AppState state) {
    if (_categoryId.isEmpty) return state.subcategories;
    return state.subcategoriesFor(_categoryId);
  }

  String _subcategoryLabel(AppState state, Subcategory subcategory) {
    if (_categoryId.isNotEmpty) return subcategory.name;
    final category = state.categoryById(subcategory.categoryId);
    return category == null
        ? subcategory.name
        : '${subcategory.name} · ${category.name}';
  }
}

class _ServiceEntryRow extends StatefulWidget {
  const _ServiceEntryRow({
    super.key,
    required this.entry,
    required this.category,
    required this.subcategory,
    required this.overlapping,
    required this.editing,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onSaved,
    required this.onSplit,
    required this.onDelete,
  });

  final WorkEntry entry;
  final Category? category;
  final Subcategory? subcategory;
  final bool overlapping;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onSaved;
  final VoidCallback onSplit;
  final VoidCallback onDelete;

  @override
  State<_ServiceEntryRow> createState() => _ServiceEntryRowState();
}

class _ServiceEntryRowState extends State<_ServiceEntryRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final category = widget.category;
    final subcategory = widget.subcategory;
    final overlapping = widget.overlapping;
    final editing = widget.editing;
    final onEdit = widget.onEdit;
    final onSplit = widget.onSplit;
    final onDelete = widget.onDelete;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final support = category?.role == CategoryRole.support;
    final accent = support ? scheme.tertiary : scheme.primary;
    final attribution = [
      category?.name ?? 'Unknown category',
      if (subcategory != null) subcategory.name,
      if (entry.people.isNotEmpty) peopleLabel(entry.people),
    ].join(' · ');
    final verticalPadding = AppTheme.isCompact(context) ? 6.0 : 10.0;

    return Container(
      decoration: BoxDecoration(
        color: overlapping
            ? scheme.errorContainer.withValues(alpha: 0.08)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: editing
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: verticalPadding),
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 98,
                    child: Text(
                      formatTimeRange(entry.startedLocal, entry.endedLocal),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  Icon(
                    support
                        ? Icons.volunteer_activism_outlined
                        : category?.role == CategoryRole.initiative
                        ? Icons.flag_outlined
                        : Icons.category_outlined,
                    size: 14,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                attribution,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (overlapping) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Overlaps another entry',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: scheme.error),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.pill,
                                    ),
                                  ),
                                  child: Text(
                                    'Overlap',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (entry.description.isNotEmpty)
                          Text(
                            entry.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        if (entry.outcome.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                size: 12,
                                color: scheme.tertiary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  entry.outcome,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 52,
                    child: Text(
                      formatDuration(entry.minutes),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: AppSizes.rowComfortable,
                    height: AppSizes.rowComfortable,
                    child: PopupMenuButton<String>(
                      tooltip: 'Row actions',
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      onSelected: (value) => switch (value) {
                        'edit' => onEdit(),
                        'split' => onSplit(),
                        'delete' => onDelete(),
                        _ => null,
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'split',
                          enabled: entry.minutes > 1,
                          child: const Text('Split'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (editing)
            EntryForm(
              entry: entry,
              onCancel: widget.onCancelEdit,
              onSaved: (_) => widget.onSaved(),
            ),
          if (!editing && _expanded) _buildDetails(context),
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = widget.entry;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerLow.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(112, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.outcome.isNotEmpty) ...[
            Text(
              'OUTCOME',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.tertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Text(entry.outcome, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
          ],
          if (entry.links.isNotEmpty) ...[
            Text(
              'LINKS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final link in entry.links)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link, size: 13, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        link.label.isEmpty ? link.url : link.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (entry.tags.isNotEmpty) ...[
            Text(
              'TAGS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in entry.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(tag, style: theme.textTheme.labelSmall),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            '${entry.source == EntrySource.timer ? 'Timer · ' : 'Manual · '}'
            '${entry.localDate}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitDialog extends StatefulWidget {
  const _SplitDialog({required this.entry});

  final WorkEntry entry;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minutes = TextEditingController(
    text: (widget.entry.minutes ~/ 2)
        .clamp(1, widget.entry.minutes - 1)
        .toString(),
  );

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(int.parse(_minutes.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final at = int.tryParse(_minutes.text);
    final second = at == null ? null : entry.minutes - at;
    return AlertDialog(
      title: const Text('Split entry'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatTime(entry.startedLocal)}–'
              '${formatTime(entry.endedLocal)} · '
              '${formatDuration(entry.minutes)}',
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _minutes,
              autofocus: true,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Minutes in the first half',
              ),
              validator: (value) {
                final minutes = int.tryParse(value?.trim() ?? '');
                if (minutes == null ||
                    minutes < 1 ||
                    minutes >= entry.minutes) {
                  return 'Leave at least one minute on each side.';
                }
                return null;
              },
            ),
            if (at != null && second != null && second > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'First ${formatDuration(at)}, second ${formatDuration(second)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Split')),
      ],
    );
  }
}

class _DayGroupHeader extends StatelessWidget {
  const _DayGroupHeader({required this.day, required this.minutes});

  final DateTime day;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 7,
      ),
      child: Row(
        children: [
          Text(
            formatDayHeader(day),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            formatDuration(minutes),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
