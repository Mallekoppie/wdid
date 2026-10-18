import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/check_in.dart';
import '../models/enums.dart';
import '../models/initiative.dart';
import '../models/work_item.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/analytics.dart';
import '../utils/time_utils.dart';
import '../widgets/allocation_bars.dart';
import '../widgets/forms/export_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/simple_markdown.dart';
import '../widgets/status_badge.dart';

class CheckinDetailScreen extends StatefulWidget {
  const CheckinDetailScreen({super.key, required this.checkInId});

  final String checkInId;

  @override
  State<CheckinDetailScreen> createState() => _CheckinDetailScreenState();
}

class _CheckinDetailScreenState extends State<CheckinDetailScreen> {
  final _editor = TextEditingController();
  bool _editing = false;
  bool _generating = false;
  bool _saving = false;

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  CheckIn? _find(AppState state) {
    for (final checkIn in state.checkIns) {
      if (checkIn.id == widget.checkInId) return checkIn;
    }
    return null;
  }

  Future<void> _generate(AppState state, CheckIn checkIn) async {
    if (checkIn.state == CheckInState.edited &&
        checkIn.summaryMarkdown.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace edited summary?'),
          content: const Text(
            'Generation will replace your manual edits. Copy the current summary '
            'first if you want to keep it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Regenerate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() => _generating = true);
    try {
      await state.generateSummary(checkIn);
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Summary generated')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Generation failed. The existing summary is unchanged. $error',
          ),
        ),
      );
    }
  }

  Future<void> _copyPrompt(AppState state, CheckIn checkIn) async {
    try {
      final text =
          await state.buildPrompt(checkIn.periodStart, checkIn.periodEnd);
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prompt copied to clipboard')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not build the prompt: $error')),
      );
    }
  }

  Future<void> _saveSummary(AppState state, CheckIn checkIn) async {
    setState(() => _saving = true);
    try {
      await state.saveSummary(checkIn, _editor.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Summary saved')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the summary: $error')),
      );
    }
  }

  Future<void> _finalize(AppState state, CheckIn checkIn) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark check-in as final?'),
        content: const Text(
          'Final check-ins are read-only and become the boundary for the next '
          'period. Exports remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark final'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await state.finalizeCheckIn(checkIn);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-in marked final')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not finalize the check-in: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final checkIn = _find(state);

    if (checkIn == null) {
      return ScreenBody(
        child: PageScaffold(
          child: Panel(
            child: EmptyState(
              icon: Icons.event_note_outlined,
              title: 'Check-in not found',
              message: 'It may have been removed.',
              action: FilledButton(
                onPressed: () => context.go('/checkins'),
                child: const Text('Back to check-ins'),
              ),
            ),
          ),
        ),
      );
    }

    final entries = entriesInRange(
      state.workItems,
      checkIn.periodStart,
      checkIn.periodEnd,
    );
    final support = entries.where((item) => item.isSupport).toList();
    final supportPeople = supportByPerson(support).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final finalState = checkIn.isFinal;

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'Back to check-ins',
                  onPressed: () => context.go('/checkins'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Check-in · ${formatRange(checkIn.periodStart, checkIn.periodEnd)}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          CheckInStateBadge(state: checkIn.state),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Created ${formatFullDate(checkIn.createdAt)} · '
                        'prompt ${checkIn.promptVersion}'
                        '${checkIn.summaryModel == null ? '' : ' · ${checkIn.summaryModel}'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => showExportDialog(
                    context,
                    state: state,
                    start: checkIn.periodStart,
                    end: checkIn.periodEnd,
                  ),
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export'),
                ),
                const SizedBox(width: 6),
                if (!finalState)
                  FilledButton.icon(
                    onPressed: () => unawaited(_finalize(state, checkIn)),
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text('Mark final'),
                  ),
              ],
            ),
            if (finalState) ...[
              const SizedBox(height: AppSpacing.md),
              Panel(
                tone: PanelTone.support,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 17, color: scheme.tertiary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Final check-in — read-only boundary for the next period.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                _Stat(
                  label: 'logged',
                  value: formatDuration(checkIn.totals.minutes),
                ),
                _Stat(label: 'days', value: '${checkIn.daysCovered}'),
                _Stat(
                  label: 'initiatives',
                  value: '${checkIn.totals.byInitiative.length}',
                ),
                _Stat(
                  label: 'support',
                  value: formatDuration(supportMinutes(support)),
                ),
                _Stat(
                  label: 'interactions',
                  value: '${support.length}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PanelHeader(
                    title: 'Summary',
                    subtitle: _editing
                        ? 'Editing Markdown · generation will not overwrite silently'
                        : checkIn.summaryModel == null
                            ? 'No model recorded'
                            : 'Model: ${checkIn.summaryModel}',
                    icon: Icons.auto_awesome_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      if (!finalState && !_editing) ...[
                        FilledButton.tonalIcon(
                          onPressed: _generating
                              ? null
                              : () => unawaited(_generate(state, checkIn)),
                          icon: _generating
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_awesome, size: 16),
                          label: Text(
                            checkIn.summaryMarkdown.isEmpty
                                ? 'Generate with AI'
                                : 'Regenerate',
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_copyPrompt(state, checkIn)),
                        icon: const Icon(Icons.copy_all, size: 15),
                        label: const Text('Copy prompt'),
                      ),
                      const Spacer(),
                      if (!finalState && !_editing)
                        TextButton.icon(
                          onPressed: () {
                            _editor.text = checkIn.summaryMarkdown;
                            setState(() => _editing = true);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Edit'),
                        ),
                      if (!finalState && _editing) ...[
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() => _editing = false);
                                },
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () => unawaited(_saveSummary(state, checkIn)),
                          child: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Save summary'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_editing)
                    TextField(
                      controller: _editor,
                      minLines: 14,
                      maxLines: 24,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: '## Highlights\n- …',
                      ),
                    )
                  else if (checkIn.summaryMarkdown.isEmpty)
                    EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: 'No summary yet',
                      message:
                          'Generate one from the captured entries, or copy the '
                          'prompt into your own model.',
                      action: finalState
                          ? null
                          : FilledButton.icon(
                              onPressed: _generating
                                  ? null
                                  : () =>
                                      unawaited(_generate(state, checkIn)),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('Generate with AI'),
                            ),
                    )
                  else
                    SimpleMarkdown(checkIn.summaryMarkdown),
                ],
              ),
            ),
            if (checkIn.focusNotes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PanelHeader(
                      title: 'Focus notes',
                      icon: Icons.push_pin_outlined,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      checkIn.focusNotes,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 900;
                final allocation = Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelHeader(
                        title: 'Time allocation',
                        subtitle: formatDuration(totalMinutes(entries)),
                        icon: Icons.pie_chart_outline,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AllocationBars(
                        slices: allocationFor(entries, state.initiatives),
                      ),
                    ],
                  ),
                );
                final initiatives = Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelHeader(
                        title: 'Initiative progress',
                        subtitle:
                            '${checkIn.totals.byInitiative.length} initiatives touched',
                        icon: Icons.flag_outlined,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (checkIn.totals.byInitiative.isEmpty)
                        Text(
                          'No initiative time in this period.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else
                        for (final entry in _sortedInitiativeTotals(checkIn))
                          _InitiativeProgressRow(
                            initiative: _initiative(state, entry.key),
                            minutes: entry.value,
                          ),
                    ],
                  ),
                );
                if (stacked) {
                  return Column(
                    children: [
                      allocation,
                      const SizedBox(height: AppSpacing.lg),
                      initiatives,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: allocation),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: initiatives),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PanelHeader(
                    title: 'Support & collaboration',
                    subtitle:
                        '${formatDuration(supportMinutes(support))} across '
                        '${supportPeople.length} people',
                    icon: Icons.volunteer_activism_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (support.isEmpty)
                    Text(
                      'No support logged in this period.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final person in supportPeople)
                      _SupportPersonRow(
                        person: person.key,
                        minutes: person.value,
                        entries: support
                            .where((item) => item.person == person.key)
                            .toList(),
                      ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => showExportDialog(
                    context,
                    state: state,
                    start: checkIn.periodStart,
                    end: checkIn.periodEnd,
                  ),
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export summary.md + data.json'),
                ),
                const Spacer(),
                if (!finalState)
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_finalize(state, checkIn)),
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text('Mark as final'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<MapEntry<String, int>> _sortedInitiativeTotals(CheckIn checkIn) {
    final entries = checkIn.totals.byInitiative.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  Initiative? _initiative(AppState state, String id) {
    for (final initiative in state.initiatives) {
      if (initiative.id == id) return initiative;
    }
    return null;
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: tabularFigures,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InitiativeProgressRow extends StatelessWidget {
  const _InitiativeProgressRow({required this.initiative, required this.minutes});

  final Initiative? initiative;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = initiative?.progress ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  initiative?.name ?? 'Unknown initiative',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (initiative != null) ...[
                InitiativeStatusBadge(status: initiative!.status),
                const SizedBox(width: 8),
              ],
              Text(
                formatDuration(minutes),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress / 100,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportPersonRow extends StatelessWidget {
  const _SupportPersonRow({
    required this.person,
    required this.minutes,
    required this.entries,
  });

  final String person;
  final int minutes;
  final List<WorkItem> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: scheme.tertiaryContainer,
            child: Text(
              person.characters.first.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      person,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${formatDuration(minutes)} · ${entries.length} '
                      '${entries.length == 1 ? 'interaction' : 'interactions'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                for (final entry in entries.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.outcome.isEmpty
                          ? entry.summary
                          : '${entry.summary} — ${entry.outcome}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
