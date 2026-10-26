import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/people.dart';

/// The shared people field: roster chips, a removable selected list, and a
/// free-text field for a new name.
///
/// A person is a name, not an entity. In its default mode the roster chips
/// toggle membership and the committed names come back as an ordered list
/// through [onChanged]. Committing a new name also grows the account's roster,
/// so a name typed in any surface is available everywhere afterwards. A batch
/// adds the name once.
///
/// [oneTap] keeps a single-tap surface (Support now, the header picker) working:
/// a roster chip commits exactly that one name through [onCommitted] instead of
/// toggling membership. Those surfaces reach multi-select through
/// [showPeoplePickerDialog].
class PersonPicker extends StatefulWidget {
  const PersonPicker({
    super.key,
    this.selected = const [],
    this.onChanged,
    this.textController,
    this.label = 'Person',
    this.hint,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.compact = false,
    this.oneTap = false,
    this.onCommitted,
    this.onSubmitted,
  });

  /// The ordered names currently selected. The picker is controlled: every
  /// change is reported through [onChanged] and the caller supplies the new
  /// list back.
  final List<String> selected;

  /// Fires for every selection change: a chip toggle, a committed name, or a
  /// removed selected chip.
  final ValueChanged<List<String>>? onChanged;

  /// The free-text field's controller. A caller that saves from outside the
  /// picker can include uncommitted text with [peopleIncludingPending], so a
  /// typed name is never silently dropped.
  final TextEditingController? textController;

  final String label;
  final String? hint;
  final String? errorText;
  final bool enabled;
  final bool autofocus;

  /// Tighter chip styling for dense surfaces.
  final bool compact;

  /// When true, a roster chip commits exactly that one name through
  /// [onCommitted] instead of toggling membership. Used by the one-tap support
  /// surfaces, which must start a one-person timer from a single tap.
  final bool oneTap;

  /// Fires with the resulting list when a name is committed: a one-tap chip,
  /// Enter in the new-name field, or the add action.
  final ValueChanged<List<String>>? onCommitted;

  /// Fires after Enter in the new-name field, allowing callers to start or
  /// save in the same gesture.
  final ValueChanged<List<String>>? onSubmitted;

  @override
  State<PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<PersonPicker> {
  late TextEditingController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _attachController(widget.textController);
  }

