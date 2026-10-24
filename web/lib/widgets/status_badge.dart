import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/taxonomy.dart';
import '../theme/app_tokens.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class InitiativeStatusBadge extends StatelessWidget {
  const InitiativeStatusBadge({super.key, required this.status});

  final InitiativeStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      InitiativeStatus.planned => scheme.onSurfaceVariant,
      InitiativeStatus.active => scheme.primary,
      InitiativeStatus.blocked => scheme.error,
      InitiativeStatus.done => scheme.tertiary,
      InitiativeStatus.archived => scheme.outline,
    };
    return StatusBadge(label: status.label, color: color);
  }
}

class SubcategoryStatusBadge extends StatelessWidget {
  const SubcategoryStatusBadge({super.key, required this.status});

  final SubcategoryStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      SubcategoryStatus.planned => scheme.onSurfaceVariant,
      SubcategoryStatus.active => scheme.primary,
      SubcategoryStatus.blocked => scheme.error,
      SubcategoryStatus.done => scheme.tertiary,
      SubcategoryStatus.archived => scheme.outline,
    };
    return StatusBadge(label: status.label, color: color);
  }
}

class CheckInStateBadge extends StatelessWidget {
  const CheckInStateBadge({super.key, required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      CheckInState.draft => scheme.onSurfaceVariant,
      CheckInState.generated => scheme.primary,
      CheckInState.edited => scheme.secondary,
      CheckInState.final_ => scheme.tertiary,
    };
    return StatusBadge(label: state.label, color: color);
  }
}

/// Distinguishes a manager check-in from a personal review in a listing.
class CheckInKindBadge extends StatelessWidget {
  const CheckInKindBadge({super.key, required this.kind});

  final CheckInKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StatusBadge(
      label: kind.label,
      color: kind == CheckInKind.manager ? scheme.primary : scheme.secondary,
      icon: kind == CheckInKind.manager
          ? Icons.supervisor_account_outlined
          : Icons.person_outline,
    );
  }
}

/// The audience of a manager check-in. It is omitted for personal reviews.
class CheckInAudienceBadge extends StatelessWidget {
  const CheckInAudienceBadge({super.key, required this.audience});

  final CheckInAudience audience;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StatusBadge(
      label: audience.label,
      color: scheme.onSurfaceVariant,
      icon: audience == CheckInAudience.oneOnOne
          ? Icons.forum_outlined
          : Icons.workspace_premium_outlined,
    );
  }
}
