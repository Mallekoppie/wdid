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

  /// True when the picker was opened after an interrupt actually stopped a
  /// timer, so its support start must keep the Resume stash.
  bool _preserveInterruptOnStart = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
      _preserveInterruptOnStart = false;
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
        ScaffoldMessenger.of(context)
            .showSnackBar(stoppedTimerSnackBar(context, state, result));
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
    // The stop happened, so the support start keeps the Resume stash.
    _preserveInterruptOnStart = true;
    _openPicker(category);
  }

  Future<void> _startSupport(String name, Category category) async {
    final person = name.trim();
    if (person.isEmpty) return;
    final preserveInterruptedTimer = _preserveInterruptOnStart;
    _preserveInterruptOnStart = false;
    final state = AppStateScope.read(context);
    try {
      await state.startSupportTimer(
        person: person,
        category: category,
        preserveInterruptedTimer: preserveInterruptedTimer,
      );
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
        : _runningControls(context, state, timer);
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
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        icon: Icon(Icons.play_arrow, size: 18, color: scheme.primary),
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

  Widget _runningControls(
    BuildContext context,
    AppState state,
    ActiveTimer timer,
  ) {
    final labels = MediaQuery.sizeOf(context).width >= 900;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _timerSummary(context, state, timer),
        const SizedBox(width: 14),
        _segmentedActions(context, timer, labels: labels),
      ],
    );
  }

  Widget _timerSummary(
    BuildContext context,
    AppState state,
    ActiveTimer timer,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final elapsed = timer.elapsedAt(DateTime.now());
    final projectId = state.timerInitiativeId(timer);
    final width = MediaQuery.sizeOf(context).width;
    final labelMaxWidth = width < 600 ? 120.0 : 200.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          timer.isPaused ? Icons.pause_circle_outline : Icons.timer_outlined,
          size: 20,
          color: timer.isPaused ? scheme.onSurfaceVariant : scheme.primary,
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: labelMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatClock(elapsed),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFeatures: tabularFigures,
                      color: timer.isPaused
                          ? scheme.onSurfaceVariant
                          : scheme.primary,
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
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _segmentedActions(
    BuildContext context,
    ActiveTimer timer, {
    required bool labels,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = _stopping || _interrupting;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            context,
            icon: Icons.swap_horiz,
            label: 'Interrupt',
            tooltip: 'Interrupt the running timer and start support',
            color: scheme.tertiary,
            labels: labels,
            spinner: _interrupting,
            onTap: disabled ? null : () => unawaited(_interrupt()),
          ),
          _segmentDivider(scheme.outlineVariant),
          _segment(
            context,
            icon: timer.isPaused ? Icons.play_arrow : Icons.pause,
            label: timer.isPaused ? 'Resume' : 'Pause',
            tooltip: timer.isPaused ? 'Resume' : 'Pause',
            color: scheme.onPrimary,
            background: scheme.primary,
            labels: labels,
            onTap: disabled
                ? null
                : () => unawaited(_togglePause(timer.isPaused)),
          ),
          _segmentDivider(scheme.outlineVariant),
          _segment(
            context,
            icon: Icons.stop,
            label: 'Stop',
            tooltip: 'Stop & save',
            color: scheme.error,
            labels: labels,
            spinner: _stopping,
            onTap: disabled ? null : () => unawaited(_stop()),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tooltip,
    required Color color,
    required bool labels,
    Color? background,
    bool spinner = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final iconWidget = spinner
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        : Icon(icon, size: 18, color: color);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: background ?? Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            width: labels ? null : 48,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: labels ? 14 : 0),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconWidget,
                    if (labels) ...[
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: color,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _segmentDivider(Color color) {
    return Container(width: 1, height: 24, color: color);
  }
}
