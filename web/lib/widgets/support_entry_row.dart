import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/work_entry.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../utils/people.dart';
import '../utils/time_utils.dart';

/// One support entry in the Support feed.
///
/// Support rows are deliberately distinct from initiative work: a tertiary
/// tint, the volunteer icon and a `Support · person · mode` attribution keep
/// them recognisable at a glance.
class SupportEntryRow extends StatefulWidget {
  const SupportEntryRow({
    super.key,
    required this.entry,
    required this.modeLabel,
    this.onEdit,
    this.onDelete,
    this.initiallyExpanded = false,
  });

  final WorkEntry entry;
  final String modeLabel;
  final ValueChanged<WorkEntry>? onEdit;
  final ValueChanged<WorkEntry>? onDelete;
  final bool initiallyExpanded;

  @override
  State<SupportEntryRow> createState() => _SupportEntryRowState();
}

class _SupportEntryRowState extends State<SupportEntryRow> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = widget.entry;
    final person = entry.people.isEmpty ? 'Someone' : peopleLabel(entry.people);
    final attribution = ['Support', person, widget.modeLabel].join(' · ');
    final verticalPadding = AppTheme.isCompact(context) ? 5.0 : 9.0;

    return Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.14),
        border: Border(
          left: BorderSide(color: scheme.tertiary, width: 3),
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: verticalPadding),
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 98,
                    child: Text(
                      formatTimeRange(entry.startedLocal, entry.endedLocal),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.volunteer_activism_outlined,
                    size: 14,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.team.isEmpty
                              ? attribution
                              : '$attribution · ${entry.team}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (entry.description.isNotEmpty)
                          Text(
                            entry.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  if (entry.outcome.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: entry.outcome,
                        child: Icon(
                          Icons.verified_outlined,
                          size: 13,
                          color: scheme.tertiary,
                        ),
                      ),
                    ),
                  if (entry.links.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.link,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
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
                  if (widget.onEdit != null || widget.onDelete != null)
                    PopupMenuButton<String>(
                      tooltip: 'Support row actions',
                      icon: Icon(
                        Icons.more_vert,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      onSelected: (value) {
                        if (value == 'edit') widget.onEdit?.call(entry);
                        if (value == 'delete') widget.onDelete?.call(entry);
                      },
                      itemBuilder: (context) => [
                        if (widget.onEdit != null)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                        if (widget.onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                      ],
                    )
                  else
                    const SizedBox(width: AppSpacing.sm),
                ],
              ),
            ),
          ),
          if (_expanded) _buildDetails(context),
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = widget.entry;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerLow.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(112, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.outcome.isNotEmpty) ...[
            Text(
              'OUTCOME',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.tertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Text(entry.outcome, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
          ],
          if (entry.links.isNotEmpty) ...[
            Text(
              'LINKS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final link in entry.links)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link, size: 13, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        link.label.isEmpty ? link.url : link.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            '${entry.source == EntrySource.timer ? 'Timer' : 'Manual'} · '
            '${entry.localDate}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
