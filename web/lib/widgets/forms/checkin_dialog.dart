import 'package:flutter/material.dart';

import '../../models/check_in.dart';
import '../../models/drafts.dart';
import '../../models/enums.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import '../../widgets/app_dropdown.dart';
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

/// Edits a saved personal review's period and focus notes. Personal reviews
/// stay editable for their whole life; only final manager check-ins are
/// read-only.
Future<CheckIn?> showPersonalReviewDialog(
  BuildContext context, {
  required AppState state,
  required CheckIn checkIn,
}) {
  return showDialog<CheckIn>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PersonalReviewDialog(state: state, checkIn: checkIn),
  );
}

class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog({required this.state});

  final AppState state;

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends State<_CheckInDialog> {
  final _focusNotes = TextEditingController();
  CheckInKind _kind = CheckInKind.manager;
  CheckInAudience _audience = CheckInAudience.oneOnOne;
  DateTime? _start;
  DateTime? _end;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  @override
  void dispose() {
    _focusNotes.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final defaults = await widget.state.getCheckInDefaults(kind: _kind);
      if (!mounted) return;
      setState(() {
        _start = defaults.periodStart;
        _end = defaults.periodEnd;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not work out the next period. $error';
      });
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final currentStart = _start;
    final currentEnd = _end;
    if (currentStart == null || currentEnd == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? currentStart : currentEnd,
      firstDate: DateTime(2020),
      lastDate: widget.state.today,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  Future<void> _create() async {
    final start = _start;
    final end = _end;
    if (start == null || end == null) {
      setState(() => _error = 'Choose both dates for the period.');
      return;
    }
    if (start.isAfter(end)) {
      setState(() => _error = 'The period start must be on or before the end.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final checkIn = await widget.state.createCheckIn(
        CheckInDraft(
          periodStart: start,
          periodEnd: end,
          kind: _kind,
          audience: _kind == CheckInKind.manager ? _audience : null,
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
    final start = _start;
    final end = _end;
    final days = start == null || end == null || end.isBefore(start)
        ? 0
        : daysBetweenInclusive(start, end);

    return DialogFrame(
      title: 'Create check-in',
      subtitle: 'The period starts after the last final manager check-in and ends today.',
      icon: Icons.event_note_outlined,
      maxWidth: 560,
      content: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Text('Loading the next period…'),
                  ],
                ),
              ),
            )
          : _loadError != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FormError(message: _loadError!),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _loadDefaults,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDropdown<CheckInKind>(
                  value: _kind,
                  label: 'Kind',
                  icon: Icons.event_note_outlined,
                  items: const [
                    DropdownMenuItem(
                      value: CheckInKind.manager,
                      child: Text('Manager check-in'),
                    ),
                    DropdownMenuItem(
                      value: CheckInKind.personal,
                      child: Text('Personal review'),
                    ),
                  ],
                  onChanged: (kind) {
                    if (kind == null) return;
                    setState(() => _kind = kind);
                  },
                ),
                if (_kind == CheckInKind.manager) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppDropdown<CheckInAudience>(
                    value: _audience,
                    label: 'Audience',
                    icon: Icons.forum_outlined,
                    items: const [
                      DropdownMenuItem(
                        value: CheckInAudience.oneOnOne,
                        child: Text('1:1'),
                      ),
                      DropdownMenuItem(
                        value: CheckInAudience.performanceReview,
                        child: Text('Performance review'),
                      ),
                    ],
                    onChanged: (audience) {
                      if (audience == null) return;
                      setState(() => _audience = audience);
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(start: true),
                        icon: const Icon(Icons.first_page, size: 16),
                        label: Text(
                          start == null ? 'Start date' : formatFullDate(start),
                        ),
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
                        label: Text(
                          end == null ? 'End date' : formatFullDate(end),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$days ${days == 1 ? 'day' : 'days'} covered',
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
          Expanded(
            child: Text(
              'Aggregates are snapshotted by the service.',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: _loading || _loadError != null || _saving
                ? null
                : _create,
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

class _PersonalReviewDialog extends StatefulWidget {
  const _PersonalReviewDialog({required this.state, required this.checkIn});

  final AppState state;
  final CheckIn checkIn;

  @override
  State<_PersonalReviewDialog> createState() => _PersonalReviewDialogState();
}

class _PersonalReviewDialogState extends State<_PersonalReviewDialog> {
  late final _focusNotes = TextEditingController(
    text: widget.checkIn.focusNotes,
  );
  late DateTime _start = widget.checkIn.periodStart;
  late DateTime _end = widget.checkIn.periodEnd;
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
      lastDate: widget.state.today,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_start.isAfter(_end)) {
      setState(() => _error = 'The period start must be on or before the end.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.state.updateCheckIn(
        widget.checkIn.copyWith(
          periodStart: _start,
          periodEnd: _end,
          focusNotes: _focusNotes.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the review. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = _end.isBefore(_start) ? 0 : daysBetweenInclusive(_start, _end);

    return DialogFrame(
      title: 'Edit personal review',
      subtitle:
          'Personal reviews stay editable and never move the manager '
          'boundary.',
      icon: Icons.edit_outlined,
      maxWidth: 560,
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
            '$days ${days == 1 ? 'day' : 'days'} covered',
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
              hintText: 'What mattered in this period?',
            ),
          ),
          if (_error != null) FormError(message: _error!),
        ],
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
                : const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save review'),
          ),
        ],
      ),
    );
  }
}
