import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/auth_api.dart';
import 'data/repository.dart';
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
  });

  final WdidRepository repository;
  final AuthApi authApi;
  final String? initialRoute;

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
    _state = AppState(widget.repository);
    _auth = AuthState(widget.authApi);
    _router = buildRouter(
      _state,
      _auth,
      initialLocation: widget.initialRoute,
    );
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
                ),
                AppTheme.build(
                  ThemePreference.system,
                  system: Brightness.dark,
                ),
                ThemeMode.system,
              ),
            ThemePreference.light => (
                AppTheme.build(ThemePreference.light),
                AppTheme.build(ThemePreference.light),
                ThemeMode.light,
              ),
            ThemePreference.dark => (
                AppTheme.build(ThemePreference.dark),
                AppTheme.build(ThemePreference.dark),
                ThemeMode.dark,
              ),
            ThemePreference.highContrast => (
                AppTheme.build(ThemePreference.highContrast),
                AppTheme.build(ThemePreference.highContrast),
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
