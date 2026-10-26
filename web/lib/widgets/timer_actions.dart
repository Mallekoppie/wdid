import 'package:flutter/material.dart';

import '../data/timer_api.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../utils/time_utils.dart';

/// Stops the timer, asking the user what to do when the server needs a
/// decision (under a minute, or past the block limit). Returns null when the
/// user cancels or no timer was running.
Future<StoppedTimer?> stopTimerWithDecision(
  BuildContext context, {
  AppState? state,
}) async {
  final appState = state ?? AppStateScope.read(context);

  try {
    return await appState.stopTimer();
  } on TimerConflict catch (conflict) {
    if (!context.mounted) return null;
    final action = await showDialog<TimerStopAction>(
      context: context,
      builder: (context) => _TimerConflictDialog(
        conflict: conflict,
        elapsed:
            appState.activeTimer?.elapsedAt(DateTime.now()) ?? Duration.zero,
        blockLimitMinutes: appState.blockLimitMinutes,
        label: appState.activeTimer == null
            ? 'this timer'
            : appState.timerLabel(appState.activeTimer!),
      ),
    );
    if (action == null) return null;
    return appState.stopTimer(action: action);
  } catch (error) {
    if (!context.mounted) rethrow;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not stop the timer: $error')));
    return null;
  }
}

/// The message shown after a stop.
String stoppedTimerMessage(StoppedTimer? result) {
  if (result == null) return 'Timer';
  if (result.discarded) return 'Timer discarded';
  return 'Saved ${formatDuration(result.minutes)} · ${result.summary}';
}

/// Stops the running timer for the interrupt flow. The attribution is captured
/// before stopping because [StoppedTimer] does not carry it; the normal stop
/// decisions still decide whether the block is saved, trimmed or discarded.
///
/// Returns false when the user cancelled the decision or the stop failed, in
/// which case nothing should start. A discarded stop still lets the interrupt
/// continue (the timer is gone), but it stashes no Resume target: there is no
/// saved block to return to.
Future<bool> stopForInterrupt(
  BuildContext context, {
  required AppState state,
}) async {
  final timer = state.activeTimer;
  if (timer == null) return false;

  final result = await stopTimerWithDecision(context, state: state);
  if (result == null) return false;
  if (result.discarded) return true;
  state.setInterruptedTimer(
    InterruptedTimer(
      categoryId: timer.categoryId,
      subcategoryId: timer.subcategoryId,
      description: timer.description,
      people: timer.people,
      minutes: result.minutes,
    ),
  );
  return true;
}

/// Shows the brief toast after an ordinary stop.
///
/// It never offers Resume: the interrupt stash belongs to the Resume card, so
/// a stash left by an earlier interrupt cannot attach an action here.
void showStoppedTimerToast(BuildContext context, StoppedTimer? result) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(stoppedTimerMessage(result)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

class _TimerConflictDialog extends StatelessWidget {
  const _TimerConflictDialog({
    required this.conflict,
    required this.elapsed,
    required this.blockLimitMinutes,
    required this.label,
  });

  final TimerConflict conflict;
  final Duration elapsed;
  final int blockLimitMinutes;
  final String label;

  @override
  Widget build(BuildContext context) {
    final limit = Duration(minutes: blockLimitMinutes);
    if (conflict.reason == TimerConflictReason.tooShort) {
      return AlertDialog(
        title: const Text('Less than a minute'),
        content: Text(
          'The timer for $label has run for ${formatClock(elapsed)}. '
          'Discard it, or keep working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(TimerStopAction.discard),
            child: const Text('Discard'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text('Still working on $label?'),
      content: Text(
        'The timer has run for ${formatDuration(elapsed.inMinutes)}, past '
        'your ${formatDuration(blockLimitMinutes)} block limit. Keep the '
        'full time, trim it to the limit, or discard it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(TimerStopAction.discard),
          child: const Text('Discard'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(TimerStopAction.trim),
          child: Text('Trim to ${formatDuration(limit.inMinutes)}'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(TimerStopAction.keep),
          child: const Text('Keep'),
        ),
      ],
    );
  }
}
