import 'dart:async';

import 'package:flutter/material.dart';

import '../models/work_entry.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/analytics.dart';
import '../utils/entry_grouping.dart';
import '../utils/time_utils.dart';
import '../widgets/allocation_bars.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/forms/date_range_dialog.dart';
import '../widgets/forms/support_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/support_entry_row.dart';

enum _SupportPeriod {
  quarter('This quarter'),
  month('This month'),
  all('All time'),
  custom('Custom range');

  const _SupportPeriod(this.label);
  final String label;
}

/// The inclusive local-date range a period covers. Custom ranges fall back to
/// the last seven days until the user picks one.
DateTimeRange _periodRange(
  _SupportPeriod period,
  AppState state,
  DateTimeRange? custom,
) {
  final today = state.today;
  final fallback =
      custom ?? DateTimeRange(start: addDays(today, -6), end: today);
  final start = switch (period) {
    _SupportPeriod.quarter => startOfQuarter(today),
    _SupportPeriod.month => DateTime(today.year, today.month, 1),
    _SupportPeriod.all => DateTime(2000),
    _SupportPeriod.custom => fallback.start,
  };
  final end = period == _SupportPeriod.custom ? fallback.end : today;
  return DateTimeRange(start: start, end: end);
}

/// Support work is work in a support-role category. Entries are read from
/// EntryService and never mixed with initiative work.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ServiceSupportScreen();
  }
}

class _ServiceSupportScreen extends StatefulWidget {
  const _ServiceSupportScreen();

  @override
  State<_ServiceSupportScreen> createState() => _ServiceSupportScreenState();
}

class _ServiceSupportScreenState extends State<_ServiceSupportScreen> {
  _SupportPeriod _period = _SupportPeriod.quarter;
  DateTimeRange? _customRange;
  AppState? _state;
  bool _loaded = false;
  final _newPerson = TextEditingController();

  @override
  void dispose() {
    _newPerson.dispose();
    super.dispose();
  }

