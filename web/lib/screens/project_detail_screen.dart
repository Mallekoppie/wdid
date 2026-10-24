import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/milestone.dart';
import '../models/note.dart';
import '../models/period_report.dart';
import '../models/taxonomy.dart';
import '../models/work_entry.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/entry_grouping.dart';
import '../utils/time_utils.dart';
import '../widgets/forms/milestone_dialog.dart';
import '../widgets/forms/note_dialog.dart';
import '../widgets/forms/project_entry_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/stat_tile.dart';
import '../widgets/status_badge.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _logTime(AppState state, Subcategory project) async {
    final saved = await showProjectEntryDialog(
      context,
      state: state,
      project: project,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry saved')));
    }
  }

  Future<void> _addNote(AppState state, Subcategory project) async {
    final saved = await showNoteDialog(
      context,
      state: state,
      initiativeId: project.id,
      title: 'Add note',
      subtitle: project.name,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note added')));
    }
  }

  Future<void> _editNote(AppState state, Subcategory project, Note note) async {
    final saved = await showNoteDialog(
      context,
      state: state,
      existing: note,
      initiativeId: note.initiativeId,
      title: 'Edit note',
      subtitle: project.name,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note updated')));
    }
  }

  Future<void> _deleteNote(AppState state, Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This removes the note from the project.'),
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
    if (confirmed != true) return;
    try {
      await state.deleteNote(note.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the note: $error')),
      );
    }
  }

  Future<void> _addMilestone(AppState state, Subcategory project) async {
    final saved = await showMilestoneDialog(
      context,
      state: state,
      projectId: project.id,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Milestone added')));
    }
  }

  Future<void> _editMilestone(
    AppState state,
    Subcategory project,
    Milestone milestone,
  ) async {
    final saved = await showMilestoneDialog(
      context,
      state: state,
      projectId: project.id,
      existing: milestone,
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Milestone updated')));
    }
  }

  Future<void> _toggleMilestone(AppState state, Milestone milestone) async {
    try {
      await state.setMilestoneDone(milestone, !milestone.done);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the milestone: $error')),
      );
    }
  }

  Future<void> _deleteMilestone(AppState state, Milestone milestone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete milestone?'),
        content: const Text('This removes the checkpoint from the project.'),
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
    if (confirmed != true) return;
    try {
      await state.deleteMilestone(milestone.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Milestone deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the milestone: $error')),
      );
    }
  }

  Future<void> _restore(AppState state, Subcategory project) async {
    try {
      await state.archiveSubcategory(project, archived: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project restored · ${project.name}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not restore the project: $error')),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.read(context);
    if (state.projectById(widget.projectId) == null) return;
    if (state.projectEntriesProjectId == widget.projectId) {
      _ensureProjectNotes(state);
      _ensureMilestones(state);
      return;
    }
    if (state.projectEntriesLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = AppStateScope.read(context);
      if (current.projectEntriesProjectId != widget.projectId) {
        unawaited(current.loadProjectEntries(widget.projectId));
      }
      _ensureProjectNotes(current);
      _ensureMilestones(current);
    });
  }

  /// Loads the project's notes once per visit. The demo adapter keeps its notes
  /// in the main list, so only the service-backed path fetches per project.
  void _ensureProjectNotes(AppState state) {
    if (state.noteApi == null) return;
    if (state.projectNotesProjectId == widget.projectId) return;
    if (state.projectNotesLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = AppStateScope.read(context);
      if (current.projectNotesProjectId != widget.projectId &&
          !current.projectNotesLoading) {
        unawaited(current.loadProjectNotes(widget.projectId));
      }
    });
  }

  /// Loads the project's milestones once per visit. Demo mode has no milestone
  /// store, so the tab stays read-only there.
  void _ensureMilestones(AppState state) {
    if (state.milestoneApi == null) return;
    if (state.projectMilestonesProjectId == widget.projectId) return;
    if (state.projectMilestonesLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = AppStateScope.read(context);
      if (current.projectMilestonesProjectId != widget.projectId &&
          !current.projectMilestonesLoading) {
        unawaited(current.loadProjectMilestones(widget.projectId));
      }
    });
  }

  void _ensureReport(AppState state) {
    if (state.initiativesReport != null) return;
    if (state.initiativesLoading || state.initiativesError != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = AppStateScope.read(context);
      if (current.initiativesReport == null &&
          !current.initiativesLoading &&
          current.initiativesError == null) {
        unawaited(current.loadInitiativesReport());
      }
    });
  }

  Widget _timeline(
    AppState state,
    Subcategory project, {
    required bool loading,
    required String? error,
    required List<WorkEntry> entries,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (loading) {
      return const Panel(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (error != null) {
      return Panel(
        tone: PanelTone.warning,
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 22, color: scheme.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(error, style: theme.textTheme.bodySmall)),
            OutlinedButton.icon(
              onPressed: () => unawaited(state.loadProjectEntries(project.id)),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (entries.isEmpty) {
      return Panel(
        child: EmptyState(
          icon: Icons.timeline,
          title: 'No time logged yet',
          message: project.archived
              ? 'No work entries were recorded against this project.'
              : 'Log a block against this project to start the timeline.',
        ),
      );
    }

    final grouped = groupEntriesByLocalDay(entries);
    final days = grouped.keys.toList();

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, day) in days.indexed) ...[
            if (index > 0) Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                4,
              ),
              child: Text(
                formatDayHeader(DateTime.tryParse(day) ?? DateTime.now()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            for (final entry in grouped[day]!) _ProjectEntryRow(entry: entry),
          ],
        ],
      ),
    );
  }

  /// True when the entry's local day falls inside the report's period, so the
  /// interaction list and the period totals describe the same work.
  bool _entryFallsIn(WorkEntry entry, PeriodReport report) {
    final day = entry.localDate.isNotEmpty
        ? entry.localDate
        : isoDate(entry.startedLocal);
    return day.compareTo(report.fromDate) >= 0 &&
        day.compareTo(report.toDate) <= 0;
  }

  Widget _report(
    AppState state,
    Subcategory project, {
    required List<WorkEntry> entries,
    required bool timelineLoading,
    required String? timelineError,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final report = state.initiativesReport;
    final allocation = state.allocationForProject(project.id);
    final milestoneProgress = state.milestoneProgressForProject(project.id);
    final loading = state.initiativesLoading && report == null;
    final error = state.initiativesError;
    final supportEntries = [
      for (final entry in entries)
        if (entry.person.isNotEmpty &&
            (report == null || _entryFallsIn(entry, report)))
          entry,
    ];

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'Project report',
            subtitle: report == null
                ? 'This quarter'
                : '${report.fromDate} – ${report.toDate}',
            icon: Icons.description_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 20,
                      color: scheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(error, style: theme.textTheme.bodySmall),
                    ),
                    OutlinedButton.icon(
                      onPressed: state.loadInitiativesReport,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                StatTile(
                  label: 'This quarter',
                  value: formatDuration(allocation?.minutes ?? 0),
                  icon: Icons.schedule,
                ),
                StatTile(
                  label: 'Entries',
                  value: '${allocation?.entryCount ?? 0}',
                  icon: Icons.list_alt,
                ),
                StatTile(
                  label: 'Milestones',
                  value: milestoneProgress == null
                      ? '0 of 0 complete'
                      : '${milestoneProgress.done} of '
                            '${milestoneProgress.total} complete',
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            PanelHeader(
              title: 'Support interactions',
              subtitle: timelineLoading
                  ? 'Loading this project’s entries…'
                  : timelineError != null
                  ? 'This project’s entries could not be loaded.'
                  : supportEntries.isEmpty
                  ? 'No people were named on this project’s entries in this period.'
                  : '${supportEntries.length} '
                        '${supportEntries.length == 1 ? 'interaction' : 'interactions'}',
              icon: Icons.volunteer_activism_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (timelineLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (timelineError != null)
              Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 18, color: scheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      timelineError,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        unawaited(state.loadProjectEntries(project.id)),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              )
            else if (supportEntries.isNotEmpty)
              for (final entry in supportEntries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(
                        label: entry.person,
                        color: scheme.tertiary,
                        icon: Icons.volunteer_activism_outlined,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.description.isEmpty
                                  ? 'Untitled entry'
                                  : entry.description,
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (entry.outcome.isNotEmpty)
                              Text(
                                entry.outcome,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 76,
                        child: Text(
                          formatShortDate(entry.startedLocal),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(
                        width: 52,
                        child: Text(
                          formatDuration(entry.minutes),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _notes(AppState state, Subcategory project) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notes = state.notesForProject(project.id);
    final loading =
        state.noteApi != null &&
        (state.projectNotesLoading ||
            state.projectNotesProjectId != project.id);
    final error = state.projectNotesProjectId == project.id
        ? state.projectNotesError
        : null;

    if (loading) {
      return const Panel(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (error != null) {
      return Panel(
        tone: PanelTone.warning,
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 22, color: scheme.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(error, style: theme.textTheme.bodySmall)),
            OutlinedButton.icon(
              onPressed: () => unawaited(state.loadProjectNotes(project.id)),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (notes.isEmpty) {
      return Panel(
        child: EmptyState(
          icon: Icons.notes_outlined,
          title: 'No notes yet',
          message: 'Capture decisions and context while they are fresh.',
          action: project.archived
              ? null
              : FilledButton.icon(
                  onPressed: () => unawaited(_addNote(state, project)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add note'),
                ),
        ),
      );
    }

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, note) in notes.indexed) ...[
            if (index > 0) Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: 32,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(note.text, style: theme.textTheme.bodyMedium),
                        if (note.date.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            note.date,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!project.archived) ...[
                    IconButton(
                      tooltip: 'Edit note',
                      onPressed: () =>
                          unawaited(_editNote(state, project, note)),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Delete note',
                      onPressed: () => unawaited(_deleteNote(state, note)),
                      icon: const Icon(Icons.delete_outline, size: 17),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _milestones(AppState state, Subcategory project) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final milestones = state.milestonesForProject(project.id);
    final hasService = state.milestoneApi != null;
    final loading =
        hasService &&
        (state.projectMilestonesLoading ||
            state.projectMilestonesProjectId != project.id);
    final error = state.projectMilestonesProjectId == project.id
        ? state.projectMilestonesError
        : null;

    if (loading) {
      return const Panel(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (error != null) {
      return Panel(
        tone: PanelTone.warning,
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 22, color: scheme.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(error, style: theme.textTheme.bodySmall)),
            OutlinedButton.icon(
              onPressed: () =>
                  unawaited(state.loadProjectMilestones(project.id)),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (!hasService) {
      return Panel(
        child: EmptyState(
          icon: Icons.flag_outlined,
          title: 'Milestones need the service',
          message: 'Connect the service to track dated checkpoints for this project.',
        ),
      );
    }
    if (milestones.isEmpty) {
      return Panel(
        child: EmptyState(
          icon: Icons.flag_outlined,
          title: 'No milestones yet',
          message: 'Add dated checkpoints to see this project take shape.',
          action: project.archived
              ? null
              : FilledButton.icon(
                  onPressed: () => unawaited(_addMilestone(state, project)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add milestone'),
                ),
        ),
      );
    }

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${milestones.length} '
                    '${milestones.length == 1 ? 'milestone' : 'milestones'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (!project.archived)
                  FilledButton.icon(
                    onPressed: () => unawaited(_addMilestone(state, project)),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add milestone'),
                  ),
              ],
            ),
          ),
          for (final (index, milestone) in milestones.indexed) ...[
            if (index > 0) Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                4,
                AppSpacing.sm,
                4,
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: milestone.done,
                    onChanged: project.archived
                        ? null
                        : (_) => unawaited(_toggleMilestone(state, milestone)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          milestone.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            decoration: milestone.done
                                ? TextDecoration.lineThrough
                                : null,
                            color: milestone.done
                                ? scheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                        if (milestone.dueDate.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Due ${_displayDueDate(milestone.dueDate)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!project.archived) ...[
                    IconButton(
                      tooltip: 'Edit milestone',
                      onPressed: () =>
                          unawaited(_editMilestone(state, project, milestone)),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Delete milestone',
                      onPressed: () =>
                          unawaited(_deleteMilestone(state, milestone)),
                      icon: const Icon(Icons.delete_outline, size: 17),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _displayDueDate(String dueDate) {
    final parsed = DateTime.tryParse(dueDate);
    return parsed == null ? dueDate : formatShortDate(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final project = state.projectById(widget.projectId);

    if (project == null) {
      return ScreenBody(
        child: PageScaffold(
          child: Panel(
            child: state.taxonomyLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : state.taxonomyError != null
                ? EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load the projects',
                    message: state.taxonomyError!,
                    action: OutlinedButton.icon(
                      onPressed: state.loadTaxonomy,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  )
                : EmptyState(
                    icon: Icons.flag_outlined,
                    title: 'Project not found',
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

    final category = state.categoryById(project.categoryId);
    final archived = project.archived;
    final timelineEntries = state.projectEntriesProjectId == project.id
        ? state.projectEntries
        : const <WorkEntry>[];
    final timelineLoading =
        state.projectEntriesLoading ||
        state.projectEntriesProjectId != project.id;
    final timelineError = state.projectEntriesProjectId == project.id
        ? state.projectEntriesError
        : null;
    _ensureReport(state);

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
                              project.name,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SubcategoryStatusBadge(status: project.status),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        category?.name ?? 'Unknown category',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!archived) ...[
                  const SizedBox(width: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_addNote(state, project)),
                    icon: const Icon(Icons.notes_outlined, size: 16),
                    label: const Text('Add note'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: () => unawaited(_logTime(state, project)),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Log time'),
                  ),
                ] else ...[
                  const SizedBox(width: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_restore(state, project)),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Restore'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.targetOutcome.isEmpty
                        ? 'No target outcome set.'
                        : project.targetOutcome,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Text(
                        '${project.progress}%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: project.progress / 100,
                            minHeight: 5,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (archived) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'This project is archived and read-only.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            TabBar(
              controller: _tabs,
              onTap: (_) => setState(() {}),
              tabs: const [
                Tab(text: 'Timeline'),
                Tab(text: 'Notes'),
                Tab(text: 'Milestones'),
                Tab(text: 'Report'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            switch (_tabs.index) {
              0 => _timeline(
                state,
                project,
                loading: timelineLoading,
                error: timelineError,
                entries: timelineEntries,
              ),
              1 => _notes(state, project),
              2 => _milestones(state, project),
              _ => _report(
                state,
                project,
                entries: timelineEntries,
                timelineLoading: timelineLoading,
                timelineError: timelineError,
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// One timeline entry: time, description, outcome and who was supported.
class _ProjectEntryRow extends StatelessWidget {
  const _ProjectEntryRow({required this.entry});

  final WorkEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  formatTimeRange(entry.startedLocal, entry.endedLocal),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  entry.description.isEmpty
                      ? 'Untitled entry'
                      : entry.description,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (entry.person.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                StatusBadge(
                  label: entry.person,
                  color: scheme.tertiary,
                  icon: Icons.volunteer_activism_outlined,
                ),
              ],
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 52,
                child: Text(
                  formatDuration(entry.minutes),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            ],
          ),
          if (entry.outcome.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 108, top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 13,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      entry.outcome,
                      style: theme.textTheme.bodySmall,
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
