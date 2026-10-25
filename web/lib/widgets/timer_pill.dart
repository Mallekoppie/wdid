import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/taxonomy.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';
import 'person_picker.dart';
import 'timer_actions.dart';

class TimerPill extends StatefulWidget {
  const TimerPill({super.key});

  @override
  State<TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends State<TimerPill> {
  final MenuController _menu = MenuController();

  bool _stopping = false;
  bool _interrupting = false;

  /// The support category a picker was opened for. Null while the menu is
  /// closed; the menu children are only meaningful when this is set.
  Category? _pickingCategory;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openPicker(Category category) {
    setState(() => _pickingCategory = category);
    _menu.open();
  }

  void _handleMenuClosed() {
    if (!mounted) return;
    if (_pickingCategory == null) return;
    setState(() => _pickingCategory = null);
  }

  Future<void> _start() async {
    final state = AppStateScope.read(context);
    final remembered = state.lastCategoryId;
    if (remembered != null && state.isSupportCategory(remembered)) {
      final category = state.defaultSupportCategory;
      if (category == null) {
        _showMessage('Add a support category before starting support.');
        return;
      }
      // A support start needs a person. Open the same one-tap picker here
      // instead of letting startTimer throw "Who are you supporting?".
      _openPicker(category);
      return;
    }

    try {
      await state.startTimer();
      if (!mounted) return;
      final timer = state.activeTimer;
      final label = timer == null ? 'timer' : state.timerLabel(timer);
      _showMessage('Timer started · $label');
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
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
      _showMessage('Could not change the timer: $error');
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
        ScaffoldMessenger.of(context).showSnackBar(
          stoppedTimerSnackBar(context, state, result),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _stopping = false);
      _showMessage(error.toString());
    }
  }

  /// Stops and saves the running timer through the normal decisions, stashes
  /// its attribution, then opens the one-tap person picker in the header.
  Future<void> _interrupt() async {
    final state = AppStateScope.read(context);
    if (state.activeTimer == null) return;

    final category = state.defaultSupportCategory;
    if (category == null) {
      _showMessage('Add a support category before interrupting.');
      return;
    }

    setState(() => _interrupting = true);
    final proceed = await stopForInterrupt(context, state: state);
    if (!mounted) return;
    setState(() => _interrupting = false);
    if (!proceed) return;
    _openPicker(category);
  }

  Future<void> _startSupport(String name, Category category) async {
    final person = name.trim();
    if (person.isEmpty) return;
    final state = AppStateScope.read(context);
    try {
      await state.startSupportTimer(person: person, category: category);
      if (!mounted) return;
      final timer = state.activeTimer;
      _showMessage(
        'Support timer started · ${timer == null ? person : state.timerLabel(timer)}',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not start support: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final timer = state.activeTimer;
    final body = timer == null
        ? _startButton(context)
        : _runningPill(context, state, timer);
    final picking = _pickingCategory;

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      onClose: _handleMenuClosed,
      menuChildren: picking == null
          ? const <Widget>[]
          : [_personMenu(context, picking)],
      builder: (context, controller, child) => body,
    );
  }

  Widget _startButton(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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

  Widget _personMenu(BuildContext context, Category category) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 288,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Start a support timer', style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'One tap starts a support timer with no mode.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PersonPicker(
              autofocus: true,
              compact: true,
              hint: 'Name',
              onSelected: (name) {
                _menu.close();
                unawaited(_startSupport(name, category));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _interruptButton(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = _interrupting
        ? const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.swap_horiz, size: 15);
    final enabled = !_interrupting && !_stopping;

    // The running pill is already wide. Fall back to an icon-only affordance
    // on narrow viewports so the header stays usable.
    if (MediaQuery.sizeOf(context).width < 900) {
      return IconButton(
        tooltip: 'Interrupt',
        onPressed: enabled ? _interrupt : null,
        icon: icon,
        visualDensity: VisualDensity.compact,
      );
    }

    return Tooltip(
      message: 'Interrupt the running timer and start support',
      child: TextButton.icon(
        onPressed: enabled ? _interrupt : null,
        style: TextButton.styleFrom(
          foregroundColor: scheme.tertiary,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: icon,
        label: Text('Interrupt', style: theme.textTheme.labelMedium),
      ),
    );
  }

  Widget _runningPill(
    BuildContext context,
    AppState state,
    ActiveTimer timer,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
            // Leave room for the Interrupt affordance at narrow widths.
            constraints: const BoxConstraints(maxWidth: 180),
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
          const SizedBox(width: 4),
          _interruptButton(context),
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
