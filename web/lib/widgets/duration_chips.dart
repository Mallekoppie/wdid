import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class DurationChips extends StatelessWidget {
  const DurationChips({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.presets = const [15, 30, 45, 60],
    this.compact = false,
    this.enabled = true,
  });

  final int minutes;
  final ValueChanged<int> onChanged;
  final List<int> presets;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final preset in presets)
          ChoiceChip(
            label: Text('${preset}m'),
            selected: minutes == preset,
            onSelected: enabled ? (_) => onChanged(preset) : null,
            showCheckmark: false,
            labelPadding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
            visualDensity: VisualDensity.compact,
            selectedColor: scheme.primaryContainer,
            labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: tabularFigures,
            ),
          ),
      ],
    );
  }
}

class DurationField extends StatelessWidget {
  const DurationField({super.key, required this.controller, this.validator});

  final TextEditingController controller;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Duration',
        suffixText: 'min',
      ),
      validator: validator,
    );
  }
}

class AttributionIcon extends StatelessWidget {
  const AttributionIcon({super.key, required this.isInitiative});

  final bool isInitiative;

  @override
  Widget build(BuildContext context) {
    return Icon(
      isInitiative ? Icons.flag_outlined : Icons.category_outlined,
      size: 15,
    );
  }
}

const Widget formGap = SizedBox(height: AppSpacing.md);
