import 'package:flutter/material.dart';

import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/attribution.dart';
import 'app_dropdown.dart';
import 'duration_chips.dart';
import 'panel.dart';

/// One-line capture bar. Enter saves; attribution is remembered for the next
/// entry so the default path stays under five seconds.
class QuickAddBar extends StatefulWidget {
  const QuickAddBar({super.key, this.onOpenFullForm});

  final VoidCallback? onOpenFullForm;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  AttributionChoice? _choice;
  int _minutes = 30;
  bool _saving = false;
  String? _error;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final state = AppStateScope.of(context);
    _choice = state.lastAttribution ??
        (state.attributionChoices.isEmpty ? null : state.attributionChoices.first);
    _minutes = state.settings.defaultDurationMinutes;
    if (!const [15, 30, 45, 60].contains(_minutes)) _minutes = 30;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final summary = _controller.text.trim();
    if (summary.isEmpty) {
      setState(() => _error = 'Describe what you did first.');
      _focusNode.requestFocus();
      return;
    }
    final choice = _choice;
    if (choice == null) {
      setState(() => _error = 'Create an initiative or pick a category first.');
      return;
    }
    final state = AppStateScope.read(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final item = await state.quickAdd(
        attribution: choice,
        minutes: _minutes,
        summary: summary,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _saving = false;
        _choice = choice;
      });
      _focusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logged ${_minutes}m to ${choice.label}',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await state.deleteEntry(item.id);
              } catch (_) {
                // Undo is best-effort; the service remains authoritative.
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the entry. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final choices = state.attributionChoices;
    if (_choice == null && choices.isNotEmpty) _choice = choices.first;

    final summaryField = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: !_saving,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(
        hintText: 'What did you do?',
        prefixIcon: const Icon(Icons.edit_note, size: 18),
        helperText: _error,
        helperStyle: TextStyle(color: scheme.error),
      ),
    );

    final attributionField = AppDropdown<AttributionChoice>(
      value: _choice ?? choices.first,
      items: [
        for (final choice in choices)
          DropdownMenuItem(
            value: choice,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  choice.isInitiative ? Icons.flag_outlined : Icons.category_outlined,
                  size: 14,
                  color: choice.isInitiative ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(choice.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (choice) {
        if (choice != null) setState(() => _choice = choice);
      },
    );

    final duration = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DurationChips(
          minutes: _minutes,
          compact: true,
          onChanged: (minutes) => setState(() => _minutes = minutes),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'More options',
          onPressed: widget.onOpenFullForm,
          icon: const Icon(Icons.tune, size: 17),
        ),
      ],
    );

    return Panel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summaryField,
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: attributionField),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: duration),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: summaryField),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 200, child: attributionField),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: duration,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Enter saves · T starts a timer · N opens full entry',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
