import 'dart:async';

import 'package:flutter/material.dart';

import '../models/work_item.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/analytics.dart';
import '../utils/time_utils.dart';
import '../widgets/allocation_bars.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/entry_row.dart';
import '../widgets/forms/support_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';

enum _SupportPeriod {
  quarter('This quarter'),
  month('This month'),
  all('All time');

  const _SupportPeriod(this.label);
  final String label;
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  _SupportPeriod _period = _SupportPeriod.quarter;

  DateTime _start(AppState state) {
    return switch (_period) {
      _SupportPeriod.quarter => startOfQuarter(state.today),
      _SupportPeriod.month => DateTime(state.today.year, state.today.month, 1),
      _SupportPeriod.all => DateTime(2000),
    };
  }

  Future<void> _logSupport() async {
    final state = AppStateScope.read(context);
    final saved = await showSupportDialog(context, state: state);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support entry saved')),
      );
    }
  }

  Future<void> _edit(WorkItem item) async {
    final state = AppStateScope.read(context);
    final saved =
        await showSupportDialog(context, state: state, existing: item);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support entry updated')),
      );
    }
  }

  Future<void> _delete(WorkItem item) async {
    final state = AppStateScope.read(context);
    try {
      await state.deleteEntry(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support entry deleted')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the entry: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = entriesInRange(
      state.workItems,
      _start(state),
      state.today,
    ).where((item) => item.isSupport).toList();
    final minutes = supportMinutes(entries);
    final people = supportPeople(entries);
    final byMode = supportByMode(entries);
    final byPerson = supportByPerson(entries).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final grouped = groupByDay(entries);
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

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
                      '${formatDuration(minutes)} · ${people.length} '
                      '${people.length == 1 ? 'person' : 'people'} · '
                      '${entries.length} interactions',
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
                      if (period != null) setState(() => _period = period);
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
                          for (final entry in byMode.entries)
                            AllocationSlice(
                              key: entry.key.name,
                              label: entry.key.label,
                              minutes: entry.value,
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
                        subtitle: byPerson.isEmpty
                            ? 'No interactions yet'
                            : '${people.length} people supported',
                        icon: Icons.group_outlined,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (byPerson.isEmpty)
                        Text(
                          'Support entries record who you helped and how.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else
                        for (final entry in byPerson.take(6))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 11,
                                  backgroundColor:
                                      scheme.tertiaryContainer,
                                  child: Text(
                                    entry.key.characters.first.toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onTertiaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                Text(
                                  formatDuration(entry.value),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontFeatures: tabularFigures,
                                  ),
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
            if (days.isEmpty)
              Panel(
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
              )
            else
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final day in days) ...[
                      _SupportDayHeader(
                        day: DateTime.parse(day),
                        minutes: totalMinutes(grouped[day]!),
                      ),
                      for (final item in grouped[day]!)
                        EntryRow(
                          item: item,
                          initiatives: state.initiatives,
                          onEdit: (item) => unawaited(_edit(item)),
                          onDelete: (item) => unawaited(_delete(item)),
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