  Future<void> _addPerson() async {
    final name = _newPerson.text.trim();
    if (name.isEmpty) return;
    final state = AppStateScope.read(context);
    _newPerson.clear();
    await state.addSupportPerson(name);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.of(context);
    _state = state;
    // Wait for the taxonomy so the first request already knows the
    // support-role categories.
    if (state.status != AppStatus.ready || _loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  void _load() {
    final state = _state;
    if (state == null) return;
    final range = _periodRange(_period, state, _customRange);
    unawaited(
      state.loadSupport(
        fromDate: isoDate(range.start),
        toDate: isoDate(range.end),
      ),
    );
  }

  void _selectPeriod(_SupportPeriod period) {
    setState(() => _period = period);
    _load();
  }

  Future<void> _pickCustomRange(AppState state) async {
    final picked = await showDateRangeDialog(
      context,
      initialRange: _periodRange(_period, state, _customRange),
      today: state.today,
      presets: [
        for (final period in _SupportPeriod.values)
          if (period != _SupportPeriod.custom)
            DateRangePreset(
              label: period.label,
              range: _periodRange(period, state, null),
            ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _period = _SupportPeriod.custom;
    });
    _load();
  }

  Future<void> _logSupport() async {
    final state = AppStateScope.read(context);
    final saved = await showServiceSupportDialog(context, state: state);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Support entry saved')));
    }
  }

  Future<void> _edit(WorkEntry entry) async {
    final state = AppStateScope.read(context);
    final saved = await showServiceSupportDialog(
      context,
      state: state,
      existing: entry,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Support entry updated')));
    }
  }

  Future<void> _delete(WorkEntry entry) async {
    final state = AppStateScope.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete support entry?'),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Support entry deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the entry: $error')),
      );
    }
  }

  Widget _peoplePanel(AppState state, ThemeData theme) {
    final scheme = theme.colorScheme;
    final people = state.supportPeople;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHeader(
            title: 'People',
            subtitle:
                'Names offered wherever you record support. Removing one '
                'leaves past entries untouched.',
            icon: Icons.people_outline,
          ),
          const SizedBox(height: AppSpacing.md),
          if (people.isEmpty)
            Text(
              'No people yet. Add a name here or while logging support.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final person in people)
                  InputChip(
                    label: Text(person),
                    deleteButtonTooltipMessage: 'Remove $person',
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () =>
                        unawaited(state.removeSupportPerson(person)),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newPerson,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_addPerson()),
                  decoration: const InputDecoration(
                    labelText: 'Add a person',
                    hintText: 'Priya',
                    prefixIcon: Icon(Icons.person_add_alt_1_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: () => unawaited(_addPerson()),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add person'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = state.supportEntries;
    // The rollups are the period report's allocations. They are never rebuilt
    // by adding up the loaded entries.
    final report = state.supportReport;
    final personTotals = report?.supportPeople ?? const [];
    final modeTotals = report?.supportModes ?? const [];
    // The header totals are authoritative: adding up the per-person rows would
    // count a two-person entry twice.
    final minutes = report?.supportMinutes ?? 0;
    final interactions = report?.supportInteractions ?? 0;
    final people = personTotals.length;
    final grouped = groupEntriesByLocalDay(entries);
    for (final day in grouped.values) {
      day.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    }
    final days = grouped.keys.toList();

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Support', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDuration(minutes)} · $people '
                      '${people == 1 ? 'person' : 'people'} · '
                      '$interactions interactions',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 160,
                  child: AppDropdown<_SupportPeriod>(
                    value: _period,
                    items: [
                      for (final period in _SupportPeriod.values)
                        DropdownMenuItem(
                          value: period,
                          child: Text(period.label),
                        ),
                    ],
                    onChanged: (period) {
                      if (period == null) return;
                      if (period == _SupportPeriod.custom) {
                        unawaited(_pickCustomRange(state));
                      } else {
                        _selectPeriod(period);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _logSupport,
                  icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
                  label: const Text('Log support'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _peoplePanel(state, theme),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 880;
                final modePanel = Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelHeader(
                        title: 'By mode',
                        subtitle: 'How you helped',
                        icon: Icons.diversity_3,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AllocationBars(
                        slices: [
                          for (final mode in modeTotals)
                            AllocationSlice(
                              key: mode.subcategoryId,
                              label: mode.name,
                              minutes: mode.minutes,
                            ),
                        ],
                        emptyLabel: 'No support logged in this period.',
                      ),
                    ],
                  ),
                );
                final peoplePanel = Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelHeader(
                        title: 'By person',
                        subtitle: personTotals.isEmpty
                            ? 'No interactions yet'
                            : '$people ${people == 1 ? 'person' : 'people'} '
                                  'supported',
                        icon: Icons.group_outlined,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (personTotals.isEmpty)
                        Text(
                          'Support entries record who you helped and how.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else
                        for (final total in personTotals.take(6))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 11,
                                  backgroundColor: scheme.tertiaryContainer,
                                  child: Text(
                                    total.person.characters.first.toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onTertiaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    total.person,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatDuration(total.minutes),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontFeatures: tabularFigures,
                                          ),
                                    ),
                                    Text(
                                      '${total.interactions} '
                                      '${total.interactions == 1 ? 'interaction' : 'interactions'}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                );
                if (stacked) {
                  return Column(
                    children: [
                      modePanel,
                      const SizedBox(height: AppSpacing.lg),
                      peoplePanel,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: modePanel),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: peoplePanel),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Text('Support log', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  _period.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _feed(state, theme, days, grouped),
          ],
        ),
      ),
    );
  }

  Widget _feed(
    AppState state,
    ThemeData theme,
    List<String> days,
    Map<String, List<WorkEntry>> grouped,
  ) {
    final scheme = theme.colorScheme;
    if (state.supportLoading) {
      return const Panel(
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
                Text('Loading support…'),
              ],
            ),
          ),
        ),
      );
    }
    if (state.supportError != null) {
      return Panel(
        tone: PanelTone.warning,
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, size: 28, color: scheme.error),
            const SizedBox(height: AppSpacing.sm),
            Text('Could not load support', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              state.supportError!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => unawaited(state.refreshSupport()),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (days.isEmpty) {
      return Panel(
        child: EmptyState(
          icon: Icons.volunteer_activism_outlined,
          title: 'No support logged in this period',
          message:
              'Reviews, pairing, unblocking and mentoring all belong here.',
          action: FilledButton.icon(
            onPressed: _logSupport,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Log support'),
          ),
        ),
      );
    }
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final day in days) ...[
            _SupportDayHeader(
              day: DateTime.parse(day),
              minutes: grouped[day]!.fold(
                0,
                (sum, entry) => sum + entry.minutes,
              ),
            ),
            for (final entry in grouped[day]!)
              SupportEntryRow(
                key: ValueKey('support-${entry.id}'),
                entry: entry,
                modeLabel: state.supportModeLabel(entry.subcategoryId),
                onEdit: (entry) => unawaited(_edit(entry)),
                onDelete: (entry) => unawaited(_delete(entry)),
              ),
          ],
        ],
      ),
    );
  }
}

class _SupportDayHeader extends StatelessWidget {
  const _SupportDayHeader({required this.day, required this.minutes});

  final DateTime day;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      color: scheme.tertiaryContainer.withValues(alpha: 0.15),
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
