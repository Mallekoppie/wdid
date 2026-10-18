import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/work_item.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/attribution.dart';
import '../utils/time_utils.dart';
import '../widgets/allocation_bars.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/entry_row.dart';
import '../widgets/forms/entry_dialog.dart';
import '../widgets/forms/support_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/quick_add_bar.dart';
import '../widgets/screen_states.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  void _edit(WorkItem item) {
    unawaited(_editAsync(item));
  }

  Future<void> _editAsync(WorkItem item) async {
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

  Future<void> _openEntryForm() async {
    final state = AppStateScope.read(context);
    final saved = await showEntryDialog(context, state: state);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry saved')),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = state.todayItems;

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: AppSpacing.lg,
              runSpacing: 4,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      formatFullDate(state.today),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${formatDuration(state.weekMinutes)} this week',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const _TimerCard(),
            const SizedBox(height: AppSpacing.md),
            QuickAddBar(onOpenFullForm: _openEntryForm),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Text('Today', style: theme.textTheme.titleMedium),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  formatDuration(state.todayMinutes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openEntryForm,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('Add entry'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Panel(
              padding: EdgeInsets.zero,
              child: items.isEmpty
                  ? EmptyState(
                      icon: Icons.timelapse_outlined,
                      title: 'Nothing logged yet',
                      message:
                          'Start a timer above, or add an entry after the fact.',
                      action: FilledButton.icon(
                        onPressed: _openEntryForm,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add entry'),
                      ),
                    )
                  : Column(
                      children: [
                        for (final item in items)
                          EntryRow(
                            item: item,
                            initiatives: state.initiatives,
                            onEdit: _edit,
                            onDelete: (item) => unawaited(_delete(item)),
                            onOpenInitiative: (item) {
                              if (item.initiativeId != null) {
                                context.go('/initiatives/${item.initiativeId}');
                              }
                            },
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _logSupport,
                  icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
                  label: const Text('Log support'),
                ),
                const Spacer(),
                Text(
                  '${items.where((item) => item.isSupport).length} support interactions today',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 880;
                final week = Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelHeader(
                        title: 'Week by attribution',
                        subtitle:
                            '${formatDuration(state.weekMinutes)} logged this week',
                        icon: Icons.insights_outlined,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AllocationBars(slices: state.weekAllocation),
                    ],
                  ),
                );
                final note = const _DayNoteCard();
                if (stacked) {
                  return Column(
                    children: [
                      week,
                      const SizedBox(height: AppSpacing.lg),
                      note,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: week),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: note),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerCard extends StatefulWidget {
  const _TimerCard();

  @override
  State<_TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends State<_TimerCard> {
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final state = AppStateScope.read(context);
    setState(() => _busy = true);
    try {
      state.startTimer(description: _description.text);
      if (!mounted) return;
      setState(() => _busy = false);
      _description.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Timer started · ${state.activeTimer?.attribution.label}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _stop() async {
    final state = AppStateScope.read(context);
    setState(() => _busy = true);
    try {
      final item = await state.stopTimer();
      if (!mounted) return;
      setState(() => _busy = false);
      if (item != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${formatDuration(item.minutes)} · ${item.summary}',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not stop the timer: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timer = state.activeTimer;
    final running = timer != null;
    final elapsed = timer?.elapsedAt(DateTime.now()) ?? Duration.zero;
    final choices = state.attributionChoices;
    final choice = state.lastAttribution ??
        (choices.isEmpty ? null : choices.first);

    return Panel(
      tone: running ? PanelTone.accent : PanelTone.normal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: running
                ? timer.isPaused
                    ? 'Timer paused'
                    : 'Running'
                : 'Start a timer',
            subtitle: running
                ? 'Since ${formatTime(timer.startedAt)}'
                : 'Pick an attribution and start working. Last choice is remembered.',
            icon: running ? Icons.timer_outlined : Icons.play_circle_outline,
            trailing: running
                ? Text(
                    formatClock(elapsed),
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (timer == null)
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;
                final description = TextField(
                  controller: _description,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _start(),
                  decoration: const InputDecoration(
                    hintText: 'What are you working on?',
                    prefixIcon: Icon(Icons.edit_note, size: 18),
                  ),
                );
                final attribution = AppDropdown<AttributionChoice>(
                  value: choice ?? (choices.isEmpty ? null : choices.first),
                  label: 'Attribution',
                  enabled: choices.isNotEmpty,
                  items: [
                    for (final option in choices)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) state.setAttribution(value);
                  },
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      description,
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: attribution),
                          const SizedBox(width: AppSpacing.sm),
                          FilledButton.icon(
                            onPressed: _busy ? null : _start,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Start'),
                          ),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: description),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(width: 220, child: attribution),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start'),
                    ),
                  ],
                );
              },
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      timer.attribution.isInitiative
                          ? Icons.flag_outlined
                          : Icons.category_outlined,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timer.attribution.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '·',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        timer.description,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          timer.isPaused ? state.resumeTimer : state.pauseTimer,
                      icon: Icon(
                        timer.isPaused ? Icons.play_arrow : Icons.pause,
                        size: 16,
                      ),
                      label: Text(timer.isPaused ? 'Resume' : 'Pause'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _stop,
                      icon: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.stop, size: 16),
                      label: const Text('Stop & save'),
                    ),
                    if (timer.attribution.initiativeId != null)
                      TextButton.icon(
                        onPressed: () => context.go(
                          '/initiatives/${timer.attribution.initiativeId}',
                        ),
                        icon: const Icon(Icons.arrow_outward, size: 15),
                        label: const Text('Open initiative'),
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayNoteCard extends StatefulWidget {
  const _DayNoteCard();

  @override
  State<_DayNoteCard> createState() => _DayNoteCardState();
}

class _DayNoteCardState extends State<_DayNoteCard> {
  final _controller = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _saved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _controller.text = AppStateScope.of(context).todayNote?.text ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = AppStateScope.read(context);
    setState(() {
      _saving = true;
      _saved = false;
    });
    try {
      await state.saveDayNote(_controller.text.trim());
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day note saved')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the note: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'End of day note',
            subtitle: _saved ? 'Saved just now' : 'Context that is easy to lose',
            icon: Icons.notes_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 6,
            onChanged: (_) {
              if (_saved) setState(() => _saved = false);
            },
            decoration: const InputDecoration(
              hintText: 'What should future-you remember about today?',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                formatDayHeader(DateTime.now()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save note'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
