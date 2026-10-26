import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/drafts.dart';
import '../../models/enums.dart';
import '../../models/taxonomy.dart';
import '../../models/work_entry.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../theme/app_tokens.dart';
import '../../utils/people.dart';
import '../../utils/time_utils.dart';
import '../app_dropdown.dart';
import '../person_picker.dart';
import 'dialog_frame.dart';

/// The service-backed work-entry form used inline by the Log and inside
/// [showServiceEntryDialog] for the shell's "New entry" action.
class EntryForm extends StatefulWidget {
  const EntryForm({
    super.key,
    required this.entry,
    this.initialStart,
    this.initialCategoryId,
    this.initialSubcategoryId,
    required this.onCancel,
    required this.onSaved,
  });

  /// Null creates a new entry; otherwise the entry is edited in place.
  final WorkEntry? entry;
  final DateTime? initialStart;

  /// Seeds a new entry's taxonomy, for example from the Log's active filters.
  /// Only values the form could itself offer are used; an archived or unknown
  /// category seeds nothing and the remembered pair applies. Ignored when
  /// [entry] is not null.
  final String? initialCategoryId;
  final String? initialSubcategoryId;

  final VoidCallback onCancel;
  final ValueChanged<WorkEntry> onSaved;

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _outcome;
  late final TextEditingController _minutes;
  late List<String> _people;
  late final TextEditingController _personText;
  late String _categoryId;
  late String _subcategoryId;
  late DateTime _date;
  late TimeOfDay _time;
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    final start = entry?.startedLocal ?? widget.initialStart ?? DateTime.now();
    _description = TextEditingController(text: entry?.description ?? '');
    _outcome = TextEditingController(text: entry?.outcome ?? '');
    _minutes = TextEditingController(text: (entry?.minutes ?? 30).toString());
    _people = normalizePeople(entry?.people ?? const []);
    _personText = TextEditingController();
    _categoryId = entry?.categoryId ?? '';
    _subcategoryId = entry?.subcategoryId ?? '';
    _date = start;
    _time = TimeOfDay.fromDateTime(start);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (widget.entry != null) return;

