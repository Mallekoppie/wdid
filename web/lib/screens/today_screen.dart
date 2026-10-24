import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/app_settings.dart';
import '../models/work_entry.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/review_timeframe.dart';
import '../utils/time_utils.dart';
import '../widgets/allocation_bars.dart';
import '../widgets/panel.dart';
import '../widgets/quick_capture_bar.dart';
import '../widgets/screen_states.dart';
import '../widgets/service_timer_card.dart';
import '../widgets/work_entry_row.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Future<void> _editOutcome(WorkEntry entry) async {
    final state = AppStateScope.read(context);
    final outcome = await showDialog<String>(
      context: context,
      builder: (context) => _OutcomeDialog(entry: entry),
    );
    if (outcome == null || !mounted) return;

    try {
      await state.updateWorkEntry(entry.copyWith(outcome: outcome));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Outcome saved')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the outcome: $error')),
      );
    }
  }

  Widget _serviceTodayList(AppState state) {
    if (state.entriesLoading) {
      return Panel(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Loading today's entries…",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state.entriesError != null) {
      final theme = Theme.of(context);
      return Panel(
        tone: PanelTone.warning,
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 28,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Could not load today's entries",
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              state.entriesError!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: state.loadEntries,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final entries = state.todayEntries;
    if (entries.isEmpty) {
      return const Panel(
        padding: EdgeInsets.zero,
        child: EmptyState(
          icon: Icons.timelapse_outlined,
          title: 'Nothing logged yet',
          message: 'Capture your first entry above.',
        ),
      );
    }

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final entry in entries)
            WorkEntryRow(
              entry: entry,
              category: state.categoryById(entry.categoryId),
              subcategory: state.subcategoryById(entry.subcategoryId),
              onEditOutcome: (entry) => unawaited(_editOutcome(entry)),
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
    final hasSummary = state.summaryApi != null;
    final weekPending = hasSummary && state.weekReport == null;
    final weekLabel = !weekPending
        ? '${formatDuration(state.weekMinutes)} this week'
        : state.weekReportError != null
        ? 'This week unavailable'
        : 'Loading this week…';

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
                  weekLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
            if (state.reviewPromptDue) ...[
              const SizedBox(height: AppSpacing.md),
              const _ReviewPrompt(),
            ],
            const SizedBox(height: AppSpacing.lg),
            const ServiceTimerCard(),
            const SizedBox(height: AppSpacing.md),
            const QuickCaptureBar(),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Text('Today', style: theme.textTheme.titleMedium),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  formatDuration(state.todayEntryMinutes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _serviceTodayList(state),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 880;
                final week = Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PanelHeader(
                        title: 'Week by category',
                        subtitle: weekPending
                            ? state.weekReportError != null
                                  ? 'Unavailable'
                                  : 'Loading…'
                            : '${formatDuration(state.weekMinutes)} logged this week',
                        icon: Icons.insights_outlined,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (hasSummary &&
                          state.weekReportError != null &&
                          state.weekReport == null)
                        _WeekReportError(
                          message: state.weekReportError!,
                          onRetry: state.loadWeekReport,
                        )
                      else if (weekPending)
                        const _WeekReportLoading()
                      else
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

class _WeekReportLoading extends StatelessWidget {
  const _WeekReportLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Loading this week…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _WeekReportError extends StatelessWidget {
  const _WeekReportError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('Could not load this week', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => unawaited(onRetry()),
          icon: const Icon(Icons.refresh, size: 15),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

class _OutcomeDialog extends StatefulWidget {
  const _OutcomeDialog({required this.entry});

  final WorkEntry entry;

  @override
  State<_OutcomeDialog> createState() => _OutcomeDialogState();
}

class _OutcomeDialogState extends State<_OutcomeDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.entry.outcome,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.entry.outcome.isEmpty ? 'Add outcome' : 'Edit outcome',
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Outcome',
          hintText: 'Script runs against staging',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save outcome'),
        ),
      ],
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
  String? _syncedNoteId;
  bool _dirty = false;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.of(context);
    final note = state.todayNote;
    // Notes load asynchronously in service mode. Adopt the server's text once
    // it arrives, unless the user has already started typing.
    if (_dirty && _syncedNoteId == note?.id) return;
    if (_syncedNoteId == note?.id) return;
    _syncedNoteId = note?.id;
    _controller.text = note?.text ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write a note first.');
      return;
    }
    final state = AppStateScope.read(context);
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await state.saveDayNote(text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
        _dirty = false;
        _syncedNoteId = state.todayNote?.id;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Day note saved')));
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
    final state = AppStateScope.of(context);
    final loading = state.notesLoading && state.todayNote == null;
    final loadError = state.notesError;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'End of day note',
            subtitle: _saved
                ? 'Saved just now'
                : 'Context that is easy to lose',
            icon: Icons.notes_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          if (loadError != null)
            Row(
              children: [
                Icon(Icons.cloud_off_outlined, size: 20, color: scheme.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(loadError, style: theme.textTheme.bodySmall),
                ),
                OutlinedButton.icon(
                  onPressed: state.loadNotes,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            )
          else if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 6,
              onChanged: (_) {
                _dirty = true;
                if (_saved) setState(() => _saved = false);
              },
              decoration: InputDecoration(
                hintText: 'What should future-you remember about today?',
                errorText: _error,
                errorMaxLines: 2,
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

/// A dismissible, inline personal-review hint. It is not a dialog and creates
/// nothing: accepting it opens the live review, where saving is explicit.
class _ReviewPrompt extends StatelessWidget {
  const _ReviewPrompt();

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final monthly = state.settings.reviewCadence == ReviewCadence.monthly;
    final timeframe = monthly
        ? ReviewTimeframe.last30Days
        : ReviewTimeframe.last7Days;
    final period = state.reviewPromptPeriod;

    return Panel(
      tone: PanelTone.accent,
      child: Row(
        children: [
          Icon(Icons.rate_review_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  monthly
                      ? 'Last month is ready to review'
                      : 'Last week is ready to review',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  'A personal review is open for '
                  '${formatRange(period.start, period.end)}. Nothing is saved '
                  'unless you save it, and it never moves the manager boundary.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: state.dismissReviewPrompt,
            child: const Text('Dismiss'),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: () => context.go(
              '/checkins/review'
              '?start=${isoDate(period.start)}'
              '&end=${isoDate(period.end)}'
              '&timeframe=${timeframe.name}',
            ),
            icon: const Icon(Icons.arrow_forward, size: 15),
            label: const Text('Review now'),
          ),
        ],
      ),
    );
  }
}
