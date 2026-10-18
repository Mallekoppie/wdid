import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/work_item.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import '../app_dropdown.dart';
import '../duration_chips.dart';
import 'dialog_frame.dart';

Future<WorkItem?> showSupportDialog(
  BuildContext context, {
  required AppState state,
  WorkItem? existing,
  String? initialPerson,
}) {
  return showDialog<WorkItem>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SupportDialog(
      state: state,
      existing: existing,
      initialPerson: initialPerson,
    ),
  );
}

class _SupportDialog extends StatefulWidget {
  const _SupportDialog({
    required this.state,
    this.existing,
    this.initialPerson,
  });

  final AppState state;
  final WorkItem? existing;
  final String? initialPerson;

  @override
  State<_SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<_SupportDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _person;
  late final TextEditingController _team;
  late final TextEditingController _summary;
  late final TextEditingController _outcome;
  late final TextEditingController _duration;
  late SupportMode _mode;
  late String _initiative;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _person = TextEditingController(
      text: existing?.person ?? widget.initialPerson ?? '',
    );
    _team = TextEditingController(text: existing?.team ?? '');
    _summary = TextEditingController(text: existing?.summary ?? '');
    _outcome = TextEditingController(text: existing?.outcome ?? '');
    _duration = TextEditingController(
      text: (existing?.minutes ?? widget.state.settings.defaultDurationMinutes)
          .toString(),
    );
    _mode = existing?.supportMode ?? SupportMode.review;
    _initiative = existing?.initiativeId ?? 'none';
    _date = existing?.startedLocal ?? DateTime.now();
    _time = TimeOfDay.fromDateTime(existing?.startedLocal ?? DateTime.now());
  }

  @override
  void dispose() {
    _person.dispose();
    _team.dispose();
    _summary.dispose();
    _outcome.dispose();
    _duration.dispose();
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
    final startedAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final initiativeId = _initiative == 'none' ? null : _initiative;
    final minutes = int.parse(_duration.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final WorkItem saved;
      if (widget.existing == null) {
        saved = await widget.state.logSupport(
          mode: _mode,
          person: _person.text.trim(),
          team: _team.text.trim().isEmpty ? null : _team.text.trim(),
          minutes: minutes,
          summary: _summary.text.trim(),
          outcome: _outcome.text.trim(),
          initiativeId: initiativeId,
          startedAt: startedAt,
        );
      } else {
        final base = widget.existing!;
        saved = await widget.state.updateEntry(
          base.copyWith(
            type: WorkType.category,
            category: _mode.name,
            categoryLabel: _mode.label,
            initiativeId: initiativeId,
            startedAt: startedAt,
            minutes: minutes,
            localDate: isoDate(startedAt),
            summary: _summary.text.trim(),
            outcome: _outcome.text.trim(),
            person: _person.text.trim(),
            team: _team.text.trim().isEmpty ? null : _team.text.trim(),
            clearInitiative: initiativeId == null,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the support entry. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final initiatives = widget.state.openInitiatives;
    return DialogFrame(
      title: widget.existing == null ? 'Log support' : 'Edit support entry',
      subtitle: 'Support work is reported separately from initiative time.',
      icon: Icons.volunteer_activism_outlined,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _person,
                    autofocus: widget.existing == null,
                    decoration: const InputDecoration(
                      labelText: 'Person',
                      hintText: 'Priya',
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Who did you support?'
                            : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _team,
                    decoration: const InputDecoration(
                      labelText: 'Team (optional)',
                      hintText: 'Payments',
                    ),
                  ),
                ),
              ],
            ),
            formGap,
            Row(
              children: [
                Expanded(
                  child: AppDropdown<SupportMode>(
                    value: _mode,
                    label: 'Mode',
                    items: [
                      for (final mode in SupportMode.values)
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                    ],
                    onChanged: (mode) {
                      if (mode != null) setState(() => _mode = mode);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _duration,
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
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                DurationChips(
                  minutes: int.tryParse(_duration.text) ?? 0,
                  presets: const [15, 30, 45, 60],
                  onChanged: (minutes) =>
                      setState(() => _duration.text = minutes.toString()),
                ),
              ],
            ),
            formGap,
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
              ],
            ),
            formGap,
            TextFormField(
              controller: _summary,
              decoration: const InputDecoration(
                labelText: 'What did you do?',
                hintText: 'Reviewed the event bus design',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'A short summary is required.'
                  : null,
            ),
            formGap,
            TextFormField(
              controller: _outcome,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Impact or outcome',
                hintText: 'Three risks identified before implementation',
              ),
            ),
            formGap,
            AppDropdown<String>(
              value: _initiative,
              label: 'Related initiative (optional)',
              icon: Icons.flag_outlined,
              items: [
                const DropdownMenuItem(value: 'none', child: Text('None')),
                for (final initiative in initiatives)
                  DropdownMenuItem(
                    value: initiative.id,
                    child: Text(initiative.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _initiative = value);
              },
            ),
            if (_error != null) FormError(message: _error!),
          ],
        ),
      ),
      actions: Row(
        children: [
          Text(
            'Reported in support rollups',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            label: const Text('Save support'),
          ),
        ],
      ),
    );
  }
}
