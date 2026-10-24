import 'package:flutter/material.dart';

import '../models/period_report.dart';
import '../state/app_state.dart';
import '../theme/app_tokens.dart';
import '../utils/analytics.dart';
import '../utils/time_utils.dart';
import 'allocation_bars.dart';
import 'panel.dart';
import 'screen_states.dart';

/// The four authoritative aggregates a check-in details: time by category,
/// time by project, support by person, and weekly rhythm. Every number comes
/// from the period report; none is composed from entries. A live, unsaved
/// review renders the exact same widget, so its aggregates match a saved
/// check-in for the same period.
class CheckInAggregates extends StatelessWidget {
  const CheckInAggregates({super.key, required this.state, required this.report});

  final AppState state;
  final PeriodReport? report;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    if (report == null) {
      return Panel(
        child: EmptyState(
          icon: Icons.insights_outlined,
          title: 'Aggregates need the period report',
          message: state.summaryApi == null
              ? 'Categories, projects, support and weekly rhythm come from the '
                    'service-owned period report.'
              : 'The report is still loading for this period.',
          compact: true,
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final projects = [
      for (final subcategory in report.subcategories)
        if (state.projectById(subcategory.subcategoryId) != null) subcategory,
    ];
    final maxProjectMinutes = projects.fold<int>(
      0,
      (max, project) => project.minutes > max ? project.minutes : max,
    );
    final maxWeekMinutes = report.weeks.fold<int>(
      0,
      (max, week) => week.minutes > max ? week.minutes : max,
    );

    final categories = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'Time by category',
            subtitle: formatDuration(report.totalMinutes),
            icon: Icons.pie_chart_outline,
          ),
          const SizedBox(height: AppSpacing.lg),
          AllocationBars(slices: allocationForReport(report)),
        ],
      ),
    );

    final byProject = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'Time by project',
            subtitle: projects.isEmpty
                ? 'No project time'
                : '${projects.length} ${projects.length == 1 ? 'project' : 'projects'}',
            icon: Icons.flag_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          if (projects.isEmpty)
            Text(
              'No initiative project received time in this period.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final project in projects)
              _ReportRow(
                label: project.name,
                detail:
                    '${formatDuration(project.minutes)} · '
                    '${project.entryCount} ${project.entryCount == 1 ? 'entry' : 'entries'}',
                share: maxProjectMinutes == 0
                    ? 0
                    : project.minutes / maxProjectMinutes,
              ),
        ],
      ),
    );

    final support = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'Support by person',
            subtitle: report.supportPeople.isEmpty
                ? 'No support logged'
                : '${report.supportPeople.length} '
                      '${report.supportPeople.length == 1 ? 'person' : 'people'}',
            icon: Icons.volunteer_activism_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          if (report.supportPeople.isEmpty)
            Text(
              'No support logged in this period.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final person in report.supportPeople)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: scheme.tertiaryContainer,
                      child: Text(
                        person.person.characters.first.toUpperCase(),
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
                          Text(
                            person.person,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${formatDuration(person.minutes)} · '
                            '${person.interactions} '
                            '${person.interactions == 1 ? 'interaction' : 'interactions'}',
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
              ),
        ],
      ),
    );

    final weeks = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'Weekly rhythm',
            subtitle: report.weeks.isEmpty
                ? 'No weeks'
                : '${report.weeks.length} '
                      '${report.weeks.length == 1 ? 'week' : 'weeks'}',
            icon: Icons.calendar_view_week_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          if (report.weeks.isEmpty)
            Text(
              'No weeks in this period.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final week in report.weeks)
              _ReportRow(
                label:
                    'Week of ${formatShortDate(DateTime.parse(week.weekStartDate))}',
                detail: week.topCategoryName.isEmpty
                    ? formatDuration(week.minutes)
                    : '${formatDuration(week.minutes)} · ${week.topCategoryName}',
                share: maxWeekMinutes == 0 ? 0 : week.minutes / maxWeekMinutes,
              ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              categories,
              const SizedBox(height: AppSpacing.lg),
              byProject,
              const SizedBox(height: AppSpacing.lg),
              support,
              const SizedBox(height: AppSpacing.lg),
              weeks,
            ],
          );
        }
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: categories),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: byProject),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: support),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: weeks),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.label,
    required this.detail,
    required this.share,
  });

  final String label;
  final String detail;
  final double share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                detail,
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
              value: share.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
