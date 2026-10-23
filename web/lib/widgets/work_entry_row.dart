import 'package:flutter/material.dart';

import '../models/taxonomy.dart';
import '../models/work_entry.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';

/// A work entry row backed by `EntryService`. The attribution comes from the
/// loaded taxonomy, and the outcome can be filled in after capture.
class WorkEntryRow extends StatelessWidget {
  const WorkEntryRow({
    super.key,
    required this.entry,
    this.category,
    this.subcategory,
    required this.onEditOutcome,
  });

  final WorkEntry entry;
  final Category? category;
  final Subcategory? subcategory;
  final ValueChanged<WorkEntry> onEditOutcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final support = category?.role == CategoryRole.support;
    final accent = support ? scheme.tertiary : scheme.primary;

    final attribution = [
      category?.name ?? 'Unknown category',
      if (subcategory != null) subcategory!.name,
      if (entry.person.isNotEmpty) entry.person,
    ].join(' · ');

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
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                support
                    ? Icons.volunteer_activism_outlined
                    : category?.role == CategoryRole.initiative
                    ? Icons.flag_outlined
                    : Icons.category_outlined,
                size: 14,
                color: accent,
              ),
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
                      if (entry.description.isNotEmpty)
                        TextSpan(
                          text: '   ${entry.description}',
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entry.outcome.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.verified_outlined,
                    size: 13,
                    color: scheme.tertiary,
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
            ],
          ),
          const SizedBox(height: 2),
          if (entry.outcome.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 104),
              child: TextButton.icon(
                onPressed: () => onEditOutcome(entry),
                icon: const Icon(Icons.add_circle_outline, size: 14),
                label: const Text('Add outcome'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
              ),
            )
          else
            Row(
              children: [
                const SizedBox(width: 104),
                Icon(Icons.verified_outlined, size: 13, color: scheme.tertiary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    entry.outcome,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => onEditOutcome(entry),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Text('Edit outcome'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
