import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/auth_api.dart';
import 'data/category_api.dart';
import 'data/entry_api.dart';
import 'data/repository.dart';
import 'data/settings_api.dart';
import 'data/summary_api.dart';
import 'data/timer_api.dart';
import 'models/app_settings.dart';
import 'routing/app_router.dart';
import 'state/app_state.dart';
import 'state/app_state_scope.dart';
import 'state/auth_state.dart';
import 'theme/app_theme.dart';

class WdidApp extends StatefulWidget {
  const WdidApp({
    super.key,
    required this.repository,
    required this.authApi,
    this.initialRoute,
    this.categoryApiBuilder,
    this.settingsApiBuilder,
    this.entryApiBuilder,
    this.timerApiBuilder,
    this.summaryApiBuilder,
  });

  final WdidRepository repository;
  final AuthApi authApi;
  final String? initialRoute;

  /// Builds the service-backed taxonomy client with a token accessor. Tests
  /// leave this null and exercise the demo adapter.
  final CategoryApi Function(String? Function() token)? categoryApiBuilder;

  /// Builds the service-backed settings client with a token accessor.
  final SettingsApi Function(String? Function() token)? settingsApiBuilder;

  /// Builds the service-backed entry client with a token accessor.
  final EntryApi Function(String? Function() token)? entryApiBuilder;

  /// Builds the service-backed timer client with a token accessor.
  final TimerApi Function(String? Function() token)? timerApiBuilder;

  /// Builds the service-backed period-report client with a token accessor.
  final SummaryApi Function(String? Function() token)? summaryApiBuilder;

  @override
  State<WdidApp> createState() => _WdidAppState();
}

class _WdidAppState extends State<WdidApp> {
  late final AppState _state;
  late final AuthState _auth;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _auth = AuthState(widget.authApi);
    String? token() => _auth.session?.token;
    _state = AppState(
      widget.repository,
      categoryApi: widget.categoryApiBuilder?.call(token),
      settingsApi: widget.settingsApiBuilder?.call(token),
      entryApi: widget.entryApiBuilder?.call(token),
      timerApi: widget.timerApiBuilder?.call(token),
      summaryApi: widget.summaryApiBuilder?.call(token),
    );
    _router = buildRouter(_state, _auth, initialLocation: widget.initialRoute);
    unawaited(_state.load());
  }

  @override
  void dispose() {
    _router.dispose();
    _auth.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          final preference = _state.settings.theme;
          final (theme, darkTheme, mode) = switch (preference) {
            ThemePreference.system => (
              AppTheme.build(
                ThemePreference.system,
                system: Brightness.light,
                density: _state.settings.density,
              ),
              AppTheme.build(
                ThemePreference.system,
                system: Brightness.dark,
                density: _state.settings.density,
              ),
              ThemeMode.system,
            ),
            ThemePreference.light => (
              AppTheme.build(
                ThemePreference.light,
                density: _state.settings.density,
              ),
              AppTheme.build(
                ThemePreference.light,
                density: _state.settings.density,
              ),
              ThemeMode.light,
            ),
            ThemePreference.dark => (
              AppTheme.build(
                ThemePreference.dark,
                density: _state.settings.density,
              ),
              AppTheme.build(
                ThemePreference.dark,
                density: _state.settings.density,
              ),
              ThemeMode.dark,
            ),
            ThemePreference.highContrast => (
              AppTheme.build(
                ThemePreference.highContrast,
                density: _state.settings.density,
              ),
              AppTheme.build(
                ThemePreference.highContrast,
                density: _state.settings.density,
              ),
              ThemeMode.light,
            ),
          };
          return MaterialApp.router(
            title: 'wdid — what did you do',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: darkTheme,
            themeMode: mode,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
