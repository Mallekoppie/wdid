import 'package:flutter/material.dart';

import '../../models/link_ref.dart';
import '../../models/taxonomy.dart';
import '../../state/app_state.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import '../app_dropdown.dart';
import '../duration_chips.dart';
import 'dialog_frame.dart';

Future<Subcategory?> showProjectDialog(
  BuildContext context, {
  required AppState state,
}) {
  return showDialog<Subcategory>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ProjectDialog(state: state),
  );
}

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({required this.state});

  final AppState state;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _targetOutcome = TextEditingController();
  final _links = TextEditingController();
  late String _categoryId;
  SubcategoryStatus _status = SubcategoryStatus.active;
  int _progress = 0;
  DateTime? _targetDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.state.selectableInitiativeCategories.first.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _targetOutcome.dispose();
    _links.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _targetDate = picked);
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final category = widget.state.selectableInitiativeCategories.firstWhere(
      (candidate) => candidate.id == _categoryId,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.state.createProject(
        category: category,
        name: _name.text.trim(),
        description: _description.text.trim(),
        status: _status,
        progress: _progress,
        targetOutcome: _targetOutcome.text.trim(),
        targetDate: _targetDate == null ? '' : isoDate(_targetDate!),
        links: _parsedLinks(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not create the project. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories = widget.state.selectableInitiativeCategories;

    return DialogFrame(
      title: 'New project',
      subtitle: 'A project is a subcategory under an initiative category.',
      icon: Icons.workspaces_outline,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdown<String>(
              value: _categoryId,
              label: 'Category',
              icon: Icons.account_tree_outlined,
              items: [
                for (final category in categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _categoryId = value);
              },
            ),
            formGap,
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Billing migration',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Project name is required.'
                  : null,
            ),
            formGap,
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What this project covers',
              ),
            ),
            formGap,
            TextFormField(
              controller: _targetOutcome,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Target outcome (optional)',
                hintText: 'Invoice generation under 5 minutes',
              ),
            ),
            formGap,
            Row(
              children: [
                Expanded(
                  child: AppDropdown<SubcategoryStatus>(
                    value: _status,
                    label: 'Status',
                    items: [
                      for (final status in SubcategoryStatus.values)
                        if (status != SubcategoryStatus.archived)
                          DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                    ],
                    onChanged: (status) {
                      if (status != null) setState(() => _status = status);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTargetDate,
                    icon: const Icon(Icons.event_outlined, size: 15),
                    label: Text(
                      _targetDate == null
                          ? 'No target date'
                          : formatShortDate(_targetDate!),
                    ),
                  ),
                ),
                if (_targetDate != null)
                  IconButton(
                    tooltip: 'Clear target date',
                    onPressed: () => setState(() => _targetDate = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text('Progress', style: theme.textTheme.labelMedium),
                const Spacer(),
                Text(
                  '$_progress%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
            Slider(
              value: _progress.toDouble(),
              max: 100,
              divisions: 20,
              label: '$_progress%',
              onChanged: (value) => setState(() => _progress = value.round()),
            ),
            formGap,
            TextFormField(
              controller: _links,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Links (optional, one per line)',
                hintText: 'Epic | https://example.com/epic',
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
              'Progress is a manual judgment, not computed from hours.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
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
            label: const Text('Create project'),
          ),
        ],
      ),
    );
  }
}
