import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/drafts.dart';
import '../../models/enums.dart';
import '../../models/taxonomy.dart';
import '../../models/work_entry.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import '../duration_chips.dart';
import '../person_picker.dart';
import 'dialog_frame.dart';

/// Logs a work entry against [project]. The project's category and identity are
/// fixed, so every entry saved here is attributed to the project.
Future<WorkEntry?> showProjectEntryDialog(
  BuildContext context, {
  required AppState state,
  required Subcategory project,
}) {
  return showDialog<WorkEntry>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ProjectEntryDialog(state: state, project: project),
  );
}

class _ProjectEntryDialog extends StatefulWidget {
  const _ProjectEntryDialog({required this.state, required this.project});

  final AppState state;
  final Subcategory project;

  @override
  State<_ProjectEntryDialog> createState() => _ProjectEntryDialogState();
}

class _ProjectEntryDialogState extends State<_ProjectEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _outcome;
  List<String> _people = const [];
  late final TextEditingController _personText;
  late final TextEditingController _minutes;
  late DateTime _startedAt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _description = TextEditingController();
    _outcome = TextEditingController();
    _personText = TextEditingController();
    _minutes = TextEditingController(
      text: widget.state.settings.defaultDurationMinutes.toString(),
    );
    _startedAt = DateTime.now();
  }

  @override
  void dispose() {
    _description.dispose();
    _outcome.dispose();
    _personText.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _startedAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _startedAt.hour,
          _startedAt.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
    );
    if (picked != null) {
      setState(() {
        _startedAt = DateTime(
          _startedAt.year,
          _startedAt.month,
          _startedAt.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.state.createWorkEntry(
        EntryDraft(
          categoryId: widget.project.categoryId,
          subcategoryId: widget.project.id,
          description: _description.text.trim(),
          outcome: _outcome.text.trim(),
          startedAt: _startedAt,
          minutes: int.parse(_minutes.text.trim()),
          people: peopleIncludingPending(_people, _personText),
          source: EntrySource.manual,
        ),
      );
      if (!mounted) return;
      unawaited(widget.state.addSupportPeople(saved.people));
      Navigator.of(context).pop(saved);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DialogFrame(
      title: 'Log time',
      subtitle: widget.project.name,
      icon: Icons.play_arrow,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _description,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'What did you do?',
                hintText: 'Backfill script skeleton',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'A short description is required.'
                  : null,
            ),
            formGap,
            TextFormField(
              controller: _outcome,
              decoration: const InputDecoration(
                labelText: 'Outcome or evidence (optional)',
                hintText: 'Script runs against staging',
              ),
            ),
            formGap,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 15),
                    label: Text(formatDayHeader(_startedAt)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 15),
                    label: Text(
                      formatTimeOfDay24(TimeOfDay.fromDateTime(_startedAt)),
                    ),
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
            formGap,
            PersonPicker(
              selected: _people,
              textController: _personText,
              label: 'Person (optional)',
              hint: 'Priya',
              onChanged: (people) => setState(() => _people = people),
            ),
            if (_error != null) FormError(message: _error!),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This entry is attributed to ${widget.project.name}.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
    );
  }
}
