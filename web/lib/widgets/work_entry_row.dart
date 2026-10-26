import 'package:flutter/material.dart';

import '../models/taxonomy.dart';
import '../models/work_entry.dart';
import '../theme/app_theme.dart';
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
    this.supportModes = const [],
    this.onSetMode,
  });

  final WorkEntry entry;
  final Category? category;
  final Subcategory? subcategory;
  final ValueChanged<WorkEntry> onEditOutcome;

  /// The support modes offered on a support row. Both this and [onSetMode]
  /// must be supplied for the selector to render.
  final List<Subcategory> supportModes;

  /// Selects a support mode, or clears it when null.
  final ValueChanged<Subcategory?>? onSetMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final support = category?.role == CategoryRole.support;
    final showModeSelector =
        support && onSetMode != null && supportModes.isNotEmpty;
    final accent = support ? scheme.tertiary : scheme.primary;
    final verticalPadding = AppTheme.isCompact(context) ? 6.0 : 10.0;

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
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        verticalPadding,
        12,
        verticalPadding,
      ),
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
          if (showModeSelector)
            Padding(
              padding: EdgeInsets.only(
                left: MediaQuery.sizeOf(context).width < 700
                    ? AppSpacing.sm
                    : 104,
                top: 6,
                bottom: 2,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _SupportModeControl(
                      current: subcategory,
                      modes: supportModes,
                      onChanged: onSetMode!,
                    ),
                    if (subcategory != null)
                      TextButton(
                        onPressed: () => onSetMode!(null),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
            ),
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

const _clearModeValue = '__clear_mode__';

/// The always-visible support-mode selector on a Today row. It shows the
/// current mode, changes it from a menu, and clears it when [onChanged] gets
/// null.
class _SupportModeControl extends StatelessWidget {
  const _SupportModeControl({
    required this.current,
    required this.modes,
    required this.onChanged,
  });

  final Subcategory? current;
  final List<Subcategory> modes;
  final ValueChanged<Subcategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasMode = current != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: PopupMenuButton<String>(
        tooltip: 'Change support mode',
        onSelected: (value) {
          if (value == _clearModeValue) {
            onChanged(null);
            return;
          }
          for (final mode in modes) {
            if (mode.id == value) {
              onChanged(mode);
              return;
            }
          }
        },
        itemBuilder: (context) => [
          for (final mode in modes)
            PopupMenuItem<String>(
              value: mode.id,
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: current?.id == mode.id
                        ? const Icon(Icons.check, size: 16)
                        : null,
                  ),
                  Flexible(child: Text(mode.name)),
                ],
              ),
            ),
          const PopupMenuItem<String>(
            value: _clearModeValue,
            child: Text('Clear mode'),
          ),
        ],
        child: SizedBox(
          height: 48,
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: hasMode
                    ? scheme.surface
                    : scheme.tertiaryContainer.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(
                  color: hasMode
                      ? scheme.outlineVariant
                      : scheme.tertiary.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mode',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      current?.name ?? 'Not set',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: hasMode ? scheme.onSurface : scheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
