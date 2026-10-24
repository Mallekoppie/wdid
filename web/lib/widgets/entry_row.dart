import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/initiative.dart';
import '../models/work_item.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';

class EntryRow extends StatefulWidget {
  const EntryRow({
    super.key,
    required this.item,
    required this.initiatives,
    this.compact = false,
    this.onEdit,
    this.onDelete,
    this.onOpenInitiative,
    this.initiallyExpanded = false,
  });

  final WorkItem item;
  final List<Initiative> initiatives;
  final bool compact;
  final ValueChanged<WorkItem>? onEdit;
  final ValueChanged<WorkItem>? onDelete;
  final ValueChanged<WorkItem>? onOpenInitiative;
  final bool initiallyExpanded;

  @override
  State<EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<EntryRow> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final support = item.isSupport;
    final attribution = item.attributionLabel(widget.initiatives);
    final icon = support
        ? Icons.volunteer_activism_outlined
        : item.type.name == 'initiative'
        ? Icons.flag_outlined
        : Icons.category_outlined;
    final accent = support
        ? scheme.tertiary
        : item.type.name == 'initiative'
        ? scheme.primary
        : scheme.onSurfaceVariant;

    final rowHeight = widget.compact
        ? AppSizes.rowCompact
        : AppSizes.rowComfortable;

    return Container(
      decoration: BoxDecoration(
        color: support
            ? scheme.tertiaryContainer.withValues(alpha: 0.14)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 98,
                    child: Text(
                      formatTimeRange(item.startedLocal, item.endedLocal),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  Icon(icon, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: attribution,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.summary.isNotEmpty)
                            TextSpan(
                              text: '   ${item.summary}',
                              style: theme.textTheme.bodyMedium,
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.outcome.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: item.outcome,
                        child: Icon(
                          Icons.verified_outlined,
                          size: 13,
                          color: scheme.tertiary,
                        ),
                      ),
                    ),
                  if (item.links.isNotEmpty)
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
                      formatDuration(item.minutes),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Row actions',
                    icon: Icon(
                      Icons.more_vert,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    onSelected: (value) => _handleAction(context, value),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'copy', child: Text('Copy summary')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
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
    final item = widget.item;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerLow.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(112, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.outcome.isNotEmpty) ...[
            Text(
              'OUTCOME',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.tertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Text(item.outcome, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
          ],
          if (item.notes.isNotEmpty) ...[
            Text(
              'NOTES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Text(item.notes, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
          ],
          if (item.links.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final link in item.links)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link, size: 13, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        link.label,
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
          if (item.tags.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in item.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(tag, style: theme.textTheme.labelSmall),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (widget.onEdit != null)
                TextButton.icon(
                  onPressed: () => widget.onEdit!(item),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit'),
                ),
              if (item.initiativeId != null && widget.onOpenInitiative != null)
                TextButton.icon(
                  onPressed: () => widget.onOpenInitiative!(item),
                  icon: const Icon(Icons.arrow_outward, size: 15),
                  label: const Text('Open initiative'),
                ),
              const Spacer(),
              if (widget.onDelete != null)
                TextButton.icon(
                  onPressed: () => _confirmDelete(context),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 15,
                    color: scheme.error,
                  ),
                  label: Text('Delete', style: TextStyle(color: scheme.error)),
                ),
              Text(
                item.source == 'timer'
                    ? 'Timer · ${item.localDate}'
                    : item.localDate,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, String action) {
    switch (action) {
      case 'edit':
        widget.onEdit?.call(widget.item);
      case 'copy':
        final text = [
          if (widget.item.summary.isNotEmpty) widget.item.summary,
          if (widget.item.outcome.isNotEmpty) 'Outcome: ${widget.item.outcome}',
        ].join('\n');
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry copied to clipboard')),
        );
      case 'delete':
        _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (widget.onDelete == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          '“${widget.item.summary.isEmpty ? 'Untitled entry' : widget.item.summary}” '
          'will be removed from the journal.',
        ),
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
    if (confirmed == true) widget.onDelete!(widget.item);
  }
}