  @override
  void didUpdateWidget(PersonPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController == widget.textController) return;
    _detachController();
    _attachController(widget.textController);
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  void _attachController(TextEditingController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  void _detachController() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _setText(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  bool _isSelected(String name) => widget.selected.any(
    (selected) => selected.toLowerCase() == name.toLowerCase(),
  );

  /// Commits [raw] by appending it to the selection and returns the resulting
  /// ordered list. A duplicate keeps the first spelling and adds nothing.
  /// Returns null when the input is empty.
  List<String>? _commit(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return null;
    final next = normalizePeople([...widget.selected, name]);
    _setText('');
    // Grow the roster once for this batch. The state de-duplicates, so an
    // existing name is a no-op.
    unawaited(AppStateScope.read(context).addSupportPerson(name));
    if (!_sameNames(next, widget.selected)) {
      widget.onChanged?.call(next);
      widget.onCommitted?.call(next);
    }
    return next;
  }

  void _toggle(String name) {
    final next = _isSelected(name)
        ? [
            for (final selected in widget.selected)
              if (selected.toLowerCase() != name.toLowerCase()) selected,
          ]
        : normalizePeople([...widget.selected, name]);
    widget.onChanged?.call(next);
  }

  void _tapChip(String name) {
    if (widget.oneTap) {
      final next = [name];
      widget.onChanged?.call(next);
      widget.onCommitted?.call(next);
      return;
    }
    _toggle(name);
  }

  void _remove(String name) {
    widget.onChanged?.call([
      for (final selected in widget.selected)
        if (selected.toLowerCase() != name.toLowerCase()) selected,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final roster = AppStateScope.of(context).supportPeople;
    final query = _controller.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? roster
        : [
            for (final name in roster)
              if (name.toLowerCase().contains(query)) name,
          ];
    // Selected names the roster chips cannot show (a new name, or one filtered
    // out by the query) still need a visible way to be removed.
    final hiddenSelected = [
      for (final name in widget.selected)
        if (!visible.any(
          (candidate) => candidate.toLowerCase() == name.toLowerCase(),
        ))
          name,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visible.isNotEmpty) ...[
          _chipWrap(visible),
          if (hiddenSelected.isNotEmpty) const SizedBox(height: 5),
        ],
        if (hiddenSelected.isNotEmpty) ...[
          _selectedWrap(hiddenSelected),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextFormField(
          controller: _controller,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          onFieldSubmitted: (value) {
            final committed = _commit(value);
            if (committed != null) widget.onSubmitted?.call(committed);
          },
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            errorText: widget.errorText,
            prefixIcon: const Icon(Icons.person_outline, size: 18),
            suffixIcon: IconButton(
              tooltip: 'Add person',
              onPressed: widget.enabled
                  ? () {
                      final committed = _commit(_controller.text);
                      if (committed != null) {
                        widget.onSubmitted?.call(committed);
                      }
                    }
                  : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chipWrap(List<String> names) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final name in names)
          ChoiceChip(
            label: Text(name),
            selected: !widget.oneTap && _isSelected(name),
            onSelected: widget.enabled ? (_) => _tapChip(name) : null,
            showCheckmark: false,
            labelPadding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 4 : 6,
            ),
            visualDensity: VisualDensity.compact,
            selectedColor: Theme.of(context).colorScheme.primaryContainer,
            labelStyle: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
      ],
    );
  }

  Widget _selectedWrap(List<String> names) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final name in names)
          InputChip(
            label: Text(name),
            onDeleted: widget.enabled ? () => _remove(name) : null,
            deleteButtonTooltipMessage: 'Remove $name',
            deleteIcon: const Icon(Icons.close, size: 14),
            visualDensity: VisualDensity.compact,
            labelPadding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 4 : 6,
            ),
            labelStyle: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

bool _sameNames(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index].toLowerCase() != second[index].toLowerCase()) {
      return false;
    }
  }
  return true;
}

/// The selected names plus any free text typed but not committed yet. Save
/// paths use this so clicking a form's save button after typing a name keeps
/// that name.
List<String> peopleIncludingPending(
  List<String> selected,
  TextEditingController? controller,
) => normalizePeople([...selected, if (controller != null) controller.text]);

/// Asks for an ordered list of people. Multi-select is reachable from every
/// support surface through this dialog; the caller decides what to do with the
/// chosen names (start a timer, save an entry, ...).
Future<List<String>?> showPeoplePickerDialog(
  BuildContext context, {
  String title = 'Support several people',
  String actionLabel = 'Start support',
  String hint = 'Add a person',
  List<String> initial = const [],
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) => _PeoplePickerDialog(
      title: title,
      actionLabel: actionLabel,
      hint: hint,
      initial: initial,
    ),
  );
}

class _PeoplePickerDialog extends StatefulWidget {
  const _PeoplePickerDialog({
    required this.title,
    required this.actionLabel,
    required this.hint,
    required this.initial,
  });

  final String title;
  final String actionLabel;
  final String hint;
  final List<String> initial;

  @override
  State<_PeoplePickerDialog> createState() => _PeoplePickerDialogState();
}

class _PeoplePickerDialogState extends State<_PeoplePickerDialog> {
  late List<String> _selected = normalizePeople(widget.initial);
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The Start button is enabled by typed text too, not only a committed
    // name, so it must rebuild while the user types.
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _textController
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  List<String> get _people =>
      peopleIncludingPending(_selected, _textController);

  void _confirm() {
    final people = _people;
    if (people.isEmpty) return;
    // A name typed but never committed still becomes part of the roster.
    unawaited(AppStateScope.read(context).addSupportPeople(people));
    Navigator.of(context).pop(people);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: PersonPicker(
          selected: _selected,
          textController: _textController,
          autofocus: true,
          hint: widget.hint,
          onChanged: (people) => setState(() => _selected = people),
          onSubmitted: (_) => _confirm(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _people.isEmpty ? null : _confirm,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
