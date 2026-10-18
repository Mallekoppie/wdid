import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/initiative.dart';
import '../models/work_item.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/analytics.dart';
import '../utils/time_utils.dart';
import '../widgets/forms/initiative_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/status_badge.dart';

class InitiativesScreen extends StatelessWidget {
  const InitiativesScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final state = AppStateScope.read(context);
    final saved = await showInitiativeDialog(context, state: state);
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Initiative created · ${saved.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = state.openInitiatives;
    final archived = state.archivedInitiatives;
    final quarter = entriesInRange(
      state.workItems,
      startOfQuarter(state.today),
      state.today,
    );

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Initiatives', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${open.length} open · ${formatDuration(totalMinutes(quarter))} logged this quarter',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => unawaited(_create(context)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New initiative'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (open.isEmpty && archived.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'No initiatives yet',
                  message:
                      'Create the first major body of work so captured time has somewhere to land.',
                  action: FilledButton.icon(
                    onPressed: () => unawaited(_create(context)),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New initiative'),
                  ),
                ),
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 1080
                      ? 3
                      : constraints.maxWidth > 700
                          ? 2
                          : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * AppSpacing.lg) /
                          columns;
                  return Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.lg,
                    children: [
                      for (final initiative in open)
                        SizedBox(
                          width: width,
                          child: _InitiativeCard(
                            initiative: initiative,
                            state: state,
                            quarterEntries: quarter,
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Panel(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'Archived (${archived.length})',
                      style: theme.textTheme.titleMedium,
                    ),
                    children: [
                      for (final initiative in archived)
                        _ArchivedRow(initiative: initiative, state: state),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _InitiativeCard extends StatelessWidget {
  const _InitiativeCard({
    required this.initiative,
    required this.state,
    required this.quarterEntries,
  });

  final Initiative initiative;
  final AppState state;
  final List<WorkItem> quarterEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = state.itemsForInitiative(initiative.id);
    final quarterMinutes = initiativeMinutesIn(
      quarterEntries,
      initiative.id,
    );
    final last = lastActivity(state.workItems, initiative.id);

    return Panel(
      onTap: () => context.go('/initiatives/${initiative.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  initiative.name,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              InitiativeStatusBadge(status: initiative.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            initiative.targetOutcome.isEmpty
                ? initiative.summary.isEmpty
                    ? 'No target outcome set.'
                    : initiative.summary
                : initiative.targetOutcome,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                formatDuration(quarterMinutes),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'this quarter',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${initiative.progress}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: initiative.progress / 100,
              minHeight: 5,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                Icons.history,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  last == null
                      ? 'No activity yet'
                      : 'Last activity ${formatRelativeDay(last)} · ${entries.length} entries',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (initiative.tags.isNotEmpty)
                Text(
                  initiative.tags.take(2).join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.initiative, required this.state});

  final Initiative initiative;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minutes = state.minutesForInitiative(initiative.id);
    return InkWell(
      onTap: () => context.go('/initiatives/${initiative.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                initiative.name,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              formatDuration(minutes),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: tabularFigures,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            InitiativeStatusBadge(status: initiative.status),
          ],
        ),
      ),
    );
  }
}
