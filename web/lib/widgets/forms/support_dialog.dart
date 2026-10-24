import 'package:flutter/material.dart';

import '../../data/entry_api.dart';
import '../../models/drafts.dart';
import '../../models/enums.dart';
import '../../models/link_ref.dart';
import '../../models/taxonomy.dart';
import '../../models/work_entry.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import '../app_dropdown.dart';
import '../duration_chips.dart';
import 'dialog_frame.dart';

/// The service-backed support form.
///
/// A support entry is an ordinary work entry under a support-role category:
/// the mode is its subcategory, the person is required, and no project or
/// initiative attribution is offered. It never appears on a project timeline.
Future<WorkEntry?> showServiceSupportDialog(
  BuildContext context, {
  required AppState state,
  WorkEntry? existing,
  String? initialPerson,
}) {
  return showDialog<WorkEntry>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ServiceSupportDialog(
      state: state,
      existing: existing,
      initialPerson: initialPerson,
    ),
  );
}

class _ServiceSupportDialog extends StatefulWidget {
  const _ServiceSupportDialog({
    required this.state,
    this.existing,
    this.initialPerson,
  });

  final AppState state;
  final WorkEntry? existing;
  final String? initialPerson;

  @override
  State<_ServiceSupportDialog> createState() => _ServiceSupportDialogState();
}

