import 'dart:async';

import 'package:flutter/material.dart';

import '../data/settings_api.dart';
import '../models/app_settings.dart';
import '../models/check_in.dart';
import '../models/enums.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';
import '../state/auth_state.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/settings/backups_panel.dart';
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
  const SettingsScreen({super.key, this.auth});

  /// The sign-in state, used to describe the deployment in About. Optional so
  /// screens can be embedded without an auth gate in tests.
  final AuthState? auth;

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
  late final TextEditingController _apiKey;
  late int _weekStart;
  late ReviewCadence _reviewCadence;
  late bool _redactUrls;
  late AIProviderPreset _aiPreset;
  bool _initialized = false;
  bool _savingTime = false;
  bool _savingAi = false;
  bool _savingKey = false;
  bool _clearingKey = false;
  String? _timeError;
  String? _timeField;
  String? _keyError;

  // An editor only resyncs from the service while the user has not changed it,
  // so a delayed preferences load cannot overwrite a draft.
  bool _timeDirty = false;
  bool _aiDirty = false;
  bool _syncing = false;

  CheckInPromptVariant _previewVariant = CheckInPromptVariant.managerOneOnOne;
  PromptTemplate? _previewTemplate;
  String? _previewError;
  bool _previewLoading = false;

  @override
  void initState() {
    super.initState();
    widget.auth?.addListener(_refreshAuthDescription);
    // A session injected without going through the login screen still needs
    // the auth config so About can name the deployment mode.
    if (widget.auth != null && widget.auth!.config == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.auth!.loadConfig());
      });
    }
  }

  void _refreshAuthDescription() {
    if (mounted) setState(() {});
  }

  String get _authDescription {
    final config = widget.auth?.config;
    if (config == null) return 'Loading…';
    if (config.isLocal) return 'Local single-user · optional password';
    if (config.oidcEnabled) {
      return 'Zitadel OIDC · invite-gated registration';
    }
    return 'Email/password · invite-gated registration';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.of(context);
    if (!_initialized) {
      _initialized = true;
      _timezone = TextEditingController(text: state.settings.timezone);
      _dailyTarget = TextEditingController(
        text: state.settings.dailyTargetHours.toString(),
      );
      _longTimer = TextEditingController(
        text: '${state.settings.longTimerMinutes}',
      );
      _defaultDuration = TextEditingController(
        text: '${state.settings.defaultDurationMinutes}',
      );
      _baseUrl = TextEditingController(text: state.settings.aiBaseUrl);
      _model = TextEditingController(text: state.settings.aiModel);
      _apiKey = TextEditingController();
      for (final controller in [
        _timezone,
        _dailyTarget,
        _longTimer,
        _defaultDuration,
      ]) {
        controller.addListener(_markTimeDirty);
      }
      for (final controller in [_baseUrl, _model]) {
        controller.addListener(_markAiDirty);
      }
      _weekStart = state.settings.weekStart;
      _reviewCadence = state.settings.reviewCadence;
      _redactUrls = state.settings.redactUrls;
      _aiPreset = AIProviderPreset.forBaseUrl(state.settings.aiBaseUrl);
      if (state.hasSummaryService) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadPromptTemplate());
        });
      }
      return;
    }

    // Preferences load asynchronously (and can be retried after a transient
    // failure). When they arrive, refresh only the editors the user has not
    // touched; otherwise Save would write defaults over stored values.
    _applySettings(state.settings);
  }

  void _markTimeDirty() {
    if (!_syncing) _timeDirty = true;
  }

  void _markAiDirty() {
    if (!_syncing) _aiDirty = true;
  }

  void _applySettings(AppSettings settings) {
    _syncing = true;
    try {
      if (!_timeDirty) {
        _setText(_timezone, settings.timezone);
        _setText(_dailyTarget, settings.dailyTargetHours.toString());
        _setText(_longTimer, '${settings.longTimerMinutes}');
        _setText(_defaultDuration, '${settings.defaultDurationMinutes}');
        _weekStart = settings.weekStart;
        _reviewCadence = settings.reviewCadence;
      }
      if (!_aiDirty) {
        _setText(_baseUrl, settings.aiBaseUrl);
        _setText(_model, settings.aiModel);
        _redactUrls = settings.redactUrls;
        _aiPreset = AIProviderPreset.forBaseUrl(settings.aiBaseUrl);
      }
    } finally {
      _syncing = false;
    }
  }

  void _setText(TextEditingController controller, String value) {
    if (controller.text != value) controller.text = value;
  }

  @override
  void dispose() {
    widget.auth?.removeListener(_refreshAuthDescription);
    _timezone.dispose();
    _dailyTarget.dispose();
    _longTimer.dispose();
    _defaultDuration.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _saveTime() async {
    final state = AppStateScope.read(context);
    if (state.preferencesError != null || state.preferencesLoading) {
      setState(() {
        _timeError =
            'Preferences could not be loaded. Retry before saving so stored '
            'values are not replaced.';
        _timeField = null;
      });
      return;
    }
    setState(() {
      _savingTime = true;
      _timeError = null;
      _timeField = null;
    });
    try {
      final saved = await state.saveSettings(
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
      setState(() {
        _savingTime = false;
        _timeDirty = false;
      });
      _applySettings(saved);
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
    if (state.preferencesError != null || state.preferencesLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preferences could not be loaded. Retry before saving so stored '
            'values are not replaced.',
          ),
        ),
      );
      return;
    }
    setState(() => _savingAi = true);
    try {
      // The key has its own write-only actions; the settings message has no
      // field for it.
      final saved = await state.saveSettings(
        state.settings.copyWith(
          aiBaseUrl: _baseUrl.text.trim(),
          aiModel: _model.text.trim(),
          redactUrls: _redactUrls,
        ),
      );
      if (!mounted) return;
      setState(() {
        _savingAi = false;
        _aiDirty = false;
      });
      _applySettings(saved);
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

  Future<void> _saveKey() async {
    final state = AppStateScope.read(context);
    final apiKey = _apiKey.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _keyError = 'Enter an API key first.');
      return;
    }
    setState(() {
      _savingKey = true;
      _keyError = null;
    });
    try {
      await state.setAiApiKey(apiKey);
      if (!mounted) return;
      _apiKey.clear();
      setState(() => _savingKey = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved for this account')),
      );
    } on SettingsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _savingKey = false;
        _keyError = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingKey = false;
        _keyError = '$error';
      });
    }
  }

  Future<void> _clearKey() async {
    final state = AppStateScope.read(context);
    setState(() {
      _clearingKey = true;
      _keyError = null;
    });
    try {
      await state.clearAiApiKey();
      if (!mounted) return;
      _apiKey.clear();
      setState(() => _clearingKey = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('API key cleared')));
    } on SettingsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _clearingKey = false;
        _keyError = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clearingKey = false;
        _keyError = '$error';
      });
    }
  }

  Future<void> _loadPromptTemplate() async {
    final state = AppStateScope.read(context);
    if (!state.hasSummaryService) return;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final template = await state.promptTemplate(_previewVariant);
      if (!mounted) return;
      setState(() {
        _previewTemplate = template;
        _previewLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewLoading = false;
        _previewError = error.toString();
      });
    }
  }

  Future<void> _applyTheme(AppState state, ThemePreference preference) async {
    try {
      await state.setTheme(preference);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Theme set to ${preference.label}')),
      );
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Density set to ${density.label}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the density: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = state.settings;
    // Saving before a successful load would write the default editors over the
    // account's stored preferences.
    final canSavePreferences =
        state.preferencesError == null && !state.preferencesLoading;

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
            const BackupsPanel(),
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
                              _timeDirty = true;
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
                              _timeDirty = true;
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
                        onPressed: _savingTime || !canSavePreferences
                            ? null
                            : _saveTime,
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
                        'Anthropic Messages provider for check-in synthesis',
                    icon: Icons.auto_awesome_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppDropdown<AIProviderPreset>(
                    value: _aiPreset,
                    label: 'Provider',
                    items: [
                      for (final preset in AIProviderPreset.values)
                        DropdownMenuItem(
                          value: preset,
                          child: Text(preset.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _aiPreset = value;
                        if (value != AIProviderPreset.custom) {
                          _setText(_baseUrl, value.baseUrl);
                          _setText(_model, value.model);
                        }
                        _aiDirty = true;
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _baseUrl,
                          decoration: const InputDecoration(
                            labelText: 'Base URL',
                            helperText: 'Endpoint for the chosen provider',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _model,
                          decoration: const InputDecoration(
                            labelText: 'Model',
                            helperText: 'Always editable',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    value: _redactUrls,
                    onChanged: (value) {
                      setState(() => _redactUrls = value);
                      _aiDirty = true;
                    },
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Redact URLs and notes'),
                    subtitle: const Text(
                      'Strips links, day/project notes and focus notes from the '
                      'payload sent to the provider.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.key_outlined,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                settings.hasAiApiKey
                                    ? 'API key stored'
                                    : 'No API key stored',
                                style: theme.textTheme.labelMedium,
                              ),
                            ),
                            if (settings.hasAiApiKey)
                              TextButton(
                                onPressed: _savingKey || _clearingKey
                                    ? null
                                    : () => unawaited(_clearKey()),
                                child: _clearingKey
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Clear key'),
                              ),
                          ],
                        ),
                        Text(
                          'Stored for this account. The key is write-only: it is '
                          'never returned by the service or included in an export.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _apiKey,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: 'API key',
                                  hintText: settings.hasAiApiKey
                                      ? 'Enter a new key to replace the stored one'
                                      : 'sk-ant-…',
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            FilledButton(
                              onPressed: _savingKey || !canSavePreferences
                                  ? null
                                  : () => unawaited(_saveKey()),
                              child: _savingKey
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Save key'),
                            ),
                          ],
                        ),
                        if (_keyError != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _keyError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
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
                      'Version ${_previewTemplate?.promptVersion ?? 'v1'} · service-owned',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    children: [
                      if (!state.hasSummaryService)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Connect the service to preview the versioned '
                            'prompt templates.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else ...[
                        AppDropdown<CheckInPromptVariant>(
                          value: _previewVariant,
                          label: 'Variant',
                          items: const [
                            DropdownMenuItem(
                              value: CheckInPromptVariant.managerOneOnOne,
                              child: Text('Manager 1:1'),
                            ),
                            DropdownMenuItem(
                              value:
                                  CheckInPromptVariant.managerPerformanceReview,
                              child: Text('Manager performance review'),
                            ),
                            DropdownMenuItem(
                              value: CheckInPromptVariant.personalReview,
                              child: Text('Personal review'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _previewVariant = value);
                            unawaited(_loadPromptTemplate());
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (_previewLoading)
                          const LinearProgressIndicator(minHeight: 2)
                        else if (_previewError != null)
                          Text(
                            _previewError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(
                                AppRadius.input,
                              ),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Text(
                              _previewTemplate?.template ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                height: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Redaction applies to generation only; exports keep '
                          'your complete data.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton(
                        onPressed: _savingAi || !canSavePreferences
                            ? null
                            : _saveAi,
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
                  const _AboutRow(
                    label: 'Data adapter',
                    value: 'Connect service',
                  ),
                  _AboutRow(label: 'Auth', value: _authDescription),
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
