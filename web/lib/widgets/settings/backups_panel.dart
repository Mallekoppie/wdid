import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/settings_api.dart';
import '../../state/app_state.dart';
import '../../state/app_state_scope.dart';
import '../../theme/app_tokens.dart';
import '../../utils/time_utils.dart';
import '../forms/export_dialog.dart';
import '../panel.dart';

/// Settings → Data & backups. The database paths and backup preferences are
/// read-only here; snapshots, `Backup now` and `Restore` are instance-wide and
/// therefore admin-only. A normal account keeps the paths and export but sees
/// an explanatory read-only state instead of the backup controls.
class BackupsPanel extends StatefulWidget {
  const BackupsPanel({super.key});

  @override
  State<BackupsPanel> createState() => _BackupsPanelState();
}

class _BackupsPanelState extends State<BackupsPanel> {
  bool _loaded = false;
  bool _backingUp = false;
  bool _restoring = false;
  String? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final state = AppStateScope.of(context);
    if (state.canManageBackups) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(state.loadBackups());
      });
    }
  }

  Future<void> _backupNow(AppState state) async {
    setState(() => _backingUp = true);
    try {
      final status = await state.backupNow();
      if (!mounted) return;
      setState(() {
        _backingUp = false;
        _selected = state.backups.isEmpty ? null : state.backups.first.name;
      });
      _toast(
        context,
        'Backup created · ${formatBytes(status.lastBackupSizeBytes)}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _backingUp = false);
      _toast(context, 'Backup failed: $error', isError: true);
    }
  }

  Future<void> _restore(AppState state, BackupSnapshot snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restore ${snapshot.name}?'),
        content: const Text(
          'The service verifies this snapshot, copies the current database to '
          'a pre-restore file, replaces the database, reopens the store and '
          'rebuilds its indexes. Work recorded after this snapshot will not be '
          'in the restored database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // A successful restore reloads every server-owned view, which briefly
    // replaces this panel. Keep the messenger so the confirmation survives
    // that rebuild.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _restoring = true);
    try {
      final result = await state.restoreBackup(snapshot.name);
      final saved = result.preRestorePath.isEmpty
          ? ''
          : ' · previous database saved';
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Restored ${snapshot.name}$saved')),
        );
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _selected = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _restoring = false);
      _toast(context, 'Restore failed: $error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = state.settings;
    final status = state.backupStatus;
    final lastBackupAt = status?.lastBackupAt ?? settings.lastBackupAt;
    final lastBackupBytes =
        status?.lastBackupSizeBytes ?? settings.lastBackupBytes;
    final overdue = status?.overdue ?? settings.lastBackupAt == null;
    final intervalHours =
        status?.backupIntervalHours ?? settings.backupIntervalHours;
    final retention = status?.backupRetention ?? settings.retentionCount;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: 'Data & backups',
            subtitle: 'Local-first storage, snapshots and recovery',
            icon: Icons.backup_outlined,
            trailing: Text(
              lastBackupAt == null
                  ? 'No backup yet'
                  : 'Last backup ${formatRelativeDay(lastBackupAt)} · '
                        '${formatBytes(lastBackupBytes)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: lastBackupAt == null
                    ? scheme.error
                    : scheme.onSurfaceVariant,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ReadOnlyPath(label: 'Database', value: settings.databasePath),
          const SizedBox(height: 6),
          _ReadOnlyPath(label: 'Data directory', value: settings.dataDir),
          const SizedBox(height: 6),
          _ReadOnlyPath(label: 'Backup directory', value: settings.backupDir),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Every ${intervalHours}h · keep $retention scheduled backups',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!state.canManageBackups) ...[
            const SizedBox(height: AppSpacing.md),
            const _AdminOnlyNotice(),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => showExportDialog(
                  context,
                  state: state,
                  start: DateTime(2000),
                  end: state.today,
                ),
                icon: const Icon(Icons.file_download_outlined, size: 15),
                label: const Text('Export all data'),
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            if (state.backupsLoading && state.backups.isEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (state.backupsError != null)
              _InlineError(
                message: state.backupsError!,
                onRetry: () => state.loadBackups(force: true),
              ),
            if (overdue)
              _OverdueNotice(
                intervalHours: intervalHours,
                lastBackupAt: lastBackupAt,
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text('Snapshots', style: theme.textTheme.titleSmall),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${state.backups.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (state.backups.isEmpty && !state.backupsLoading)
              Text(
                'No backups yet. Take a backup before changing data.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else if (state.backups.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 232),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: state.backups.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final snapshot = state.backups[index];
                    return _SnapshotTile(
                      snapshot: snapshot,
                      selected: _selected == snapshot.name,
                      enabled: !_restoring && !_backingUp,
                      onSelected: () =>
                          setState(() => _selected = snapshot.name),
                    );
                  },
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || _selected == null
                      ? null
                      : () {
                          final index = state.backups.indexWhere(
                            (item) => item.name == _selected,
                          );
                          if (index < 0) return;
                          unawaited(_restore(state, state.backups[index]));
                        },
                  icon: const Icon(Icons.restore, size: 15),
                  label: const Text('Restore selected'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showExportDialog(
                    context,
                    state: state,
                    start: DateTime(2000),
                    end: state.today,
                  ),
                  icon: const Icon(Icons.file_download_outlined, size: 15),
                  label: const Text('Export all data'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => unawaited(_backupNow(state)),
                  icon: _backingUp
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined, size: 15),
                  label: const Text('Backup now'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool get _busy => _backingUp || _restoring;
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    required this.snapshot,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final BackupSnapshot snapshot;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      onTap: enabled ? onSelected : null,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        snapshot.name,
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${snapshot.manual ? 'Manual' : 'Scheduled'} · '
        '${formatRelativeDay(snapshot.createdAt)} · '
        '${formatBytes(snapshot.sizeBytes)}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AdminOnlyNotice extends StatelessWidget {
  const _AdminOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Backups cover the whole instance and are managed by an '
              'administrator. Only an administrator can list, take or restore '
              'a backup. Your own data and exports stay available here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverdueNotice extends StatelessWidget {
  const _OverdueNotice({required this.intervalHours, this.lastBackupAt});

  final int intervalHours;
  final DateTime? lastBackupAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = lastBackupAt == null
        ? 'No backup has been taken yet. Take one now to protect this workspace.'
        : 'The last backup was ${formatRelativeDay(lastBackupAt!)}; scheduled '
              'backups run every ${intervalHours}h.';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Backup overdue. $message',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
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

class _ReadOnlyPath extends StatelessWidget {
  const _ReadOnlyPath({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
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