    // A new entry starts from the caller's hint, else the user's defaults and
    // last capture pair. A remembered pair that has since been archived is not
    // offered again.
    final state = AppStateScope.of(context);
    _minutes.text = state.settings.defaultDurationMinutes.toString();
    final seeded = _seededTaxonomy(state);
    final preferred = state.lastCategoryId;
    _categoryId =
        seeded.categoryId ??
        (preferred != null &&
                state.selectableCategories.any(
                  (category) => category.id == preferred,
                )
            ? preferred
            : state.selectableCategories.isEmpty
            ? ''
            : state.selectableCategories.first.id);
    final lastSubcategory = state.lastSubcategoryId ?? '';
    _subcategoryId =
        seeded.subcategoryId ??
        (state
                .selectableSubcategoriesFor(_categoryId)
                .any((subcategory) => subcategory.id == lastSubcategory)
            ? lastSubcategory
            : '');
  }

  /// The caller's taxonomy hint, reduced to a pair the form can actually
  /// offer. A supplied category that is archived or unknown suppresses the
  /// hint entirely so the remembered pair applies exactly as before. A
  /// subcategory hint implies its parent, keeping the pair consistent.
  ({String? categoryId, String? subcategoryId}) _seededTaxonomy(
    AppState state,
  ) {
    final requestedCategory = widget.initialCategoryId;
    final requestedSubcategory = widget.initialSubcategoryId;

    String? categoryId;
    if (requestedCategory != null) {
      final selectable = state.selectableCategories.any(
        (category) => category.id == requestedCategory,
      );
      if (!selectable) return (categoryId: null, subcategoryId: null);
      categoryId = requestedCategory;
    }

    String? subcategoryId;
    if (requestedSubcategory != null) {
      final subcategory = state.subcategoryById(requestedSubcategory);
      if (subcategory != null &&
          state
              .selectableSubcategoriesFor(subcategory.categoryId)
              .any((candidate) => candidate.id == subcategory.id)) {
        if (categoryId == null) {
          final parent = state.selectableCategories.any(
            (category) => category.id == subcategory.categoryId,
          );
          if (!parent) return (categoryId: null, subcategoryId: null);
          categoryId = subcategory.categoryId;
        }
        if (categoryId == subcategory.categoryId) {
          subcategoryId = subcategory.id;
        }
      }
    }

    if (categoryId == null) return (categoryId: null, subcategoryId: null);
    return (categoryId: categoryId, subcategoryId: subcategoryId);
  }

  @override
  void dispose() {
    _description.dispose();
    _outcome.dispose();
    _minutes.dispose();
    _personText.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = AppStateScope.read(context);
    final startedAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final minutes = int.parse(_minutes.text.trim());
    final description = _description.text.trim();
    final outcome = _outcome.text.trim();
    final people = peopleIncludingPending(_people, _personText);
    if (state.categoryById(_categoryId)?.role == CategoryRole.support &&
        people.isEmpty) {
      setState(() => _error = 'Who are you supporting? Add a person.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.entry;
      final WorkEntry saved;
      if (existing == null) {
        saved = await state.createWorkEntry(
          EntryDraft(
            categoryId: _categoryId,
            subcategoryId: _subcategoryId,
            description: description,
            outcome: outcome,
            startedAt: startedAt,
            minutes: minutes,
            people: people,
            source: EntrySource.manual,
          ),
        );
      } else {
        saved = await state.updateWorkEntry(
          existing.copyWith(
            categoryId: _categoryId,
            subcategoryId: _subcategoryId,
            description: description,
            outcome: outcome,
            startedAt: startedAt,
            endedAt: startedAt.add(Duration(minutes: minutes)),
            minutes: minutes,
            localDate: isoDate(startedAt),
            people: people,
          ),
        );
      }
      if (people.isNotEmpty) {
        unawaited(state.addSupportPeople(people));
      }
      await state.refreshLog();
      if (!mounted) return;
      widget.onSaved(saved);
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
    final subcategories = _categoryId.isEmpty
        ? <Subcategory>[]
        : state.selectableSubcategoriesFor(_categoryId);
    final support =
        state.categoryById(_categoryId)?.role == CategoryRole.support;
    final selectedCategory =
        state.selectableCategories.any((category) => category.id == _categoryId)
        ? null
        : state.categoryById(_categoryId);
    final selectedSubcategory =
        subcategories.any((subcategory) => subcategory.id == _subcategoryId)
        ? null
        : state.subcategoryById(_subcategoryId);
    return Container(
      width: double.infinity,
      color: widget.entry == null
          ? Colors.transparent
          : scheme.surfaceContainerLow.withValues(alpha: 0.6),
      padding: widget.entry == null
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(112, 12, 16, 14),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _description,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Backfill script skeleton',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'A short description is required.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 560;
                final categoryField = AppDropdown<String>(
                  value: _categoryId,
                  label: 'Category',
                  items: [
                    // An entry already filed under an archived category keeps
                    // its attribution visible but cannot be re-selected.
                    if (_categoryId.isNotEmpty && selectedCategory != null)
                      DropdownMenuItem(
                        value: _categoryId,
                        enabled: false,
                        child: Text(
                          selectedCategory.name.isEmpty
                              ? 'Unknown category'
                              : '${selectedCategory.name} (archived)',
                        ),
                      ),
                    for (final category in state.selectableCategories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _categoryId = value;
                      if (state.subcategoryById(_subcategoryId)?.categoryId !=
                          value) {
                        _subcategoryId = '';
                      }
                    });
                  },
                );
                final subcategoryField = AppDropdown<String>(
                  value: _subcategoryId,
                  label: 'Subcategory',
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No subcategory'),
                    ),
                    if (_subcategoryId.isNotEmpty &&
                        selectedSubcategory != null)
                      DropdownMenuItem(
                        value: _subcategoryId,
                        enabled: false,
                        child: Text(
                          selectedSubcategory.name.isEmpty
                              ? 'Unknown subcategory'
                              : '${selectedSubcategory.name} (archived)',
                        ),
                      ),
                    for (final subcategory in subcategories)
                      DropdownMenuItem(
                        value: subcategory.id,
                        child: Text(subcategory.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _subcategoryId = value);
                    }
                  },
                );
                if (stacked) {
                  return Column(
                    children: [
                      categoryField,
                      const SizedBox(height: AppSpacing.sm),
                      subcategoryField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: categoryField),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: subcategoryField),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 15),
                    label: Text(formatDayHeader(_date)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 15),
                    label: Text(formatTimeOfDay24(_time)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes'),
                    validator: (value) {
                      final minutes = int.tryParse(value?.trim() ?? '');
                      if (minutes == null || minutes < 1 || minutes > 1440) {
                        return '1–1440';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (support || _people.isNotEmpty) ...[
              PersonPicker(
                selected: _people,
                textController: _personText,
                label: 'Person',
                hint: 'Priya',
                onChanged: (people) => setState(() => _people = people),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextFormField(
              controller: _outcome,
              decoration: const InputDecoration(
                labelText: 'Outcome or evidence',
                hintText: 'Script runs against staging',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Save entry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the service-backed entry form as a modal dialog. Used by the shell's
/// "New entry" action, which must write through the generated EntryService.
Future<WorkEntry?> showServiceEntryDialog(
  BuildContext context, {
  WorkEntry? entry,
  String? initialCategoryId,
  String? initialSubcategoryId,
}) {
  return showDialog<WorkEntry>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        entry == null ? 'New entry' : 'Edit entry',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                EntryForm(
                  entry: entry,
                  initialCategoryId: initialCategoryId,
                  initialSubcategoryId: initialSubcategoryId,
                  onCancel: () => Navigator.of(dialogContext).pop(),
                  onSaved: (saved) => Navigator.of(dialogContext).pop(saved),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
