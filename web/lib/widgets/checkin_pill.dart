import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';

class CheckInPill extends StatelessWidget {
  const CheckInPill({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latest = state.latestCheckIn;
    final days = state.daysSinceCheckIn;
    final overdue = latest == null || days >= 14;

    final label = latest == null
        ? 'No check-ins yet'
        : days == 0
        ? 'Check-in due'
        : '$days days since check-in';

    return Tooltip(
      message: latest == null
          ? 'Open check-ins'
          : 'Last check-in ended ${latest.periodEnd.year}-'
                '${latest.periodEnd.month.toString().padLeft(2, '0')}-'
                '${latest.periodEnd.day.toString().padLeft(2, '0')}',
      child: InkWell(
        onTap: () => context.go('/checkins'),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: overdue
                ? Color.alphaBlend(
                    scheme.tertiaryContainer.withValues(alpha: 0.55),
                    scheme.surface,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: overdue
                  ? scheme.tertiary.withValues(alpha: 0.45)
                  : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_note_outlined,
                size: 14,
                color: overdue ? scheme.tertiary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: overdue ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
