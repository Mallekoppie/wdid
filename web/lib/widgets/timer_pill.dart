import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';

class TimerPill extends StatefulWidget {
  const TimerPill({super.key});

  @override
  State<TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends State<TimerPill> {
  bool _stopping = false;

  Future<void> _start() async {
    final state = AppStateScope.read(context);
    try {
      state.startTimer();
      if (!mounted) return;
      final initiative = state.activeTimer?.attribution.label ?? 'timer';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Timer started · $initiative')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _stop() async {
    final state = AppStateScope.read(context);
    setState(() => _stopping = true);
    try {
      final item = await state.stopTimer();
      if (!mounted) return;
      setState(() => _stopping = false);
      if (item != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${formatDuration(item.minutes)} · ${item.summary}',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _stopping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not stop the timer: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timer = state.activeTimer;

    if (timer == null) {
      return Tooltip(
        message: 'Start timer (T)',
        child: OutlinedButton.icon(
          onPressed: _start,
          icon: Icon(Icons.play_arrow, size: 17, color: scheme.primary),
          label: Text(
            'Start timer',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.primary,
            ),
          ),
        ),
      );
    }

    final elapsed = timer.elapsedAt(DateTime.now());
    final initiative = state.initiativeById(timer.attribution.initiativeId);
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: timer.isPaused ? 0.18 : 0.5),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: timer.isPaused
              ? scheme.outlineVariant
              : scheme.primary.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            timer.isPaused ? Icons.pause_circle_outline : Icons.timer_outlined,
            size: 16,
            color: timer.isPaused ? scheme.onSurfaceVariant : scheme.primary,
          ),
          const SizedBox(width: 7),
          InkWell(
            onTap: initiative == null
                ? null
                : () => context.go('/initiatives/${initiative.id}'),
            borderRadius: BorderRadius.circular(4),
            child: Text(
              timer.attribution.label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatClock(elapsed),
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: tabularFigures,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          if (timer.isPaused) ...[
            const SizedBox(width: 6),
            Text(
              'Paused',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          IconButton(
            tooltip: timer.isPaused ? 'Resume' : 'Pause',
            onPressed: timer.isPaused ? state.resumeTimer : state.pauseTimer,
            icon: Icon(
              timer.isPaused ? Icons.play_arrow : Icons.pause,
              size: 16,
            ),
          ),
          Tooltip(
            message: 'Stop & save',
            child: IconButton(
              onPressed: _stopping ? null : _stop,
              icon: _stopping
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.stop, size: 16, color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
