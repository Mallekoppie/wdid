import 'package:flutter/material.dart';

/// One choice in a [SearchableDropdown].
class SearchableDropdownOption<T> {
  const SearchableDropdownOption({
    required this.value,
    required this.label,
    this.pinned = false,
  });

  /// The selected value. It must be non-null; use a sentinel such as an empty
  /// string for an explicit "none" choice.
  final T value;
  final String label;

  /// Pinned options stay visible while the user filters and are not counted
  /// as matches. Use it for entries such as "No subcategory".
  final bool pinned;
}

/// A compact, searchable selector. Typing filters the options case-insensitively
/// by substring, keeping the caller's order. A pinned option stays visible.
///
/// The field is a search-first combobox: tapping it opens the menu and selects
/// the current label, so the first keystroke starts the query.
class SearchableDropdown<T> extends StatefulWidget {
  const SearchableDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.hint,
    this.errorText,
    this.enabled = true,
    this.menuMinWidth = 240,
  });

  final T? value;
  final List<SearchableDropdownOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool enabled;

  /// Minimum width of the open menu. The field itself follows its parent.
  final double menuMinWidth;

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late List<DropdownMenuEntry<_Choice<T>>> _entries;

  /// The last value this widget reported or received, used to restore the
  /// field text when the user abandons a search.
  T? _selectedValue;

  @override
  void initState() {
    super.initState();
    _entries = _buildEntries();
    _selectedValue = widget.value;
    _controller = TextEditingController(text: _labelFor(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(SearchableDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameOptions(oldWidget.options, widget.options)) {
      _entries = _buildEntries();
      if (!_focusNode.hasFocus) {
        _setText(_labelFor(_selectedValue));
      }
    }
    if (widget.value != oldWidget.value) {
      _selectedValue = widget.value;
      _setText(_labelFor(widget.value));
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  List<DropdownMenuEntry<_Choice<T>>> _buildEntries() => [
    for (final option in widget.options)
      DropdownMenuEntry<_Choice<T>>(
        value: _Choice<T>(
          value: option.value,
          label: option.label,
          pinned: option.pinned,
        ),
        label: option.label,
      ),
  ];

  String _labelFor(T? value) {
    for (final option in widget.options) {
      if (option.value == value) return option.label;
    }
    return '';
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      // Select the current label so the first keystroke replaces it with a
      // query instead of appending to it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.hasFocus) return;
        final text = _controller.text;
        if (text.isEmpty) return;
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      });
      return;
    }
    // Leaving the field without choosing restores the selected label.
    _resetText();
  }

  List<DropdownMenuEntry<_Choice<T>>> _filter(
    List<DropdownMenuEntry<_Choice<T>>> entries,
    String query,
  ) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return entries;

    final matches = entries
        .where(
          (entry) =>
              entry.value.pinned || entry.label.toLowerCase().contains(needle),
        )
        .toList();

    final hasRealMatch = matches.any((entry) => !entry.value.pinned);
    if (!hasRealMatch) {
      matches.add(
        DropdownMenuEntry<_Choice<T>>(
          value: _Choice<T>(label: 'No matches', sentinel: true),
          label: 'No matches',
          enabled: false,
        ),
      );
    }
    return matches;
  }

  void _handleSelected(_Choice<T>? choice) {
    if (choice == null || choice.sentinel) return;
    final value = choice.value;
    if (value == null) return;

    _selectedValue = value;
    _setText(choice.label);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.inputDecorationTheme;

    return TapRegion(
      onTapOutside: (_) => _resetText(),
      child: DropdownMenu<_Choice<T>>(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        requestFocusOnTap: true,
        enableFilter: true,
        filterCallback: _filter,
        // The menu needs room for long labels; expandedInsets lets the field
        // itself follow the available width instead.
        width: widget.menuMinWidth,
        expandedInsets: EdgeInsets.zero,
        menuHeight: 320,
        label: widget.label == null ? null : Text(widget.label!),
        hintText: widget.hint,
        errorText: widget.errorText,
        leadingIcon: Icon(
          Icons.search,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        showTrailingIcon: false,
        textStyle: theme.textTheme.bodyMedium,
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: base.filled,
          fillColor: base.fillColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          border: base.border,
          enabledBorder: base.enabledBorder,
          focusedBorder: base.focusedBorder,
          errorBorder: base.errorBorder,
          focusedErrorBorder: base.focusedErrorBorder,
          hintStyle: base.hintStyle,
          labelStyle: base.labelStyle,
          floatingLabelStyle: base.floatingLabelStyle,
        ),
        dropdownMenuEntries: _entries,
        onSelected: _handleSelected,
      ),
    );
  }

  void _resetText() {
    if (!mounted) return;
    final expected = _labelFor(_selectedValue);
    if (_controller.text != expected) _setText(expected);
  }

  static bool _sameOptions<T>(
    List<SearchableDropdownOption<T>> left,
    List<SearchableDropdownOption<T>> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].value != right[index].value ||
          left[index].label != right[index].label ||
          left[index].pinned != right[index].pinned) {
        return false;
      }
    }
    return true;
  }
}

class _Choice<T> {
  const _Choice({
    this.value,
    required this.label,
    this.pinned = false,
    this.sentinel = false,
  });

  final T? value;
  final String label;
  final bool pinned;
  final bool sentinel;

  @override
  bool operator ==(Object other) =>
      other is _Choice<T> &&
      other.value == value &&
      other.label == label &&
      other.pinned == pinned &&
      other.sentinel == sentinel;

  @override
  int get hashCode => Object.hash(value, label, pinned, sentinel);
}
