import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';

/// The in-memory Resume offer left by an interrupt, pinned to the bottom-right
/// and sized to its content.
///
/// It belongs to the interrupt stash, not to a stop: an ordinary stop never
/// opens or replaces it. Resume starts a fresh timer from the stash; Done
/// forgets the stash without starting anything.
class InterruptResumeCard extends StatelessWidget {
  const InterruptResumeCard({super.key});

  Future<void> _resume(BuildContext context, AppState state) async {
    try {
      await state.resumeInterruptedTimer();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not resume: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final stash = state.interruptedTimer;
    if (stash == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surface,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.replay, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saved ${formatDuration(stash.minutes)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      state.interruptedTimerLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: () => unawaited(_resume(context, state)),
                child: const Text('Resume'),
              ),
              IconButton(
                tooltip: 'Done',
                onPressed: state.clearInterruptedTimer,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
