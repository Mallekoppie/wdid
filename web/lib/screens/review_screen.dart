import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/drafts.dart';
import '../models/enums.dart';
import '../models/period_report.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/review_timeframe.dart';
import '../utils/time_utils.dart';
import '../widgets/checkin_aggregates.dart';
import '../widgets/forms/dialog_frame.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/status_badge.dart';

/// A live, unsaved personal review. The aggregates come from the same
/// authoritative period report a saved check-in reads. Only `Save review`
/// creates a record; leaving (back, or Discard) discards everything.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.start,
    required this.end,
    this.timeframe,
  });

  final DateTime start;
  final DateTime end;
  final ReviewTimeframe? timeframe;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _focusNotes = TextEditingController();
  final _summary = TextEditingController();
  bool _requested = false;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadReport());
    });
  }

  @override
  void dispose() {
    _focusNotes.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _loadReport({bool force = false}) async {
    await AppStateScope.read(
      context,
    ).loadReviewReport(widget.start, widget.end, force: force);
  }

  Future<void> _save(AppState state) async {
    final validation = validateReviewPeriod(
      widget.start,
      widget.end,
      today: state.today,
    );
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var saved = await state.createCheckIn(
        CheckInDraft(
          periodStart: widget.start,
          periodEnd: widget.end,
          kind: CheckInKind.personal,
          focusNotes: _focusNotes.text.trim(),
        ),
      );
      final summary = _summary.text.trim();
      if (summary.isNotEmpty) {
        saved = await state.updateCheckIn(
          saved.copyWith(
            summaryMarkdown: summary,
            state: CheckInState.edited,
          ),
        );
      }
      if (!mounted) return;
      context.go('/checkins/${saved.id}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the review. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final report = state.reviewReport;
    final reportMatches =
        state.reviewError == null &&
        state.reviewReport != null &&
        state.reviewReport!.fromDate == isoDate(widget.start) &&
        state.reviewReport!.toDate == isoDate(widget.end);
    final liveReport = reportMatches ? report : null;
    final emptyPeriod =
        liveReport != null &&
        liveReport.entryCount == 0 &&
        liveReport.totalMinutes == 0;
    final days = daysBetweenInclusive(widget.start, widget.end);

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'Discard review',
                  onPressed: _saving ? null : () => context.go('/checkins'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Personal review · ${formatRange(widget.start, widget.end)}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontFeatures: tabularFigures,
                            ),
                          ),
                          const CheckInKindBadge(kind: CheckInKind.personal),
                          if (widget.timeframe != null)
                            StatusBadge(
                              label: widget.timeframe!.label,
                              color: scheme.onSurfaceVariant,
                              icon: Icons.date_range_outlined,
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$days ${days == 1 ? 'day' : 'days'} · not saved yet · '
                        'never moves the manager boundary',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                TextButton(
                  onPressed: _saving ? null : () => context.go('/checkins'),
                  child: const Text('Discard'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _saving ? null : () => unawaited(_save(state)),
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save review'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _ReviewStats(
              report: liveReport,
              loading: state.reviewLoading,
              days: days,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              FormError(message: _error!),
            ],
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PanelHeader(
                    title: 'Reflection',
                    subtitle:
                        'What moved, what did not, and what to change next period',
                    icon: Icons.edit_note_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _focusNotes,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Focus notes (optional)',
                      hintText: 'What mattered in this period?',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _summary,
                    minLines: 10,
                    maxLines: 20,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Summary (optional, Markdown)',
                      hintText:
                          '## Where the time went\n- …\n\n## What to change\n- …',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.reviewLoading && liveReport == null)
              const Panel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
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
                        Text('Loading the period report…'),
                      ],
                    ),
                  ),
                ),
              )
            else if (state.reviewError != null)
              Panel(
                child: EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load the period report',
                  message: state.reviewError!,
                  action: OutlinedButton.icon(
                    onPressed: () => unawaited(_loadReport(force: true)),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ),
              )
            else if (emptyPeriod)
              Panel(
                child: EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'Nothing logged in this period',
                  message:
                      'There is no work to aggregate for these dates. Pick '
                      'another timeframe, or save the empty review anyway.',
                ),
              )
            else
              CheckInAggregates(state: state, report: liveReport),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : () => context.go('/checkins'),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Leave without saving'),
                ),
                const Spacer(),
                if (emptyPeriod)
                  OutlinedButton(
                    onPressed: _saving ? null : () => unawaited(_save(state)),
                    child: const Text('Save empty review'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStats extends StatelessWidget {
  const _ReviewStats({
    required this.report,
    required this.loading,
    required this.days,
  });

  final PeriodReport? report;
  final bool loading;
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = report?.totalMinutes;
    final entries = report?.entryCount;
    final support = report?.supportPeople.fold<int>(
      0,
      (sum, person) => sum + person.minutes,
    );
    Widget stat(String label, String value) => Column(
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

    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.md,
      children: [
        stat(
          'logged',
          loading && total == null
              ? '…'
              : total == null
              ? '—'
              : formatDuration(total),
        ),
        stat('days', '$days'),
        stat('entries', loading && entries == null ? '…' : '${entries ?? '—'}'),
        stat(
          'support',
          loading && support == null
              ? '…'
              : support == null
              ? '—'
              : formatDuration(support),
        ),
      ],
    );
  }
}
