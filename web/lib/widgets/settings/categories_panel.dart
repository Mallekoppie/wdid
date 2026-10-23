import 'package:flutter/material.dart';

import '../../data/category_api.dart';
import '../../models/taxonomy.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../theme/app_tokens.dart';
import '../app_dropdown.dart';
import '../panel.dart';
import '../screen_states.dart';
import '../status_badge.dart';

/// Settings → Categories. The taxonomy is the source of attribution in every
/// capture form, so create, rename and archive actions update AppState's list
/// immediately after the service confirms them.
class CategoriesPanel extends StatelessWidget {
  const CategoriesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'Categories',
            subtitle: 'Reporting roles are chosen once and cannot change.',
            icon: Icons.account_tree_outlined,
            trailing: FilledButton.icon(
              onPressed: state.taxonomyLoading
                  ? null
                  : () => _editCategory(context, state),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New category'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (state.taxonomyLoading && state.categories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (state.taxonomyError != null && state.categories.isEmpty)
            _InlineError(
              message: state.taxonomyError!,
              onRetry: state.loadTaxonomy,
            )
          else if (state.categories.isEmpty)
            EmptyState(
              compact: true,
              icon: Icons.account_tree_outlined,
              title: 'No categories yet',
              message: 'Create a category with a reporting role before capturing work.',
              action: FilledButton(
                onPressed: () => _editCategory(context, state),
                child: const Text('Create category'),
              ),
            )
          else ...[
            if (state.taxonomyError != null)
              _InlineError(
                message: state.taxonomyError!,
                onRetry: state.loadTaxonomy,
              ),
            for (var index = 0; index < state.categories.length; index++) ...[
              if (index > 0) const Divider(height: 1),
              _CategoryTile(
                category: state.categories[index],
                subcategories: state.subcategoriesFor(
                  state.categories[index].id,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    AppState state, {
    Category? category,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _CategoryDialog(state: state, category: category),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            category == null ? 'Category created' : 'Category renamed',
          ),
        ),
      );
    }
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.subcategories});

  final Category category;
  final List<Subcategory> subcategories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = AppStateScope.read(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: category.color.isEmpty
                      ? scheme.primary
                      : _parseColor(category.color, scheme.primary),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  category.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: category.archived
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                    decoration: category.archived
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(
                label: category.role.label,
                color: switch (category.role) {
                  CategoryRole.initiative => scheme.primary,
                  CategoryRole.support => scheme.tertiary,
                  CategoryRole.other => scheme.onSurfaceVariant,
                },
              ),
              if (category.archived) ...[
                const SizedBox(width: 6),
                StatusBadge(
                  label: 'Archived',
                  color: scheme.onSurfaceVariant,
                  background: scheme.surfaceContainerHighest,
                ),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Category actions',
                onSelected: (action) =>
                    _runCategoryAction(context, state, action),
                itemBuilder: (context) => [
                  if (!category.archived)
                    const PopupMenuItem(
                      value: 'subcategory',
                      child: Text('New subcategory'),
                    ),
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(category.archived ? 'Unarchive' : 'Archive'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          if (subcategories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 17, top: 2, bottom: 2),
              child: Text(
                category.archived
                    ? 'Archived category. Historical entries keep their attribution.'
                    : 'No subcategories.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 17, top: 4),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                children: [
                  for (final subcategory in subcategories)
                    _SubcategoryChip(
                      category: category,
                      subcategory: subcategory,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _runCategoryAction(
    BuildContext context,
    AppState state,
    String action,
  ) async {
    try {
      switch (action) {
        case 'subcategory':
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) =>
                _SubcategoryDialog(state: state, category: category),
          );
          if (ok == true && context.mounted) {
            _toast(context, 'Subcategory created');
          }
        case 'rename':
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) =>
                _CategoryDialog(state: state, category: category),
          );
          if (ok == true && context.mounted) {
            _toast(context, 'Category renamed');
          }
        case 'archive':
          await state.archiveCategory(category, archived: !category.archived);
          if (!context.mounted) return;
          _toast(
            context,
            category.archived ? 'Category unarchived' : 'Category archived',
          );
        case 'delete':
          final confirmed = await _confirm(
            context,
            title: 'Delete “${category.name}”?',
            message:
                'A category referenced by existing work cannot be deleted; '
                'archive it instead.',
          );
          if (!confirmed) return;
          await state.deleteCategory(category);
          if (!context.mounted) return;
          _toast(context, 'Category deleted');
      }
    } on CategoryFailure catch (error) {
      if (context.mounted) _toast(context, error.message, isError: true);
    } catch (error) {
      if (context.mounted) _toast(context, error.toString(), isError: true);
    }
  }
}

class _SubcategoryChip extends StatelessWidget {
  const _SubcategoryChip({required this.category, required this.subcategory});

  final Category category;
  final Subcategory subcategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = AppStateScope.read(context);
    final archived = subcategory.archived;

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 3, 3, 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            subcategory.name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: archived ? scheme.onSurfaceVariant : scheme.onSurface,
              decoration: archived ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            archived ? 'Archived' : subcategory.status.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            iconSize: 15,
            tooltip: 'Subcategory actions',
            onSelected: (action) => _runAction(context, state, action),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                value: 'archive',
                child: Text(archived ? 'Unarchive' : 'Archive'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    AppState state,
    String action,
  ) async {
    try {
      switch (action) {
        case 'rename':
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => _SubcategoryDialog(
              state: state,
              category: category,
              subcategory: subcategory,
            ),
          );
          if (ok == true && context.mounted) {
            _toast(context, 'Subcategory renamed');
          }
        case 'archive':
          await state.archiveSubcategory(
            subcategory,
            archived: !subcategory.archived,
          );
          if (!context.mounted) return;
          _toast(
            context,
            subcategory.archived
                ? 'Subcategory unarchived'
                : 'Subcategory archived',
          );
        case 'delete':
          final confirmed = await _confirm(
            context,
            title: 'Delete “${subcategory.name}”?',
            message:
                'A subcategory referenced by existing work cannot be deleted; '
                'archive it instead.',
          );
          if (!confirmed) return;
          await state.deleteSubcategory(subcategory);
          if (!context.mounted) return;
          _toast(context, 'Subcategory deleted');
      }
    } on CategoryFailure catch (error) {
      if (context.mounted) _toast(context, error.message, isError: true);
    } catch (error) {
      if (context.mounted) _toast(context, error.toString(), isError: true);
    }
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.state, this.category});

