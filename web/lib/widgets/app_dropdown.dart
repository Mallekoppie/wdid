import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A compact, controlled dropdown used across forms and filters.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.icon,
    this.enabled = true,
    this.isDense = true,
    this.expanded = true,
    this.errorText,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;
  final IconData? icon;
  final bool enabled;
  final bool isDense;
  final bool expanded;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 30,
          minHeight: 20,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.any((item) => item.value == value) ? value : null,
          items: items,
          onChanged: enabled ? onChanged : null,
          isDense: isDense,
          isExpanded: expanded,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.input),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
