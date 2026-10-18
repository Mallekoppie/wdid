import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/app_settings.dart';
import '../models/enums.dart';
import '../models/work_item.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/analytics.dart';
import '../utils/time_utils.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/entry_row.dart';
import '../widgets/forms/entry_dialog.dart';
import '../widgets/forms/export_dialog.dart';
import '../widgets/forms/support_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';

enum _LogPreset {
  today('Today'),
  week('This week'),
  sinceCheckIn('Since last check-in'),
  quarter('This quarter'),
  custom('Custom range');

  const _LogPreset(this.label);
  final String label;
}

enum _TypeFilter {
  all('All types'),
  initiative('Initiative work'),
  support('Support'),
  other('Other');

  const _TypeFilter(this.label);
  final String label;
}

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  AppState? _state;
  _LogPreset _preset = _LogPreset.week;
  String _initiative = 'all';
  _TypeFilter _type = _TypeFilter.all;
  DateTimeRange? _customRange;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.of(context);
    if (!identical(state, _state)) {
      _state?.searchFocusRequest.removeListener(_focusSearch);
      _state = state;
      state.searchFocusRequest.addListener(_focusSearch);
    }
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection =
        TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  @override
  void dispose() {
    _state?.searchFocusRequest.removeListener(_focusSearch);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  DateTimeRange _range(AppState state) {
    final today = state.today;
    return switch (_preset) {
      _LogPreset.today => DateTimeRange(start: today, end: today),
      _LogPreset.week => DateTimeRange(
          start: startOfWeek(today, weekStart: state.settings.weekStart),
          end: today,
        ),
      _LogPreset.sinceCheckIn => DateTimeRange(
          start: state.latestCheckIn?.periodEnd ?? startOfQuarter(today),
          end: today,
        ),
      _LogPreset.quarter =>
        DateTimeRange(start: startOfQuarter(today), end: today),
      _LogPreset.custom => _customRange ??
          DateTimeRange(
            start: today.subtract(const Duration(days: 6)),
            end: today,
          ),
    };
  }

  List<WorkItem> _filtered(AppState state) {
    final range = _range(state);
    final query = _search.text.trim().toLowerCase();
    return entriesInRange(state.workItems, range.start, range.end).where((item) {
      if (_initiative != 'all' && item.initiativeId != _initiative) return false;
      final matchesType = switch (_type) {
        _TypeFilter.all => true,
        _TypeFilter.initiative => item.type == WorkType.initiative,
        _TypeFilter.support => item.isSupport,
        _TypeFilter.other =>
          item.type == WorkType.category && !item.isSupport,
      };
      if (!matchesType) return false;
      if (query.isEmpty) return true;
      return [
        item.summary,
        item.outcome,
        item.notes,
        item.categoryLabel ?? '',
        item.category ?? '',
        item.person ?? '',
        item.team ?? '',
        item.tags.join(' '),
      ].any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _pickCustomRange(AppState state) async {
    final initial = _customRange ??
        DateTimeRange(
          start: state.today.subtract(const Duration(days: 6)),
          end: state.today,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: initial,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _preset = _LogPreset.custom;
      });
    }
  }

  Future<void> _edit(WorkItem item) async {
    final state = AppStateScope.read(context);
    final saved = item.isSupport
        ? await showSupportDialog(context, state: state, existing: item)
        : await showEntryDialog(context, state: state, existing: item);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry updated')),
      );
    }
  }

  Future<void> _delete(WorkItem item) async {
    final state = AppStateScope.read(context);
    try {
      await state.deleteEntry(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry deleted')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the entry: $error')),
      );
    }
  }

  Future<void> _addEntry() async {
    final state = AppStateScope.read(context);
    final saved = await showEntryDialog(context, state: state);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry saved')),
      );
    }
  }

  void _clearFilters() {
    setState(() {
      _initiative = 'all';
      _type = _TypeFilter.all;
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final range = _range(state);
    final items = _filtered(state);
    final grouped = groupByDay(items);
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final total = totalMinutes(items);
    final filtersActive = _initiative != 'all' ||
        _type != _TypeFilter.all ||
        _search.text.trim().isNotEmpty;

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              children: [
                Text('Log', style: theme.textTheme.headlineSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => showExportDialog(
                    context,
                    state: state,
                    start: range.start,
                    end: range.end,
                  ),
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export period'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _addEntry,
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
                        }
                      },
                    ),
                    AppDropdown<String>(
                      value: _initiative,
                      label: 'Attribution',
                      icon: Icons.flag_outlined,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All initiatives'),
                        ),
                        for (final initiative in state.initiatives)
                          DropdownMenuItem(
                            value: initiative.id,
                            child: Text(initiative.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _initiative = value);
                      },
                    ),
                    AppDropdown<_TypeFilter>(
                      value: _type,
                      label: 'Type',
                      icon: Icons.filter_alt_outlined,
                      items: [
                        for (final type in _TypeFilter.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _type = value);
                      },
                    ),
                    TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search entries…  /',
                        prefixIcon: const Icon(Icons.search, size: 17),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close, size: 15),
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
                      SizedBox(width: 170, child: fields[0]),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(width: 190, child: fields[1]),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(width: 150, child: fields[2]),
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
                    onPressed: () => _pickCustomRange(state),
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
            if (days.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.search_off,
                  title: filtersActive
                      ? 'No entries match these filters'
                      : 'Nothing logged in this period',
                  message: filtersActive
                      ? 'Try a wider period or clear the filters.'
                      : 'Add an entry or widen the date range.',
                  action: filtersActive
                      ? TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.filter_alt_off, size: 16),
                          label: const Text('Clear filters'),
                        )
                      : FilledButton.icon(
                          onPressed: _addEntry,
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
                        minutes: totalMinutes(grouped[day]!),
                      ),
                      for (final item in grouped[day]!)
                        EntryRow(
                          item: item,
                          initiatives: state.initiatives,
                          compact:
                              state.settings.density == DensityPreference.compact,
                          onEdit: (item) => unawaited(_edit(item)),
                          onDelete: (item) => unawaited(_delete(item)),
                          onOpenInitiative: (item) {
                            if (item.initiativeId != null) {
                              context.go('/initiatives/${item.initiativeId}');
                            }
                          },
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