  final AppState state;
  final Category? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name;
  late final TextEditingController _color;
  CategoryRole? _role;
  bool _saving = false;
  String? _error;
  String? _field;

  bool get _creating => widget.category == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _color = TextEditingController(text: widget.category?.color ?? '');
    _role = widget.category?.role;
  }

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() {
        _field = 'name';
        _error = 'Name is required.';
      });
      return;
    }
    if (_creating && _role == null) {
      setState(() {
        _field = 'role';
        _error = 'Choose a reporting role.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _field = null;
    });
    try {
      if (_creating) {
        await widget.state.createCategory(
          name: name,
          role: _role!,
          color: _color.text.trim(),
        );
      } else {
        await widget.state.renameCategory(widget.category!, name);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on CategoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _field = failure.field;
        _error = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_creating ? 'New category' : 'Rename category'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _field == 'name' ? _error : null,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_creating) ...[
              AppDropdown<CategoryRole>(
                value: _role,
                label: 'Reporting role (fixed after creation)',
                hint: 'Choose a role',
                items: [
                  for (final role in CategoryRole.values)
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _color,
                decoration: InputDecoration(
                  labelText: 'Colour (optional)',
                  hintText: '#00696D',
                  errorText: _field == 'color' ? _error : null,
                ),
              ),
            ] else
              Text(
                'Role: ${widget.category!.role.label}. Roles cannot change.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (_error != null &&
                _field != 'name' &&
                _field != 'color' &&
                _field != 'role') ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_creating ? 'Create' : 'Rename'),
        ),
      ],
    );
  }
}

class _SubcategoryDialog extends StatefulWidget {
  const _SubcategoryDialog({
    required this.state,
    required this.category,
    this.subcategory,
  });

  final AppState state;
  final Category category;
  final Subcategory? subcategory;

  @override
  State<_SubcategoryDialog> createState() => _SubcategoryDialogState();
}

class _SubcategoryDialogState extends State<_SubcategoryDialog> {
  late final TextEditingController _name;
  late SubcategoryStatus _status;
  bool _saving = false;
  String? _error;
  String? _field;

  bool get _creating => widget.subcategory == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.subcategory?.name ?? '');
    _status = widget.subcategory?.status ?? SubcategoryStatus.active;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() {
        _field = 'name';
        _error = 'Name is required.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _field = null;
    });
    try {
      if (_creating) {
        await widget.state.createSubcategory(
          category: widget.category,
          name: name,
          status: _status,
        );
      } else {
        await widget.state.saveSubcategory(
          widget.subcategory!.copyWith(name: name, status: _status),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on CategoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _field = failure.field;
        _error = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_creating ? 'New subcategory' : 'Rename subcategory'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.category.name,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _field == 'name' ? _error : null,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppDropdown<SubcategoryStatus>(
              value: _status,
              label: 'Status',
              items: [
                for (final status in SubcategoryStatus.values)
                  DropdownMenuItem(value: status, child: Text(status.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
            if (_error != null && _field != 'name') ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_creating ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: scheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

void _toast(BuildContext context, String message, {bool isError = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
    ),
  );
}

Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  if (hex.length != 6) return fallback;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return fallback;
  return Color(0xFF000000 | parsed);
}