class _ServiceSupportDialogState extends State<_ServiceSupportDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _person;
  late final TextEditingController _team;
  late final TextEditingController _description;
  late final TextEditingController _outcome;
  late final TextEditingController _duration;
  late final TextEditingController _links;
  late String _modeId;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _error;
  String? _serverField;
  String? _serverMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _person = TextEditingController(
      text: existing?.person ?? widget.initialPerson ?? '',
    );
    _team = TextEditingController(text: existing?.team ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _outcome = TextEditingController(text: existing?.outcome ?? '');
    _duration = TextEditingController(
      text: (existing?.minutes ?? widget.state.settings.defaultDurationMinutes)
          .toString(),
    );
    _links = TextEditingController(
      text: [
        for (final link in existing?.links ?? const <LinkRef>[])
          link.label.isEmpty || link.label == link.url
              ? link.url
              : '${link.label} | ${link.url}',
      ].join('\n'),
    );
    _modeId = existing?.subcategoryId ?? '';
    if (_modeId.isEmpty) {
      final modes = widget.state.selectableSupportModes;
      _modeId = modes.isEmpty ? '' : modes.first.id;
    }
    final started = existing?.startedLocal ?? DateTime.now();
    _date = started;
    _time = TimeOfDay.fromDateTime(started);
  }

  @override
  void dispose() {
    _person.dispose();
    _team.dispose();
    _description.dispose();
    _outcome.dispose();
    _duration.dispose();
    _links.dispose();
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

  List<LinkRef> _parsedLinks() {
    final links = <LinkRef>[];
    for (final line in _links.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final separator = trimmed.indexOf('|');
      if (separator < 0) {
        links.add(LinkRef(label: trimmed, url: trimmed));
        continue;
      }
      links.add(
        LinkRef(
          label: trimmed.substring(0, separator).trim(),
          url: trimmed.substring(separator + 1).trim(),
        ),
      );
    }
    return links;
  }

  /// The modal's form is checked before the request so a support entry can
  /// never be saved without a person, even when the service is unreachable.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final mode = widget.state.subcategoryById(_modeId);
    final category = mode == null
        ? null
        : widget.state.categoryById(mode.categoryId);
    if (mode == null || category?.role != CategoryRole.support) {
      setState(() {
        _error = 'Choose a support mode.';
        _serverField = null;
      });
      return;
    }

    final startedAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final minutes = int.parse(_duration.text.trim());
    final person = _person.text.trim();
    final team = _team.text.trim();
    final description = _description.text.trim();
    final outcome = _outcome.text.trim();
    final links = _parsedLinks();

    setState(() {
      _saving = true;
      _error = null;
      _serverField = null;
      _serverMessage = null;
    });
    try {
      final WorkEntry saved;
      final existing = widget.existing;
      if (existing == null) {
        saved = await widget.state.createWorkEntry(
          EntryDraft(
            categoryId: category!.id,
            subcategoryId: mode.id,
            description: description,
            outcome: outcome,
            startedAt: startedAt,
            minutes: minutes,
            person: person,
            team: team,
            links: links,
            source: EntrySource.manual,
          ),
        );
      } else {
        saved = await widget.state.updateWorkEntry(
          existing.copyWith(
            categoryId: category!.id,
            subcategoryId: mode.id,
            description: description,
            outcome: outcome,
            startedAt: startedAt,
            endedAt: startedAt.add(Duration(minutes: minutes)),
            minutes: minutes,
            localDate: isoDate(startedAt),
            person: person,
            team: team,
            links: links,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on EntryFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _serverField = error.field;
        _serverMessage = error.message;
        _error = error.field == null
            ? 'Could not save the support entry. ${error.message}'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the support entry. $error';
      });
    }
  }

  String? _fieldError(String field) =>
      _serverField == field ? _serverMessage : null;

  @override
  Widget build(BuildContext context) {
    final modes = widget.state.selectableSupportModes;
    final existingMode = widget.existing?.subcategoryId ?? '';
    final modeItems = [
      for (final mode in modes)
        DropdownMenuItem(value: mode.id, child: Text(mode.name)),
      if (existingMode.isNotEmpty &&
          !modes.any((mode) => mode.id == existingMode) &&
          widget.state.subcategoryById(existingMode) != null)
        DropdownMenuItem(
          value: existingMode,
          child: Text(widget.state.subcategoryById(existingMode)!.name),
        ),
    ];
    if (modeItems.isEmpty) {
      return DialogFrame(
        title: 'Log support',
        subtitle: 'Support work is reported separately from initiative time.',
        icon: Icons.volunteer_activism_outlined,
        content: Text(
          'Add a support mode in Settings first. A support mode is a '
          'subcategory of a support-role category.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    return DialogFrame(
      title: widget.existing == null ? 'Log support' : 'Edit support entry',
      subtitle: 'Support work is reported separately and is never attributed to a project.',
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
                    decoration: InputDecoration(
                      labelText: 'Person',
                      hintText: 'Priya',
                      errorText: _fieldError('person'),
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
                    decoration: InputDecoration(
                      labelText: 'Team (optional)',
                      hintText: 'Payments',
                      errorText: _fieldError('team'),
                    ),
                  ),
                ),
              ],
            ),
            formGap,
            Row(
              children: [
                Expanded(
                  child: AppDropdown<String>(
                    value: _modeId,
                    label: 'Mode',
                    errorText: _fieldError('subcategoryId'),
                    items: modeItems,
                    onChanged: (value) {
                      if (value != null) setState(() => _modeId = value);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _duration,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Minutes',
                      errorText: _fieldError('duration'),
                    ),
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
              controller: _description,
              decoration: InputDecoration(
                labelText: 'What did you do?',
                hintText: 'Reviewed the event bus design',
                errorText: _fieldError('description'),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'A short description is required.'
                  : null,
            ),
            formGap,
            TextFormField(
              controller: _outcome,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Impact or outcome',
                hintText: 'Three risks identified before implementation',
                errorText: _fieldError('outcome'),
              ),
            ),
            formGap,
            TextFormField(
              controller: _links,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Links (one per line, label | url)',
                hintText: 'Design doc | https://example.com/doc',
                errorText: _fieldError('links'),
              ),
            ),
            if (_error != null) FormError(message: _error!),
          ],
        ),
      ),
      actions: Row(
        children: [
          Expanded(
            child: Text(
              'Reported in support rollups',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
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
