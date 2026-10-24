import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';
import 'timer_actions.dart';

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
      await state.startTimer();
      if (!mounted) return;
      final timer = state.activeTimer;
      final label = timer == null ? 'timer' : state.timerLabel(timer);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Timer started · $label')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _togglePause(bool paused) async {
    final state = AppStateScope.read(context);
    try {
      if (paused) {
        await state.resumeTimer();
      } else {
        await state.pauseTimer();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change the timer: $error')),
      );
    }
  }

  Future<void> _stop() async {
    final state = AppStateScope.read(context);
    setState(() => _stopping = true);
    try {
      final result = await stopTimerWithDecision(context, state: state);
      if (!mounted) return;
      setState(() => _stopping = false);
      if (result != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(stoppedTimerMessage(result))));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _stopping = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
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
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
          ),
        ),
      );
    }

    final elapsed = timer.elapsedAt(DateTime.now());
    final projectId = state.timerInitiativeId(timer);
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primaryContainer.withValues(
            alpha: timer.isPaused ? 0.18 : 0.5,
          ),
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: InkWell(
              onTap: projectId == null
                  ? null
                  : () => context.go('/initiatives/$projectId'),
              borderRadius: BorderRadius.circular(4),
              child: Text(
                state.timerLabel(timer),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
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
            onPressed: () => unawaited(_togglePause(timer.isPaused)),
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
