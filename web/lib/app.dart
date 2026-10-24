import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/auth_api.dart';
import 'data/category_api.dart';
import 'data/checkin_api.dart';
import 'data/entry_api.dart';
import 'data/milestone_api.dart';
import 'data/note_api.dart';
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
    required this.authApi,
    this.initialSession,
    this.initialRoute,
    this.categoryApiBuilder,
    this.settingsApiBuilder,
    this.entryApiBuilder,
    this.timerApiBuilder,
    this.summaryApiBuilder,
    this.noteApiBuilder,
    this.milestoneApiBuilder,
    this.checkInApiBuilder,
    this.isAdmin,
  });

  final AuthApi authApi;

  /// A session to start with. Production leaves this null and signs in; tests
  /// inject one to exercise the signed-in app without a login round-trip.
  final AuthSession? initialSession;
  final String? initialRoute;

  /// Builds the service-backed taxonomy client with a token accessor.
  final CategoryApi Function(String? Function() token)? categoryApiBuilder;

  /// Builds the service-backed settings client with a token accessor.
  final SettingsApi Function(String? Function() token)? settingsApiBuilder;

  /// Builds the service-backed entry client with a token accessor.
  final EntryApi Function(String? Function() token)? entryApiBuilder;

  /// Builds the service-backed timer client with a token accessor.
  final TimerApi Function(String? Function() token)? timerApiBuilder;

  /// Builds the service-backed period-report client with a token accessor.
  final SummaryApi Function(String? Function() token)? summaryApiBuilder;

  /// Builds the service-backed day/project note client with a token accessor.
  final NoteApi Function(String? Function() token)? noteApiBuilder;

  /// Builds the service-backed project milestone client with a token accessor.
  final MilestoneApi Function(String? Function() token)? milestoneApiBuilder;

  /// Builds the service-backed check-in client with a token accessor.
  final CheckInApi Function(String? Function() token)? checkInApiBuilder;

  /// Resolves the signed-in account's admin role. Defaults to the auth session;
  /// widget tests inject it directly.
  final bool Function()? isAdmin;

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
    _auth = AuthState(widget.authApi, initialSession: widget.initialSession);
    String? token() => _auth.session?.token;
    _state = AppState(
      categoryApi: widget.categoryApiBuilder?.call(token),
      settingsApi: widget.settingsApiBuilder?.call(token),
      entryApi: widget.entryApiBuilder?.call(token),
      timerApi: widget.timerApiBuilder?.call(token),
      summaryApi: widget.summaryApiBuilder?.call(token),
      noteApi: widget.noteApiBuilder?.call(token),
      milestoneApi: widget.milestoneApiBuilder?.call(token),
      checkInApi: widget.checkInApiBuilder?.call(token),
      roleCheck: widget.isAdmin ?? () => _auth.session?.user.role == 'admin',
    );
    _router = buildRouter(_state, _auth, initialLocation: widget.initialRoute);
    // The service-backed clients send the session bearer token, so loading
    // before sign-in would only produce unauthenticated errors. The login
    // screen reloads once a session exists.
    if (_auth.signedIn) unawaited(_state.load());
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
