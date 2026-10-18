import 'package:flutter/material.dart';

import '../../models/drafts.dart';
import '../../models/enums.dart';
import '../../models/initiative.dart';
import '../../models/work_item.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/attribution.dart';
import '../../utils/time_utils.dart';
import '../app_dropdown.dart';
import '../duration_chips.dart';
import 'dialog_frame.dart';

Future<WorkItem?> showEntryDialog(
  BuildContext context, {
  required AppState state,
  WorkItem? existing,
  String? initialSummary,
  AttributionChoice? initialChoice,
  int? initialMinutes,
}) {
  return showDialog<WorkItem>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _EntryDialog(
      state: state,
      existing: existing,
      initialSummary: initialSummary,
      initialChoice: initialChoice,
      initialMinutes: initialMinutes,
    ),
  );
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({
    required this.state,
    this.existing,
    this.initialSummary,
    this.initialChoice,
    this.initialMinutes,
  });

  final AppState state;
  final WorkItem? existing;
  final String? initialSummary;
  final AttributionChoice? initialChoice;
  final int? initialMinutes;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _summary;
  late final TextEditingController _outcome;
  late final TextEditingController _notes;
  late final TextEditingController _tags;
  late final TextEditingController _linkLabel;
  late final TextEditingController _linkUrl;
  late final TextEditingController _duration;
  late AttributionChoice? _choice;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _summary = TextEditingController(
      text: existing?.summary ?? widget.initialSummary ?? '',
    );
    _outcome = TextEditingController(text: existing?.outcome ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
    final link = existing?.links.isNotEmpty == true ? existing!.links.first : null;
    _linkLabel = TextEditingController(text: link?.label ?? '');
    _linkUrl = TextEditingController(text: link?.url ?? '');
    _duration = TextEditingController(
      text: (existing?.minutes ?? widget.initialMinutes ?? widget.state.settings.defaultDurationMinutes)
          .toString(),
    );
    _date = existing?.startedLocal ?? DateTime.now();
    _time = TimeOfDay.fromDateTime(existing?.startedLocal ?? DateTime.now());
    _choice = widget.initialChoice ?? _choiceFor(existing);
    if (_choice == null && widget.state.attributionChoices.isNotEmpty) {
      _choice = widget.state.attributionChoices.first;
    }
  }

  AttributionChoice? _choiceFor(WorkItem? existing) {
    if (existing == null) return widget.state.lastAttribution;
    final choices = widget.state.attributionChoices;
    if (existing.initiativeId != null) {
      for (final choice in choices) {
        if (choice.initiativeId == existing.initiativeId) return choice;
      }
    }
    if (existing.category != null) {
      for (final choice in choices) {
        if (choice.category == existing.category) return choice;
      }
      return AttributionChoice.category(
        existing.category!,
        existing.categoryLabel ?? existing.category!,
      );
    }
    return null;
  }

  @override
  void dispose() {
    _summary.dispose();
    _outcome.dispose();
    _notes.dispose();
    _tags.dispose();
    _linkLabel.dispose();
    _linkUrl.dispose();
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
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final choice = _choice;
    if (choice == null) {
      setState(() => _error = 'Choose an initiative or category.');
      return;
    }
    final startedAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final links = _linkUrl.text.trim().isEmpty
        ? <LinkRef>[]
        : [
            LinkRef(
              label: _linkLabel.text.trim().isEmpty
                  ? 'Link'
                  : _linkLabel.text.trim(),
              url: _linkUrl.text.trim(),
            ),
          ];
    final tags = _tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final minutes = int.parse(_duration.text.trim());

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final WorkItem saved;
      if (widget.existing == null) {
        saved = await widget.state.createEntry(
          WorkItemDraft(
            type: choice.type,
            initiativeId: choice.initiativeId,
            category: choice.category,
            categoryLabel: choice.categoryLabel ?? choice.label,
            startedAt: startedAt,
            minutes: minutes,
            summary: _summary.text.trim(),
            outcome: _outcome.text.trim(),
            notes: _notes.text.trim(),
            links: links,
            tags: tags,
            source: 'manual',
          ),
        );
      } else {
        final base = widget.existing!;
        saved = await widget.state.updateEntry(
          base.copyWith(
            type: choice.type,
            initiativeId: choice.initiativeId,
            category: choice.category,
            categoryLabel: choice.categoryLabel ?? choice.label,
            startedAt: startedAt,
            minutes: minutes,
            localDate: isoDate(startedAt),
            summary: _summary.text.trim(),
            outcome: _outcome.text.trim(),
            notes: _notes.text.trim(),
            links: links,
            tags: tags,
            clearInitiative: choice.type == WorkType.category,
            clearPerson: true,
            source: base.source,
          ),
        );
      }
      if (!mounted) return;
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
    final state = widget.state;
    final choices = state.attributionChoices;
    if (_choice == null && choices.isNotEmpty) _choice = choices.first;

    return DialogFrame(
      title: widget.existing == null ? 'New entry' : 'Edit entry',
      subtitle: 'Every entry carries one attribution and an optional outcome.',
      icon: Icons.edit_note,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _summary,
              autofocus: widget.existing == null,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'What did you do?',
                hintText: 'Backfill script skeleton',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'A short summary is required.'
                  : null,
            ),
            formGap,
            AppDropdown<AttributionChoice>(
              value: _choice ?? choices.first,
              label: 'Attribution',
              icon: _choice?.isInitiative == true
                  ? Icons.flag_outlined
                  : Icons.category_outlined,
              items: [
                for (final choice in choices)
                  DropdownMenuItem(
                    value: choice,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          choice.isInitiative
                              ? Icons.flag_outlined
                              : Icons.category_outlined,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            choice.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (choice) {
                if (choice != null) setState(() => _choice = choice);
              },
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
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _duration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
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
                  presets: const [15, 30, 45, 60, 90],
                  onChanged: (minutes) {
                    setState(() {
                      _duration.text = minutes.toString();
                    });
                  },
                ),
              ],
            ),
            formGap,
            TextFormField(
              controller: _outcome,
              decoration: const InputDecoration(
                labelText: 'Outcome or evidence',
                hintText: 'Script runs against staging',
              ),
            ),
            formGap,
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
              ),
            ),
            formGap,
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _linkLabel,
                    decoration: const InputDecoration(
                      labelText: 'Link label (optional)',
                      hintText: 'PR #412',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _linkUrl,
                    decoration: const InputDecoration(
                      labelText: 'URL (optional)',
                    ),
                  ),
                ),
              ],
            ),
            formGap,
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
                hintText: 'migration, backfill',
              ),
            ),
            if (_error != null) FormError(message: _error!),
          ],
        ),
      ),
      actions: Row(
        children: [
          Text(
            widget.existing == null
                ? 'Entries are validated by the service.'
                : 'Editing entry · ${widget.existing!.localDate}',
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
            label: const Text('Save entry'),
          ),
        ],
      ),
    );
  }
}
