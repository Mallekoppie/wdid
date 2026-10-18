import 'package:flutter/material.dart';

import '../../models/drafts.dart';
import '../../models/enums.dart';
import '../../models/initiative.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import '../app_dropdown.dart';
import '../duration_chips.dart';
import 'dialog_frame.dart';

Future<Initiative?> showInitiativeDialog(
  BuildContext context, {
  required AppState state,
  Initiative? existing,
}) {
  return showDialog<Initiative>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _InitiativeDialog(state: state, existing: existing),
  );
}

class _InitiativeDialog extends StatefulWidget {
  const _InitiativeDialog({required this.state, this.existing});

  final AppState state;
  final Initiative? existing;

  @override
  State<_InitiativeDialog> createState() => _InitiativeDialogState();
}

class _InitiativeDialogState extends State<_InitiativeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _summary;
  late final TextEditingController _target;
  late final TextEditingController _tags;
  late InitiativeStatus _status;
  late int _progress;
  DateTime? _targetDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _summary = TextEditingController(text: existing?.summary ?? '');
    _target = TextEditingController(text: existing?.targetOutcome ?? '');
    _tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
    _status = existing?.status ?? InitiativeStatus.active;
    _progress = existing?.progress ?? 0;
    _targetDate = existing?.targetDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _target.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final tags = _tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Initiative saved;
      if (widget.existing == null) {
        saved = await widget.state.createInitiative(
          InitiativeDraft(
            name: _name.text.trim(),
            summary: _summary.text.trim(),
            targetOutcome: _target.text.trim(),
            status: _status,
            progress: _progress,
            targetDate: _targetDate,
            tags: tags,
          ),
        );
      } else {
        saved = await widget.state.updateInitiative(
          widget.existing!.copyWith(
            name: _name.text.trim(),
            summary: _summary.text.trim(),
            targetOutcome: _target.text.trim(),
            status: _status,
            progress: _progress,
            targetDate: _targetDate,
            tags: tags,
            clearTargetDate: _targetDate == null,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the initiative. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DialogFrame(
      title: widget.existing == null ? 'New initiative' : 'Edit initiative',
      subtitle: 'Initiatives are the major bodies of work you report on.',
      icon: Icons.flag_outlined,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Billing migration',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Initiative name is required.'
                  : null,
            ),
            formGap,
            TextFormField(
              controller: _summary,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Summary (optional)',
                hintText: 'What this body of work covers',
              ),
            ),
            formGap,
            TextFormField(
              controller: _target,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Target outcome',
                hintText: 'Invoice generation under 5 minutes',
              ),
            ),
            formGap,
            Row(
              children: [
                Expanded(
                  child: AppDropdown<InitiativeStatus>(
                    value: _status,
                    label: 'Status',
                    items: [
                      for (final status in InitiativeStatus.values)
                        DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                    ],
                    onChanged: (status) {
                      if (status != null) setState(() => _status = status);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTargetDate,
                    icon: const Icon(Icons.event_outlined, size: 15),
                    label: Text(
                      _targetDate == null
                          ? 'No target date'
                          : formatShortDate(_targetDate!),
                    ),
                  ),
                ),
                if (_targetDate != null)
                  IconButton(
                    tooltip: 'Clear target date',
                    onPressed: () => setState(() => _targetDate = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text('Progress', style: theme.textTheme.labelMedium),
                const Spacer(),
                Text(
                  '$_progress%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
            Slider(
              value: _progress.toDouble(),
              max: 100,
              divisions: 20,
              label: '$_progress%',
              onChanged: (value) =>
                  setState(() => _progress = value.round()),
            ),
            formGap,
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
                hintText: 'billing, migration',
              ),
            ),
            if (_error != null) FormError(message: _error!),
          ],
        ),
      ),
      actions: Row(
        children: [
          Text(
            'Progress is a manual judgment, not computed from hours.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
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
            label: const Text('Save initiative'),
          ),
        ],
      ),
    );
  }
}
