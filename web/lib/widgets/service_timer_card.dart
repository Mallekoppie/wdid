import 'dart:async';

import 'package:flutter/material.dart';

import '../data/timer_api.dart';
import '../models/taxonomy.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';
import 'panel.dart';
import 'person_picker.dart';
import 'searchable_dropdown.dart';
import 'timer_actions.dart';

/// Today's timer card for service mode. The category and subcategory are
/// chosen here; every transition goes through the TimerService, so the pill,
/// a refresh and a second tab all see the same timer.
class ServiceTimerCard extends StatefulWidget {
  const ServiceTimerCard({super.key});

  @override
  State<ServiceTimerCard> createState() => _ServiceTimerCardState();
}

class _ServiceTimerCardState extends State<ServiceTimerCard> {
  final _description = TextEditingController();
  final _person = TextEditingController();

  String _categoryId = '';
  String _subcategoryId = '';
  bool _busy = false;
  bool _initialized = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final state = AppStateScope.of(context);
    final categories = state.selectableCategories;
    _categoryId = state.lastCategoryId ?? '';
    if (!categories.any((category) => category.id == _categoryId)) {
      _categoryId = categories.isEmpty ? '' : categories.first.id;
    }
    final subcategories = state.selectableSubcategoriesFor(_categoryId);
    _subcategoryId = state.lastSubcategoryId ?? '';
    if (!subcategories.any((subcategory) => subcategory.id == _subcategoryId)) {
      _subcategoryId = '';
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _person.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final state = AppStateScope.read(context);
    final person = _person.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await state.startTimer(
        categoryId: _categoryId,
        subcategoryId: _subcategoryId,
        description: _description.text,
        person: person,
      );
      if (person.isNotEmpty) unawaited(state.addSupportPerson(person));
      if (!mounted) return;
      setState(() => _busy = false);
      _description.clear();
      _person.clear();
    } on TimerFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not start the timer. $error';
      });
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
    setState(() => _busy = true);
    try {
      final result = await stopTimerWithDecision(context, state: state);
      if (!mounted) return;
      setState(() => _busy = false);
      if (result != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(stoppedTimerMessage(result))));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
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

    if (timer != null) {
      final elapsed = timer.elapsedAt(DateTime.now());
      return Panel(
        tone: PanelTone.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PanelHeader(
              title: timer.isPaused ? 'Timer paused' : 'Running',
              subtitle: 'Since ${formatTime(timer.startedAt)}',
              icon: Icons.timer_outlined,
              trailing: Text(
                formatClock(elapsed),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.category_outlined, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  state.timerLabel(timer),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (timer.person.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text('·', style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(width: AppSpacing.sm),
                  Text(timer.person, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(width: AppSpacing.sm),
                Text('·', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    timer.description,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => unawaited(_togglePause(timer.isPaused)),
                  icon: Icon(
                    timer.isPaused ? Icons.play_arrow : Icons.pause,
                    size: 16,
                  ),
                  label: Text(timer.isPaused ? 'Resume' : 'Pause'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _stop,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop, size: 16),
                  label: const Text('Stop & save'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final categories = state.selectableCategories;
    if (categories.isNotEmpty &&
        !categories.any((category) => category.id == _categoryId)) {
      _categoryId = categories.first.id;
      _subcategoryId = '';
    }
    final subcategories = state.selectableSubcategoriesFor(_categoryId);
    if (!subcategories.any((subcategory) => subcategory.id == _subcategoryId)) {
      _subcategoryId = '';
    }
    final support =
        state.categoryById(_categoryId)?.role == CategoryRole.support;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHeader(
            title: 'Start a timer',
            subtitle: 'Choose a category and subcategory. The timer follows you everywhere.',
            icon: Icons.play_circle_outline,
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              final descriptionField = TextField(
                controller: _description,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_start()),
                decoration: const InputDecoration(
                  hintText: 'What are you working on?',
                  prefixIcon: Icon(Icons.edit_note, size: 18),
                ),
              );
              final categoryField = SearchableDropdown<String>(
                value: _categoryId,
                label: 'Category',
                hint: categories.isEmpty ? 'Create a category first' : null,
                enabled: categories.isNotEmpty && !_busy,
                options: [
                  for (final category in categories)
                    SearchableDropdownOption(
                      value: category.id,
                      label: category.name,
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _categoryId = value;
                    _subcategoryId = '';
                    _error = null;
                  });
                },
              );
              final subcategoryField = SearchableDropdown<String>(
                value: _subcategoryId,
                label: 'Subcategory',
                enabled: subcategories.isNotEmpty && !_busy,
                options: [
                  const SearchableDropdownOption(
                    value: '',
                    label: 'No subcategory',
                    pinned: true,
                  ),
                  for (final subcategory in subcategories)
                    SearchableDropdownOption(
                      value: subcategory.id,
                      label: subcategory.name,
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _subcategoryId = value;
                    _error = null;
                  });
                },
              );

              final startButton = FilledButton.icon(
                onPressed: _busy || categories.isEmpty ? null : _start,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Start'),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    descriptionField,
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: categoryField),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: subcategoryField),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(alignment: Alignment.centerRight, child: startButton),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: descriptionField),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 170, child: categoryField),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 170, child: subcategoryField),
                  const SizedBox(width: AppSpacing.sm),
                  startButton,
                ],
              );
            },
          ),
          if (support) ...[
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: PersonPicker(
                controller: _person,
                enabled: !_busy,
                hint: 'Who are you supporting?',
                onSubmitted: (_) => unawaited(_start()),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
