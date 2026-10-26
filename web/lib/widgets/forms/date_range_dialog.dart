import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import 'dialog_frame.dart';

/// A quick range offered by [DateRangeDialog]. Callers precompute the range so
/// the dialog stays independent of whichever presets a screen uses.
class DateRangePreset {
  const DateRangePreset({required this.label, required this.range});

  final String label;
  final DateTimeRange range;
}

/// Shows the shared compact range dialog. Returns the chosen inclusive local
/// range, or null when the user cancels.
Future<DateTimeRange?> showDateRangeDialog(
  BuildContext context, {
  required DateTimeRange initialRange,
  required DateTime today,
  List<DateRangePreset> presets = const [],
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (context) => DateRangeDialog(
      initialRange: initialRange,
      today: dateOnly(today),
      presets: presets,
    ),
  );
}

/// One dialog for every "custom range" flow. It stays a compact dialog with
/// preset chips plus explicit start and end dates; it never opens Flutter's
/// full-bleed date-range picker.
class DateRangeDialog extends StatefulWidget {
  const DateRangeDialog({
    super.key,
    required this.initialRange,
    required this.today,
    this.presets = const [],
  });

  /// The widest the dialog may become. Dates remain bounded by 2020 and today.
  static const double maxWidth = 420;

  final DateTimeRange initialRange;
  final DateTime today;
  final List<DateRangePreset> presets;

  @override
  State<DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<DateRangeDialog> {
  static final DateTime _firstDate = DateTime(2020);

  late DateTime _start = dateOnly(widget.initialRange.start);
  late DateTime _end = dateOnly(widget.initialRange.end);
  String? _error;

  DateTime get _lastDate => widget.today;

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _start : _end;
    // A preset such as All time may start before the picker's first year, so
    // the seed is clamped into the selectable bounds.
    final seeded = current.isBefore(_firstDate)
        ? _firstDate
        : current.isAfter(_lastDate)
        ? _lastDate
        : current;
    final picked = await showDatePicker(
      context: context,
      initialDate: seeded,
      firstDate: _firstDate,
      lastDate: _lastDate,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = dateOnly(picked);
      } else {
        _end = dateOnly(picked);
      }
      _error = null;
    });
  }

  void _apply() {
    if (_start.isAfter(_end)) {
      setState(
        () => _error = 'The start date must be on or before the end date.',
      );
      return;
    }
    Navigator.of(context).pop(DateTimeRange(start: _start, end: _end));
  }

  bool _isSelected(DateRangePreset preset) =>
      dateOnly(preset.range.start) == _start &&
      dateOnly(preset.range.end) == _end;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = _end.isBefore(_start) ? 0 : daysBetweenInclusive(_start, _end);

    return DialogFrame(
      title: 'Custom range',
      subtitle: 'Pick a preset or choose the exact start and end dates.',
      icon: Icons.date_range_outlined,
      maxWidth: DateRangeDialog.maxWidth,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.presets.isNotEmpty) ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final preset in widget.presets)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: _isSelected(preset),
                    onSelected: (_) => setState(() {
                      _start = dateOnly(preset.range.start);
                      _end = dateOnly(preset.range.end);
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
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
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$days ${days == 1 ? 'day' : 'days'} covered',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
          if (_error != null) FormError(message: _error!),
        ],
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
