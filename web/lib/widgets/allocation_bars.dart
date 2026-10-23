import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../utils/analytics.dart';
import '../utils/time_utils.dart';

class AllocationBars extends StatelessWidget {
  const AllocationBars({
    super.key,
    required this.slices,
    this.emptyLabel = 'No time logged in this period.',
    this.maxRows,
    this.showShare = true,
  });

  final List<AllocationSlice> slices;
  final String emptyLabel;
  final int? maxRows;
  final bool showShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (slices.isEmpty) {
      return Text(
        emptyLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final total = slices.fold(0, (sum, slice) => sum + slice.minutes);
    final visible = maxRows == null ? slices : slices.take(maxRows!);
    final palette = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.primary.withValues(alpha: 0.62),
      scheme.tertiary.withValues(alpha: 0.62),
      scheme.secondary.withValues(alpha: 0.62),
      scheme.outline,
    ];

    return Column(
      children: [
        for (final (index, slice) in visible.indexed) ...[
          if (index > 0) const SizedBox(height: 7),
          Builder(
            builder: (context) {
              final row = Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: palette[index % palette.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 132,
                    child: Text(
                      slice.label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 6,
                        child: ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: slice.shareOf(total).clamp(0.01, 1.0),
                            child: ColoredBox(
                              color: palette[index % palette.length],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (showShare)
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${(slice.shareOf(total) * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 54,
                    child: Text(
                      formatDuration(slice.minutes),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                ],
              );
              return slice.tooltip == null
                  ? row
                  : Tooltip(message: slice.tooltip!, child: row);
            },
          ),
        ],
      ],
    );
  }
}
