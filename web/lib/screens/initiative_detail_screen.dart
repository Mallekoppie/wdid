import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/enums.dart';
import '../models/initiative.dart';
import '../models/note.dart';
import '../models/work_item.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/analytics.dart';
import '../utils/attribution.dart';
import '../utils/time_utils.dart';
import '../widgets/entry_row.dart';
import '../widgets/forms/entry_dialog.dart';
import '../widgets/forms/initiative_dialog.dart';
import '../widgets/forms/note_dialog.dart';
import '../widgets/forms/support_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/stat_tile.dart';
import '../widgets/status_badge.dart';

/// The demo adapter's initiative detail. The service-backed project detail
/// lives in `project_detail_screen.dart`; screens without a service contract
/// still render this older Initiative record.
class InitiativeDetailScreen extends StatefulWidget {
  const InitiativeDetailScreen({super.key, required this.initiativeId});

  final String initiativeId;

  @override
  State<InitiativeDetailScreen> createState() => _InitiativeDetailScreenState();
}

class _InitiativeDetailScreenState extends State<InitiativeDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  int _tab = 0;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Initiative? _find(AppState state) {
    for (final initiative in state.initiatives) {
      if (initiative.id == widget.initiativeId) return initiative;
    }
    return null;
  }

  Future<void> _logTime(AppState state, Initiative initiative) async {
    final saved = await showEntryDialog(
      context,
      state: state,
      initialChoice: AttributionChoice.initiative(
        initiative.id,
        initiative.name,
      ),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry saved')));
    }
  }

  Future<void> _addNote(AppState state, Initiative initiative) async {
    final saved = await showNoteDialog(
      context,
      state: state,
      initiativeId: initiative.id,
      title: 'Add note',
      subtitle: initiative.name,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note added')));
    }
  }

  Future<void> _edit(AppState state, Initiative initiative) async {
    final saved = await showInitiativeDialog(
      context,
      state: state,
      existing: initiative,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Initiative updated')));
    }
  }

  Future<void> _editEntry(AppState state, WorkItem item) async {
    final saved = item.isSupport
        ? await showSupportDialog(context, state: state, existing: item)
        : await showEntryDialog(context, state: state, existing: item);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry updated')));
    }
  }

  Future<void> _deleteEntry(AppState state, WorkItem item) async {
    try {
      await state.deleteEntry(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the entry: $error')),
      );
    }
  }

  Future<void> _changeStatus(
    AppState state,
    Initiative initiative,
    InitiativeStatus status,
  ) async {
    try {
      await state.setInitiativeStatus(initiative, status);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Status set to ${status.label}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update status: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initiative = _find(state);

    if (initiative == null) {
      return ScreenBody(
        child: PageScaffold(
          child: Panel(
            child: EmptyState(
              icon: Icons.flag_outlined,
              title: 'Initiative not found',
              message: 'It may have been archived or removed.',
              action: FilledButton(
                onPressed: () => context.go('/initiatives'),
                child: const Text('Back to initiatives'),
              ),
            ),
          ),
        ),
      );
    }

    final entries = state.itemsForInitiative(initiative.id);
    final quarterEntries = entriesInRange(
      entries,
      startOfQuarter(state.today),
      state.today,
    );
    final quarterMinutes = initiativeMinutesIn(quarterEntries, initiative.id);
    final last = lastActivity(state.workItems, initiative.id);
    final archived = initiative.isArchived;
    final notes = state.notesForInitiative(initiative.id);

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'Back to initiatives',
                  onPressed: () => context.go('/initiatives'),
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
                              initiative.name,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          InitiativeStatusBadge(status: initiative.status),
                        ],
                      ),
                      if (initiative.summary.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          initiative.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (!archived) ...[
                  IconButton(
                    tooltip: 'Edit initiative',
                    onPressed: () => unawaited(_edit(state, initiative)),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_addNote(state, initiative)),
                    icon: const Icon(Icons.notes_outlined, size: 16),
                    label: const Text('Add note'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: () => unawaited(_logTime(state, initiative)),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Log time'),
                  ),
                ],
                PopupMenuButton<InitiativeStatus>(
                  tooltip: 'Change status',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (status) =>
                      unawaited(_changeStatus(state, initiative, status)),
                  itemBuilder: (context) => [
                    for (final status in InitiativeStatus.values)
                      PopupMenuItem(
                        value: status,
                        child: Text(
                          status == initiative.status
                              ? '${status.label} (current)'
                              : status.label,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (archived) ...[
              const SizedBox(height: AppSpacing.md),
              Panel(
                tone: PanelTone.warning,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: scheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'This initiative is archived and read-only.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(
                        _changeStatus(
                          state,
                          initiative,
                          InitiativeStatus.active,
                        ),
                      ),
                      child: const Text('Restore'),
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
                StatTile(
                  label: 'This quarter',
                  value: formatDuration(quarterMinutes),
                  icon: Icons.schedule,
                ),
                StatTile(
                  label: 'Entries',
                  value: '${entries.length}',
                  icon: Icons.list_alt,
                ),
                StatTile(
                  label: 'Progress',
                  value: '${initiative.progress}%',
                  icon: Icons.trending_up,
                ),
                StatTile(
                  label: 'Last activity',
                  value: last == null ? '—' : formatRelativeDay(last),
                  icon: Icons.history,
                ),
                if (initiative.targetDate != null)
                  StatTile(
                    label: 'Target date',
                    value: formatShortDate(initiative.targetDate!),
                    icon: Icons.event_outlined,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _ProgressCard(
              initiative: initiative,
              enabled: !archived,
              onSave: (value) async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await state.setInitiativeProgress(initiative, value);
                } catch (error) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Could not save progress: $error')),
                  );
                }
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            TabBar(
              controller: _tabs,
              onTap: (index) => setState(() => _tab = index),
              tabs: const [
                Tab(text: 'Timeline'),
                Tab(text: 'Notes'),
                Tab(text: 'Milestones'),
                Tab(text: 'Report'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            switch (_tab) {
              0 => _timeline(state, initiative, entries),
              1 => _notes(initiative, notes),
              2 => _milestones(),
              _ => _report(initiative, entries),
            },
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _timeline(
    AppState state,
    Initiative initiative,
    List<WorkItem> entries,
  ) {
    return Panel(
      padding: EdgeInsets.zero,
      child: entries.isEmpty
          ? EmptyState(
              icon: Icons.timeline,
              title: 'No time logged yet',
              message:
                  'Log a block against this initiative to start the timeline.',
              action: initiative.isArchived
                  ? null
                  : FilledButton.icon(
                      onPressed: () => unawaited(_logTime(state, initiative)),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Log time'),
                    ),
            )
          : Column(
              children: [
                for (final item in entries)
                  EntryRow(
                    item: item,
                    initiatives: state.initiatives,
                    onEdit: (item) => unawaited(_editEntry(state, item)),
                    onDelete: (item) => unawaited(_deleteEntry(state, item)),
                    onOpenInitiative: (item) {
                      if (item.initiativeId != null) {
                        context.go('/initiatives/${item.initiativeId}');
                      }
                    },
                  ),
              ],
            ),
    );
  }

  Widget _notes(Initiative initiative, List<Note> notes) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (notes.isEmpty) {
      return Panel(
        child: EmptyState(
          icon: Icons.notes_outlined,
          title: 'No notes yet',
          message: 'Capture decisions and context while they are fresh.',
        ),
      );
    }
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, note) in notes.indexed) ...[
            if (index > 0) const Divider(height: AppSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(note.text, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  note.date,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _milestones() {
    return Panel(
      child: EmptyState(
        icon: Icons.checklist,
        title: 'Milestones are not in the v1 contract',
        message:
            'The design calls for a dated milestone checklist, but the documented '
            'service contract has no milestone entity yet. This tab will connect '
            'once that contract is defined.',
      ),
    );
  }

  Widget _report(Initiative initiative, List<WorkItem> entries) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outcomes = entries.where((item) => item.outcome.isNotEmpty).toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'Initiative report',
            subtitle: 'Evidence captured against this initiative',
            icon: Icons.description_outlined,
            trailing: Tooltip(
              message: 'Narrative generation is owned by SummaryService',
              child: OutlinedButton.icon(
                onPressed: outcomes.isEmpty
                    ? null
                    : () {
                        final text = outcomes
                            .map(
                              (item) =>
                                  '- ${formatDayHeader(item.startedLocal)}: ${item.outcome}',
                            )
                            .join('\n');
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Outcome evidence copied'),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy_all, size: 15),
                label: const Text('Copy evidence'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            initiative.targetOutcome.isEmpty
                ? 'No target outcome set.'
                : 'Target outcome: ${initiative.targetOutcome}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (outcomes.isEmpty)
            Text(
              'No outcome evidence recorded yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final item in outcomes.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 14,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 7),
                    SizedBox(
                      width: 92,
                      child: Text(
                        formatShortDate(item.startedLocal),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.outcome,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'The generated narrative and prompt bundle are produced by '
            'SummaryService; this view only shows captured evidence.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatefulWidget {
  const _ProgressCard({
    required this.initiative,
    required this.enabled,
    required this.onSave,
  });

  final Initiative initiative;
  final bool enabled;
  final ValueChanged<int> onSave;

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard> {
  late double _value = widget.initiative.progress.toDouble();

  @override
  void didUpdateWidget(covariant _ProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiative.progress != widget.initiative.progress) {
      _value = widget.initiative.progress.toDouble();
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
          Row(
            children: [
              Text('Progress', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                '${_value.round()}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            widget.initiative.targetOutcome.isEmpty
                ? 'Set a target outcome to make progress meaningful.'
                : widget.initiative.targetOutcome,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Slider(
            value: _value,
            max: 100,
            divisions: 20,
            onChanged: widget.enabled
                ? (value) => setState(() => _value = value)
                : null,
            onChangeEnd: widget.enabled
                ? (value) => widget.onSave(value.round())
                : null,
          ),
        ],
      ),
    );
  }
}
