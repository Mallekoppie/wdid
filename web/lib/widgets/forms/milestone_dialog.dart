import 'package:flutter/material.dart';

import '../../models/milestone.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import 'dialog_frame.dart';

Future<Milestone?> showMilestoneDialog(
  BuildContext context, {
  required AppState state,
  required String projectId,
  Milestone? existing,
}) {
  return showDialog<Milestone>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MilestoneDialog(
      state: state,
      projectId: projectId,
      existing: existing,
    ),
  );
}

class _MilestoneDialog extends StatefulWidget {
  const _MilestoneDialog({
    required this.state,
    required this.projectId,
    this.existing,
  });

  final AppState state;
  final String projectId;
  final Milestone? existing;

  @override
  State<_MilestoneDialog> createState() => _MilestoneDialogState();
}

class _MilestoneDialogState extends State<_MilestoneDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  DateTime? _dueDate;
  late bool _done;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _dueDate = existing == null || existing.dueDate.isEmpty
        ? null
        : DateTime.tryParse(existing.dueDate);
    _done = existing?.done ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final title = _title.text.trim();
      final dueDate = _dueDate == null ? '' : isoDate(_dueDate!);
      final Milestone saved;
      if (widget.existing == null) {
        saved = await widget.state.addMilestone(
          projectId: widget.projectId,
          title: title,
          dueDate: dueDate,
          done: _done,
        );
      } else {
        saved = await widget.state.updateMilestone(
          widget.existing!.copyWith(
            title: title,
            dueDate: dueDate,
            done: _done,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the milestone. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DialogFrame(
      title: widget.existing == null ? 'New milestone' : 'Edit milestone',
      subtitle:
          'A dated checkpoint for this project. The due date is optional.',
      icon: Icons.flag_outlined,
      maxWidth: 520,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _title,
              autofocus: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Ship backfill to staging',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Milestone title is required.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDueDate,
                    icon: const Icon(Icons.event_outlined, size: 15),
                    label: Text(
                      _dueDate == null
                          ? 'No due date'
                          : formatShortDate(_dueDate!),
                    ),
                  ),
                ),
                if (_dueDate != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    onPressed: () => setState(() => _dueDate = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              value: _done,
              onChanged: (value) => setState(() => _done = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Done'),
              subtitle: Text(
                'Already complete',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_error != null) FormError(message: _error!),
          ],
        ),
      ),
      actions: Row(
        children: [
          const Spacer(),
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
            label: const Text('Save milestone'),
          ),
        ],
      ),
    );
  }
}
