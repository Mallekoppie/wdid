import 'package:flutter/material.dart';

import '../../models/check_in.dart';
import '../../models/drafts.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import 'dialog_frame.dart';

Future<CheckIn?> showCheckInDialog(
  BuildContext context, {
  required AppState state,
}) {
  return showDialog<CheckIn>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CheckInDialog(state: state),
  );
}

class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog({required this.state});

  final AppState state;

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  late DateTime _start = widget.state.defaultCheckInStart;
  late DateTime _end = widget.state.today;
  final _focusNotes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _focusNotes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _create() async {
    if (_start.isAfter(_end)) {
      setState(() => _error = 'The period start must be before the end date.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final checkIn = await widget.state.createCheckIn(
        CheckInDraft(
          periodStart: _start,
          periodEnd: _end,
          focusNotes: _focusNotes.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(checkIn);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not create the check-in. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = daysBetweenInclusive(_start, _end);
    return DialogFrame(
      title: 'Create check-in',
      subtitle: 'The period starts at the last check-in and ends today.',
      icon: Icons.event_note_outlined,
      maxWidth: 520,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(start: true),
                  icon: const Icon(Icons.first_page, size: 16),
                  label: Text(formatFullDate(_start)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(Icons.arrow_forward, size: 15),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(start: false),
                  icon: const Icon(Icons.today_outlined, size: 16),
                  label: Text(formatFullDate(_end)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$days days covered',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _focusNotes,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Focus notes (optional)',
              hintText: 'What mattered this period?',
            ),
          ),
          if (_error != null) FormError(message: _error!),
        ],
      ),
      actions: Row(
        children: [
          Text(
            'Aggregates are snapshotted by the service.',
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
            onPressed: _saving ? null : _create,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 16),
            label: const Text('Create check-in'),
          ),
        ],
      ),
    );
  }
}
