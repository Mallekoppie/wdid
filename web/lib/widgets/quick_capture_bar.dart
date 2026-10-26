import 'dart:async';

import 'package:flutter/material.dart';

import '../data/entry_api.dart';
import '../models/taxonomy.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';
import 'app_dropdown.dart';
import 'duration_chips.dart';
import 'panel.dart';
import 'person_picker.dart';

/// One-line capture bar for a work entry. Enter saves; the category and
/// subcategory pair is remembered for the next capture.
class QuickCaptureBar extends StatefulWidget {
  const QuickCaptureBar({super.key});

  @override
  State<QuickCaptureBar> createState() => _QuickCaptureBarState();
}

class _QuickCaptureBarState extends State<QuickCaptureBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<String> _people = const [];
  final _personText = TextEditingController();

  String _categoryId = '';
  String _subcategoryId = '';
  int _minutes = 30;
  bool _saving = false;
  bool _initialized = false;

  String? _descriptionError;
  String? _categoryError;
  String? _subcategoryError;
  String? _personError;
  String? _minutesError;
  String? _generalError;

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
    _subcategoryId = state.lastSubcategoryId ?? '';
    final subcategories = state.selectableSubcategoriesFor(_categoryId);
    if (!subcategories.any((subcategory) => subcategory.id == _subcategoryId)) {
      _subcategoryId = '';
    }
    _minutes = state.settings.defaultDurationMinutes;
  }

  @override
  void dispose() {
    _controller.dispose();
    _personText.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clearErrors() {
    _descriptionError = null;
    _categoryError = null;
    _subcategoryError = null;
    _personError = null;
    _minutesError = null;
    _generalError = null;
  }

  Future<void> _save() async {
    final state = AppStateScope.read(context);
    final description = _controller.text.trim();
    final categoryId = _categoryId;
    final category = state.categoryById(categoryId);
    final support = category?.role == CategoryRole.support;
    final people = support
        ? peopleIncludingPending(_people, _personText)
        : const <String>[];
    String? descriptionError;
    String? categoryError;
    String? personError;
    if (description.isEmpty) {
      descriptionError = 'Describe what you did first.';
    }
    if (category == null) {
      categoryError = 'Choose a category.';
    }
    if (support && people.isEmpty) {
      personError = 'Who did you support?';
    }
    if (_minutes < 1) {
      setState(() {
        _descriptionError = descriptionError;
        _categoryError = categoryError;
        _personError = personError;
        _minutesError = 'Choose a duration.';
      });
      return;
    }
    if (descriptionError != null ||
        categoryError != null ||
        personError != null) {
      setState(() {
        _descriptionError = descriptionError;
        _categoryError = categoryError;
        _personError = personError;
        _minutesError = null;
        _generalError = null;
      });
      if (descriptionError != null) _focusNode.requestFocus();
      return;
    }

    setState(() {
      _saving = true;
      _clearErrors();
    });
    try {
      final entry = await state.quickCapture(
        categoryId: categoryId,
        subcategoryId: _subcategoryId,
        description: description,
        minutes: _minutes,
        people: people,
      );
      if (!mounted) return;
      unawaited(state.addSupportPeople(people));
      _controller.clear();
      setState(() => _saving = false);
      _focusNode.requestFocus();

      final category = state.categoryById(entry.categoryId)?.name ?? 'entry';
      final subcategory = state.subcategoryById(entry.subcategoryId)?.name;
      final target = subcategory == null || subcategory.isEmpty
          ? category
          : '$category · $subcategory';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logged ${formatDuration(entry.minutes)} to $target'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await state.deleteWorkEntry(entry.id);
              } catch (_) {
                // Undo is best-effort; the service remains authoritative.
              }
            },
          ),
        ),
      );
    } on EntryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        switch (failure.field) {
          case 'description':
            _descriptionError = failure.message;
          case 'categoryId':
            _categoryError = failure.message;
          case 'subcategoryId':
            _subcategoryError = failure.message;
          case 'person':
            _personError = failure.message;
          case 'minutes':
            _minutesError = failure.message;
          default:
            _generalError = failure.message;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _generalError = 'Could not save the entry. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories = state.selectableCategories;

    if (categories.isNotEmpty &&
        !categories.any((category) => category.id == _categoryId)) {
      _categoryId = categories.first.id;
    }
    final subcategories = state.selectableSubcategoriesFor(_categoryId);
    if (subcategories.isNotEmpty &&
        !subcategories.any((subcategory) => subcategory.id == _subcategoryId)) {
      _subcategoryId = '';
    }
    final support =
        state.categoryById(_categoryId)?.role == CategoryRole.support;
    final personField = PersonPicker(
      selected: _people,
      textController: _personText,
      enabled: !_saving,
      hint: 'Who did you support?',
      errorText: _personError,
      onChanged: (people) {
        setState(() {
          _people = people;
          _personError = null;
        });
      },
      onSubmitted: (_) => _save(),
    );

    final descriptionField = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: !_saving,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      onChanged: (_) {
        if (_descriptionError != null || _generalError != null) {
          setState(() {
            _descriptionError = null;
            _generalError = null;
          });
        }
      },
      decoration: InputDecoration(
        hintText: 'What did you do?',
        prefixIcon: const Icon(Icons.edit_note, size: 18),
        errorText: _descriptionError,
      ),
    );

    final categoryField = AppDropdown<String>(
      value: _categoryId,
      label: 'Category',
      hint: categories.isEmpty ? 'Create a category first' : null,
      enabled: categories.isNotEmpty && !_saving,
      errorText: _categoryError,
      items: [
        for (final category in categories)
          DropdownMenuItem(value: category.id, child: Text(category.name)),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _categoryId = value;
          _subcategoryId = '';
          _categoryError = null;
          _subcategoryError = null;
          _personError = null;
        });
      },
    );

    final subcategoryField = AppDropdown<String>(
      value: _subcategoryId,
      label: 'Subcategory',
      enabled: subcategories.isNotEmpty && !_saving,
      errorText: _subcategoryError,
      items: [
        const DropdownMenuItem(value: '', child: Text('No subcategory')),
        for (final subcategory in subcategories)
          DropdownMenuItem(
            value: subcategory.id,
            child: Text(subcategory.name),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _subcategoryId = value;
          _subcategoryError = null;
        });
      },
    );

    final presets = {15, 30, 45, 60, _minutes}.toList()..sort();
    final durationChips = DurationChips(
      minutes: _minutes,
      presets: presets,
      compact: true,
      enabled: !_saving,
      onChanged: (minutes) => setState(() {
        _minutes = minutes;
        _minutesError = null;
      }),
    );

    final addButton = FilledButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add, size: 16),
      label: const Text('Add'),
    );

    return Panel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 820) {
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
                    Row(
                      children: [
                        Expanded(child: durationChips),
                        const SizedBox(width: AppSpacing.sm),
                        addButton,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: descriptionField),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 170, child: categoryField),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 170, child: subcategoryField),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: durationChips,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: addButton,
                  ),
                ],
              );
            },
          ),
          if (support) ...[
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: personField,
            ),
          ],
          if (_minutesError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _minutesError!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          if (_generalError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _generalError!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Enter saves · category and subcategory are remembered',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
