import 'dart:async';

import 'package:flutter/material.dart';

import '../data/settings_api.dart';
import '../models/app_settings.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/forms/export_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/settings/categories_panel.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _timezone;
  late final TextEditingController _dailyTarget;
  late final TextEditingController _longTimer;
  late final TextEditingController _defaultDuration;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _provider;
  late int _weekStart;
  late ReviewCadence _reviewCadence;
  late String _keySource;
  late bool _redactUrls;
  bool _initialized = false;
  bool _backingUp = false;
  bool _savingTime = false;
  bool _savingAi = false;
  String? _timeError;
  String? _timeField;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = AppStateScope.of(context).settings;
    _timezone = TextEditingController(text: settings.timezone);
    _dailyTarget = TextEditingController(
      text: settings.dailyTargetHours.toString(),
    );
    _longTimer = TextEditingController(text: '${settings.longTimerMinutes}');
    _defaultDuration = TextEditingController(
      text: '${settings.defaultDurationMinutes}',
    );
    _baseUrl = TextEditingController(text: settings.aiBaseUrl);
    _model = TextEditingController(text: settings.aiModel);
    _provider = TextEditingController(text: settings.aiProvider);
    _weekStart = settings.weekStart;
    _reviewCadence = settings.reviewCadence;
    _keySource = settings.aiKeySource;
    _redactUrls = settings.redactUrls;
  }

  @override
  void dispose() {
    _timezone.dispose();
    _dailyTarget.dispose();
    _longTimer.dispose();
    _defaultDuration.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _provider.dispose();
    super.dispose();
  }

  Future<void> _backupNow() async {
    final state = AppStateScope.read(context);
    setState(() => _backingUp = true);
    try {
      final status = await state.backupNow();
      if (!mounted) return;
      setState(() => _backingUp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup created · ${formatBytes(status.bytes)}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _backingUp = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Backup failed: $error')));
    }
  }

  Future<void> _saveTime() async {
    final state = AppStateScope.read(context);
    setState(() {
      _savingTime = true;
      _timeError = null;
      _timeField = null;
    });
    try {
      await state.saveSettings(
        state.settings.copyWith(
          timezone: _timezone.text.trim().isEmpty
              ? state.settings.timezone
              : _timezone.text.trim(),
          weekStart: _weekStart,
          dailyTargetHours:
              double.tryParse(_dailyTarget.text.trim()) ??
              state.settings.dailyTargetHours,
          reviewCadence: _reviewCadence,
          longTimerMinutes:
              int.tryParse(_longTimer.text.trim()) ??
              state.settings.longTimerMinutes,
          defaultDurationMinutes:
              int.tryParse(_defaultDuration.text.trim()) ??
              state.settings.defaultDurationMinutes,
        ),
      );
      if (!mounted) return;
      setState(() => _savingTime = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Time settings saved')));
    } on SettingsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _savingTime = false;
        _timeField = failure.field;
        _timeError = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingTime = false;
        _timeError = error.toString();
      });
    }
  }

  Future<void> _saveAi() async {
    final state = AppStateScope.read(context);
    setState(() => _savingAi = true);
    try {
      await state.saveSettings(
        state.settings.copyWith(
          aiProvider: _provider.text.trim(),
          aiBaseUrl: _baseUrl.text.trim(),
          aiModel: _model.text.trim(),
          aiKeySource: _keySource,
          redactUrls: _redactUrls,
        ),
      );
      if (!mounted) return;
      setState(() => _savingAi = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI settings saved')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingAi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save AI settings: $error')),
      );
    }
  }

  Future<void> _applyTheme(AppState state, ThemePreference preference) async {
    try {
      await state.setTheme(preference);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the theme: $error')),
      );
    }
  }

  Future<void> _applyDensity(AppState state, DensityPreference density) async {
    try {
      await state.setDensity(density);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the density: $error')),
      );
    }
  }

  void _showRestoreInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from backup'),
        content: const Text(
          'Restore is a host-level operation: the service verifies the selected '
          'snapshot, preserves the current database, then reopens and rebuilds '
          'indexes. The UI will call that endpoint once the backup contract is '
          'exposed by the service.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = state.settings;

    return ScreenBody(
      child: PageScaffold(
        maxWidth: 980,
        child: ListView(
          children: [
            Text('Settings', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              'Local instance · ${settings.version} · schema ${settings.schemaVersion}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: tabularFigures,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const CategoriesPanel(),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PanelHeader(
                    title: 'Data',
                    subtitle: 'Local-first storage and backups',
                    icon: Icons.storage_outlined,
                    trailing: Text(
                      settings.lastBackupAt == null
                          ? 'No backup yet'
                          : 'Last backup ${formatRelativeDay(settings.lastBackupAt!)} · '
                                '${formatBytes(settings.lastBackupBytes)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: settings.lastBackupAt == null
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ReadOnlyPath(
                    label: 'Database',
                    value: settings.databasePath,
                  ),
                  const SizedBox(height: 6),
                  _ReadOnlyPath(
                    label: 'Data directory',
                    value: settings.dataDir,
                  ),
                  const SizedBox(height: 6),
                  _ReadOnlyPath(
                    label: 'Backup directory',
                    value: settings.backupDir,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Every ${settings.backupIntervalHours}h · '
                    'keep ${settings.retentionCount} scheduled backups',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _showRestoreInfo,
                        icon: const Icon(Icons.restore, size: 15),
                        label: const Text('Restore…'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => showExportDialog(
                          context,
                          state: state,
                          start: DateTime(2000),
                          end: state.today,
                        ),
                        icon: const Icon(
                          Icons.file_download_outlined,
                          size: 15,
                        ),
                        label: const Text('Export all data'),
                      ),
                      FilledButton.icon(
                        onPressed: _backingUp ? null : _backupNow,
                        icon: _backingUp
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.backup_outlined, size: 15),
                        label: const Text('Backup now'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PanelHeader(
                    title: 'Time',
                    subtitle: 'Day grouping, targets, and timer rules',
                    icon: Icons.schedule,
                  ),
                  if (state.preferencesLoading) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  if (state.preferencesError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      state.preferencesError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _timezone,
                          decoration: InputDecoration(
                            labelText: 'Timezone',
                            hintText: 'Europe/Amsterdam',
                            errorText: _timeField == 'timezone'
                                ? _timeError
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: AppDropdown<int>(
                          value: _weekStart,
                          label: 'Week starts on',
                          items: [
                            for (var day = 1; day <= 7; day++)
                              DropdownMenuItem(
                                value: day,
                                child: Text(_weekdayNames[day - 1]),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _weekStart = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _dailyTarget,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Daily target',
                            suffixText: 'h',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: AppDropdown<ReviewCadence>(
                          value: _reviewCadence,
                          label: 'Personal review',
                          items: [
                            for (final cadence in ReviewCadence.values)
                              DropdownMenuItem(
                                value: cadence,
                                child: Text(cadence.label),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _reviewCadence = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _longTimer,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Long timer prompt',
                            suffixText: 'min',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _defaultDuration,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Default duration',
                            suffixText: 'min',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_timeError != null && _timeField != 'timezone') ...[
                    Text(
                      _timeError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Time settings are stored per account and apply to new entries.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton(
                        onPressed: _savingTime ? null : _saveTime,
                        child: _savingTime
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save time settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PanelHeader(
                    title: 'AI',
                    subtitle:
                        'OpenAI-compatible provider for check-in synthesis',
                    icon: Icons.auto_awesome_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _provider,
                          decoration: const InputDecoration(
                            labelText: 'Provider',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _baseUrl,
                          decoration: const InputDecoration(
                            labelText: 'Base URL',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _model,
                          decoration: const InputDecoration(labelText: 'Model'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AppDropdown<String>(
                          value: _keySource,
                          label: 'API key source',
                          items: const [
                            DropdownMenuItem(
                              value: 'environment',
                              child: Text('Environment variable (recommended)'),
                            ),
                            DropdownMenuItem(
                              value: 'stored',
                              child: Text('Stored setting'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _keySource = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: SwitchListTile(
                          value: _redactUrls,
                          onChanged: (value) =>
                              setState(() => _redactUrls = value),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Redact link URLs'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      'Prompt template preview',
                      style: theme.textTheme.labelMedium,
                    ),
                    subtitle: Text(
                      'Version ${settings.schemaVersion == 1 ? 'v1' : 'v1'} · reset is service-owned',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Text(
                          'You are summarising a software engineer\'s work for a '
                          'performance check-in.\n\n'
                          'Use only the data provided. Do not invent achievements, '
                          'metrics or names.\n\n'
                          'Produce highlights with measurable outcomes, initiative '
                          'progress, collaboration, time allocation observations, '
                          'risks and gaps, and three review bullets.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Keys are never shown in exports or logs.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton(
                        onPressed: _savingAi ? null : _saveAi,
                        child: _savingAi
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save AI settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PanelHeader(
                    title: 'Appearance',
                    subtitle: 'Theme and density apply immediately',
                    icon: Icons.palette_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.md,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 360,
                        child: SegmentedButton<ThemePreference>(
                          segments: [
                            for (final preference in ThemePreference.values)
                              ButtonSegment(
                                value: preference,
                                label: Text(preference.label),
                              ),
                          ],
                          selected: {settings.theme},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) {
                            unawaited(_applyTheme(state, selection.first));
                          },
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: SegmentedButton<DensityPreference>(
                          segments: [
                            for (final density in DensityPreference.values)
                              ButtonSegment(
                                value: density,
                                label: Text(density.label),
                              ),
                          ],
                          selected: {settings.density},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) {
                            unawaited(_applyDensity(state, selection.first));
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    height: settings.density == DensityPreference.compact
                        ? 36
                        : 48,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Billing migration',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Backfill script skeleton',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '42m',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontFeatures: tabularFigures,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PanelHeader(
                    title: 'About',
                    subtitle: 'Build and schema information',
                    icon: Icons.info_outline,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _AboutRow(
                    label: 'Application',
                    value: 'wdid ${settings.version}',
                  ),
                  _AboutRow(
                    label: 'Schema version',
                    value: '${settings.schemaVersion}',
                  ),
                  _AboutRow(label: 'License', value: settings.license),
                  _AboutRow(
                    label: 'Data adapter',
                    value: state.isDemo
                        ? 'Demo adapter (service contract pending)'
                        : 'Service connected',
                  ),
                  _AboutRow(
                    label: 'Auth',
                    value: 'Zitadel OIDC · invite-gated registration',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
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

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
