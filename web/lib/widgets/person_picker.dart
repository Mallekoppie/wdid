import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';

/// The shared person field: one-tap roster chips plus a searchable, free-text
/// field for a new name.
///
/// A person is a name, not an entity. Committing a name (a chip tap, Enter, or
/// the add action) returns it through [onSelected] and grows the account's
/// roster, so a name typed in any surface is available everywhere afterwards.
/// [onChanged] fires for every value change, including a chip tap; #4 uses
/// [onSelected] to tell a deliberate one-tap choice from keystrokes.
class PersonPicker extends StatefulWidget {
  const PersonPicker({
    super.key,
    this.controller,
    this.label = 'Person',
    this.hint,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.compact = false,
    this.validator,
    this.onChanged,
    this.onSelected,
    this.onSubmitted,
  });

  /// An external controller keeps the caller's existing save paths working. A
  /// private controller is owned and disposed when none is supplied.
  final TextEditingController? controller;

  final String label;
  final String? hint;
  final String? errorText;
  final bool enabled;
  final bool autofocus;

  /// Tighter chip styling for dense surfaces.
  final bool compact;

  final FormFieldValidator<String>? validator;

  /// Fires for every value change: typing, a chip tap, or a committed name.
  final ValueChanged<String>? onChanged;

  /// Fires only when a name is committed: a chip tap, Enter, or the add action.
  final ValueChanged<String>? onSelected;

  /// Fires after Enter in the new-name field, allowing callers to start or
  /// save in the same gesture.
  final ValueChanged<String>? onSubmitted;

  @override
  State<PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<PersonPicker> {
  late TextEditingController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(PersonPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _detachController();
    _attachController(widget.controller);
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

  /// Commits [raw] as the current person: normalises it, selects it, reports
  /// it, and grows the roster. Adding an existing name is a no-op.
  void _commit(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return;
    _setText(name);
    unawaited(AppStateScope.read(context).addSupportPerson(name));
    widget.onChanged?.call(name);
    widget.onSelected?.call(name);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visible.isNotEmpty) ...[
          _chipWrap(visible),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextFormField(
          controller: _controller,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          onFieldSubmitted: (value) {
            _commit(value);
            widget.onSubmitted?.call(value.trim());
          },
          onChanged: (value) {
            setState(() {});
            widget.onChanged?.call(value);
          },
          validator: widget.validator,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            errorText: widget.errorText,
            prefixIcon: const Icon(Icons.person_outline, size: 18),
            suffixIcon: IconButton(
              tooltip: 'Add person',
              onPressed: widget.enabled
                  ? () => _commit(_controller.text)
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
            selected: _isSelected(name),
            onSelected: widget.enabled ? (_) => _commit(name) : null,
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

  bool _isSelected(String name) =>
      _controller.text.trim().toLowerCase() == name.toLowerCase();
}
