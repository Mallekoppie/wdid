import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/review_timeframe.dart';
import '../../utils/time_utils.dart';
import 'dialog_frame.dart';

/// Asks for the timeframe a personal review covers. The dialog only resolves
/// dates; it never calls the service, so cancelling leaves nothing behind.
Future<ReviewPeriod?> showReviewTimeframeDialog(
  BuildContext context, {
  required AppState state,
  ReviewTimeframe initial = ReviewTimeframe.last7Days,
}) {
  return showDialog<ReviewPeriod>(
    context: context,
    builder: (context) =>
        _ReviewTimeframeDialog(state: state, initial: initial),
  );
}

class _ReviewTimeframeDialog extends StatefulWidget {
  const _ReviewTimeframeDialog({required this.state, required this.initial});

  final AppState state;
  final ReviewTimeframe initial;

  @override
  State<_ReviewTimeframeDialog> createState() => _ReviewTimeframeDialogState();
}

class _ReviewTimeframeDialogState extends State<_ReviewTimeframeDialog> {
  late ReviewTimeframe _timeframe = widget.initial;
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _error;

  ReviewPeriod _period() {
    final defaults = reviewPeriodFor(
      ReviewTimeframe.custom,
      today: widget.state.today,
      boundaryStart: widget.state.defaultCheckInStart,
    );
    return reviewPeriodFor(
      _timeframe,
      today: widget.state.today,
      boundaryStart: widget.state.defaultCheckInStart,
      weekStart: widget.state.settings.weekStart,
      customStart: _customStart ?? defaults.start,
      customEnd: _customEnd ?? defaults.end,
    );
  }

  Future<void> _pickDate({required bool start}) async {
    final period = _period();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? period.start : period.end,
      firstDate: DateTime(2020),
      lastDate: widget.state.today,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _customStart = dateOnly(picked);
      } else {
        _customEnd = dateOnly(picked);
      }
      _error = null;
    });
  }

  void _confirm() {
    final period = _period();
    final error = validateReviewPeriod(
      period.start,
      period.end,
      today: widget.state.today,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(period);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final period = _period();

    return DialogFrame(
      title: 'New personal review',
      subtitle:
          'Choose a timeframe. The review opens live; nothing is saved until '
          'you save it.',
      icon: Icons.rate_review_outlined,
      maxWidth: 560,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final timeframe in ReviewTimeframe.values)
                ChoiceChip(
                  label: Text(timeframe.label),
                  selected: _timeframe == timeframe,
                  onSelected: (_) => setState(() {
                    _timeframe = timeframe;
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_timeframe == ReviewTimeframe.custom)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(start: true),
                    icon: const Icon(Icons.first_page, size: 16),
                    label: Text(formatFullDate(period.start)),
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
                    label: Text(formatFullDate(period.end)),
                  ),
                ),
              ],
            )
          else
            Text(
              '${formatFullDate(period.start)} → ${formatFullDate(period.end)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${period.daysCovered} ${period.daysCovered == 1 ? 'day' : 'days'} covered',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
          if (_timeframe == ReviewTimeframe.sinceLastManagerCheckIn) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Starts after the last final manager check-in. A personal review '
              'never moves that boundary.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
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
            onPressed: _confirm,
            icon: const Icon(Icons.rate_review_outlined, size: 16),
            label: const Text('Open review'),
          ),
        ],
      ),
    );
  }
}
