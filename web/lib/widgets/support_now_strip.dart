import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import 'panel.dart';
import 'person_picker.dart';
import 'timer_actions.dart';

/// Today's one-tap support start. Tapping a roster name starts an ordinary
/// support timer (no mode, no description). While another timer is running it
/// first stops and saves it through the same decisions as the header interrupt,
/// leaving a Resume stash behind.
class SupportNowStrip extends StatefulWidget {
  const SupportNowStrip({super.key});

  @override
  State<SupportNowStrip> createState() => _SupportNowStripState();
}

class _SupportNowStripState extends State<SupportNowStrip> {
  final TextEditingController _person = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _person.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startWith(String raw) async {
    final person = raw.trim();
    if (person.isEmpty) return;
    final state = AppStateScope.read(context);
    final category = state.defaultSupportCategory;
    if (category == null) {
      _show('Add a support category before starting support.');
      return;
    }

    setState(() => _busy = true);
    var preserveInterruptedTimer = false;
    try {
      if (state.activeTimer != null) {
        final proceed = await stopForInterrupt(context, state: state);
        if (!mounted) return;
        if (!proceed) {
          setState(() => _busy = false);
          return;
        }
        // Only an interrupt that actually stopped a timer has a stash to keep.
        preserveInterruptedTimer = true;
      }
      await state.startSupportTimer(
        person: person,
        category: category,
        preserveInterruptedTimer: preserveInterruptedTimer,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      _person.clear();
      _show('Support timer started · $person');
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _show('Could not start support: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories = state.selectableSupportCategories;
    if (categories.isEmpty) return const SizedBox.shrink();

    final running = state.activeTimer != null;
    return Panel(
      tone: PanelTone.support,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                size: 18,
                color: scheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Support now', style: theme.textTheme.titleSmall),
                    Text(
                      running
                          ? 'Tap a person: the running timer is stopped and saved first.'
                          : 'Tap a person to start a support timer with no mode.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: PersonPicker(
              controller: _person,
              enabled: !_busy,
              compact: true,
              hint: 'Who are you supporting?',
              onSelected: (name) => unawaited(_startWith(name)),
            ),
          ),
        ],
      ),
    );
  }
}
