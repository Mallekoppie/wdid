import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/period_report.dart';
import '../models/taxonomy.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';
import '../widgets/forms/project_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/status_badge.dart';

class InitiativesScreen extends StatelessWidget {
  const InitiativesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProjectsView();
  }
}

/// The live portfolio: every subcategory under an initiative-role category is
/// a project, and its time and last activity come from the period report.
class _ProjectsView extends StatefulWidget {
  const _ProjectsView();

  @override
  State<_ProjectsView> createState() => _ProjectsViewState();
}

class _ProjectsViewState extends State<_ProjectsView> {
  bool _requestedReport = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedReport) return;
    _requestedReport = true;
    // Loading notifies listeners, which is illegal during the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppStateScope.read(context);
      if (state.initiativesReport == null &&
          !state.initiativesLoading &&
          state.initiativesError == null) {
        unawaited(state.loadInitiativesReport());
      }
    });
  }

  Future<void> _create(BuildContext context) async {
    final state = AppStateScope.read(context);
    final saved = await showProjectDialog(context, state: state);
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project created · ${saved.name}')),
      );
    }
  }

  Future<void> _edit(BuildContext context, Subcategory project) async {
    final state = AppStateScope.read(context);
    final saved = await showProjectDialog(
      context,
      state: state,
      project: project,
    );
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project updated · ${saved.name}')),
      );
    }
  }

  Future<void> _setArchived(
    BuildContext context,
    Subcategory project, {
    required bool archived,
  }) async {
    final state = AppStateScope.read(context);
    try {
      await state.archiveSubcategory(project, archived: archived);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived
                ? 'Project archived · ${project.name}'
                : 'Project restored · ${project.name}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the project: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final open = state.openProjects;
    final archived = state.archivedProjects;
    final report = state.initiativesReport;
    final reportPending = state.initiativesLoading && report == null;

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
                      reportPending
                          ? 'Loading this quarter…'
                          : '${open.length} projects · '
                                '${formatDuration(state.initiativeMinutes)} '
                                'logged this quarter',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: state.selectableInitiativeCategories.isEmpty
                      ? null
                      : () => unawaited(_create(context)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New project'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.taxonomyLoading && state.categories.isEmpty)
              const Panel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (state.taxonomyError != null && state.categories.isEmpty)
              _InlineError(
                message: state.taxonomyError!,
                onRetry: state.loadTaxonomy,
              )
            else if (state.initiativeCategories.isEmpty)
              Panel(
                child: EmptyState(
                  icon: Icons.workspaces_outline,
                  title: 'No initiative category',
                  message:
                      'Add a category with the initiative reporting role in '
                      'Settings, then create projects here.',
                  action: FilledButton.icon(
                    onPressed: () => context.go('/settings'),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Open Settings'),
                  ),
                ),
              )
            else ...[
              if (state.initiativesError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _InlineError(
                    message: state.initiativesError!,
                    onRetry: state.loadInitiativesReport,
                  ),
                ),
              if (open.isEmpty && archived.isEmpty)
                Panel(
                  child: EmptyState(
                    icon: Icons.flag_outlined,
                    title: 'No projects yet',
                    message:
                        'Create the first project under an initiative category '
                        'so captured time has somewhere to land.',
                    action: FilledButton.icon(
                      onPressed: state.selectableInitiativeCategories.isEmpty
                          ? null
                          : () => unawaited(_create(context)),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New project'),
                    ),
                  ),
                )
              else ...[
                if (reportPending)
                  const Panel(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (open.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth > 1080
                          ? 3
                          : constraints.maxWidth > 700
                          ? 2
                          : 1;
                      final width =
                          (constraints.maxWidth -
                              (columns - 1) * AppSpacing.lg) /
                          columns;
                      return Wrap(
                        spacing: AppSpacing.lg,
                        runSpacing: AppSpacing.lg,
                        children: [
                          for (final project in open)
                            SizedBox(
                              width: width,
                              child: _ProjectCard(
                                project: project,
                                onEdit: () =>
                                    unawaited(_edit(context, project)),
                                onArchive: () => unawaited(
                                  _setArchived(
                                    context,
                                    project,
                                    archived: true,
                                  ),
                                ),
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
                        for (final project in archived)
                          _ArchivedProjectRow(
                            project: project,
                            onOpen: () =>
                                context.go('/initiatives/${project.id}'),
                            onRestore: () => unawaited(
                              _setArchived(context, project, archived: false),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onEdit,
    required this.onArchive,
  });

  final Subcategory project;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = AppStateScope.of(context);
    final category = state.categoryById(project.categoryId);
    final allocation = state.allocationForProject(project.id);
    final minutes = allocation?.minutes ?? 0;
    final lastActivity = _lastActivityLabel(allocation);

    return Panel(
      onTap: () => context.go('/initiatives/${project.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: theme.textTheme.titleMedium),
                    if (category != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        category.name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SubcategoryStatusBadge(status: project.status),
              PopupMenuButton<String>(
                tooltip: 'Project actions',
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'archive') onArchive();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            project.targetOutcome.isEmpty
                ? project.description.isEmpty
                      ? 'No target outcome set.'
                      : project.description
                : project.targetOutcome,
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
                formatDuration(minutes),
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
                '${project.progress}%',
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
              value: project.progress / 100,
              minHeight: 5,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.history, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  lastActivity,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (project.links.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 4,
              children: [
                for (final link in project.links)
                  StatusBadge(
                    label: link.label.isEmpty ? link.url : link.label,
                    color: scheme.primary,
                    icon: Icons.link,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _lastActivityLabel(SubcategoryAllocation? allocation) {
    if (allocation == null || allocation.lastActivityDate.isEmpty) {
      return 'No activity this quarter';
    }
    final date = DateTime.tryParse(allocation.lastActivityDate);
    final when = date == null
        ? allocation.lastActivityDate
        : formatRelativeDay(date);
    final description = allocation.lastActivityDescription.trim();
    return description.isEmpty
        ? 'Last activity $when'
        : 'Last: $description · $when';
  }
}

class _ArchivedProjectRow extends StatelessWidget {
  const _ArchivedProjectRow({
    required this.project,
    required this.onOpen,
    required this.onRestore,
  });

  final Subcategory project;
  final VoidCallback onOpen;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = AppStateScope.of(context);
    final category = state.categoryById(project.categoryId);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 8,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.name, style: theme.textTheme.bodyMedium),
                  if (category != null)
                    Text(
                      category.name,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            StatusBadge(label: 'Archived', color: scheme.outline),
            const SizedBox(width: AppSpacing.md),
            TextButton(onPressed: onRestore, child: const Text('Restore')),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      tone: PanelTone.warning,
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 22,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
