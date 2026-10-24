import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/check_in.dart';
import '../models/enums.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';
import '../widgets/forms/checkin_dialog.dart';
import '../widgets/forms/review_timeframe_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/status_badge.dart';

class CheckinsScreen extends StatefulWidget {
  const CheckinsScreen({super.key});

  @override
  State<CheckinsScreen> createState() => _CheckinsScreenState();
}

class _CheckinsScreenState extends State<CheckinsScreen> {
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.read(context);
    if (!state.hasCheckInService || _requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(AppStateScope.read(context).loadCheckIns());
    });
  }

  Future<void> _create(BuildContext context) async {
    final state = AppStateScope.read(context);
    final checkIn = await showCheckInDialog(context, state: state);
    if (checkIn != null && context.mounted) {
      context.go('/checkins/${checkIn.id}');
    }
  }

  Future<void> _newReview(BuildContext context) async {
    final state = AppStateScope.read(context);
    final period = await showReviewTimeframeDialog(context, state: state);
    if (period == null || !context.mounted) return;
    context.go(
      '/checkins/review'
      '?start=${isoDate(period.start)}'
      '&end=${isoDate(period.end)}'
      '&timeframe=${period.timeframe.name}',
    );
  }

  String _excerpt(CheckIn checkIn) {
    final source = checkIn.summaryMarkdown.isNotEmpty
        ? checkIn.summaryMarkdown
        : checkIn.focusNotes;
    final plain = source
        .replaceAll(RegExp(r'[#>*`\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isEmpty) {
      return checkIn.focusNotes.isEmpty
          ? 'No focus notes or summary yet.'
          : checkIn.focusNotes;
    }
    return plain.length > 160 ? '${plain.substring(0, 160)}…' : plain;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final checkIns = state.checkIns;

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Check-ins', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      state.latestCheckIn == null
                          ? 'Turn captured work into a review-ready period report.'
                          : '${state.daysSinceCheckIn} days since the last check-in · '
                                '${checkIns.length} shown',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_newReview(context)),
                  icon: const Icon(Icons.rate_review_outlined, size: 16),
                  label: const Text('New review'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: () => unawaited(_create(context)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create check-in'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _KindFilter(
              selected: state.checkInKindFilter,
              onSelected: (kind) => unawaited(state.setCheckInKindFilter(kind)),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.checkInsError != null && checkIns.isNotEmpty) ...[
              Panel(
                tone: PanelTone.support,
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 17,
                      color: scheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Could not refresh check-ins. '
                        '${state.checkInsError}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          unawaited(state.loadCheckIns(force: true)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (state.checkInsLoading && checkIns.isEmpty)
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
                        Text('Loading check-ins…'),
                      ],
                    ),
                  ),
                ),
              )
            else if (state.checkInsError != null && checkIns.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load check-ins',
                  message: state.checkInsError!,
                  action: OutlinedButton.icon(
                    onPressed: () => unawaited(state.loadCheckIns(force: true)),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ),
              )
            else if (checkIns.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.event_note_outlined,
                  title: switch (state.checkInKindFilter) {
                    CheckInKind.manager => 'No manager check-ins yet',
                    CheckInKind.personal => 'No personal reviews yet',
                    null => 'No check-ins yet',
                  },
                  message: state.checkInKindFilter == null
                      ? 'A manager check-in snapshots the period since the '
                            'previous one. A personal review is for your own '
                            'weekly or monthly reflection.'
                      : 'Nothing matches this filter yet. Create one or switch '
                            'back to all check-ins.',
                  action: FilledButton.icon(
                    onPressed: () => unawaited(_create(context)),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create check-in'),
                  ),
                ),
              )
            else
              for (final checkIn in checkIns) ...[
                _CheckInCard(
                  checkIn: checkIn,
                  excerpt: _excerpt(checkIn),
                  support: checkIn.totals.supportMinutes,
                  onTap: () => context.go('/checkins/${checkIn.id}'),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            const SizedBox(height: AppSpacing.md),
            Text(
              'Final manager check-ins are read-only and become the boundary '
              'for the next period. Personal reviews never move it.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindFilter extends StatelessWidget {
  const _KindFilter({required this.selected, required this.onSelected});

  final CheckInKind? selected;
  final ValueChanged<CheckInKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget chip(String label, CheckInKind? kind) {
      final isSelected = selected == kind;
      return ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(kind),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: isSelected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        chip('All', null),
        chip('Manager', CheckInKind.manager),
        chip('Personal', CheckInKind.personal),
      ],
    );
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.checkIn,
    required this.excerpt,
    required this.support,
    required this.onTap,
  });

  final CheckIn checkIn;
  final String excerpt;
  final int support;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totals = checkIn.totals;
    return Panel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_note_outlined,
                size: 17,
                color: checkIn.isFinal ? scheme.tertiary : scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatRange(checkIn.periodStart, checkIn.periodEnd),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              CheckInKindBadge(kind: checkIn.kind),
              if (checkIn.audience != null) ...[
                const SizedBox(width: 6),
                CheckInAudienceBadge(audience: checkIn.audience!),
              ],
              const SizedBox(width: 6),
              CheckInStateBadge(state: checkIn.state),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            excerpt,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: 6,
            children: [
              _Metric(label: 'logged', value: formatDuration(totals.minutes)),
              _Metric(label: 'days', value: '${checkIn.daysCovered}'),
              _Metric(label: 'support', value: formatDuration(support)),
              _Metric(
                label: 'created',
                value: formatShortDate(checkIn.createdAt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: tabularFigures,
          ),
        ),
        const SizedBox(width: 4),
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
