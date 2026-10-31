import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/auth_api.dart';
import 'data/category_api.dart';
import 'data/checkin_api.dart';
import 'data/entry_api.dart';
import 'data/grpc_channel.dart';
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

  /// Builds the service-backed taxonomy client for the signed-in session.
  final CategoryApi Function(ApiSession session)? categoryApiBuilder;

  /// Builds the service-backed settings client for the signed-in session.
  final SettingsApi Function(ApiSession session)? settingsApiBuilder;

  /// Builds the service-backed entry client for the signed-in session.
  final EntryApi Function(ApiSession session)? entryApiBuilder;

  /// Builds the service-backed timer client for the signed-in session.
  final TimerApi Function(ApiSession session)? timerApiBuilder;

  /// Builds the service-backed period-report client for the signed-in session.
  final SummaryApi Function(ApiSession session)? summaryApiBuilder;

  /// Builds the service-backed day/project note client for the signed-in session.
  final NoteApi Function(ApiSession session)? noteApiBuilder;

  /// Builds the service-backed project milestone client for the signed-in session.
  final MilestoneApi Function(ApiSession session)? milestoneApiBuilder;

  /// Builds the service-backed check-in client for the signed-in session.
  final CheckInApi Function(ApiSession session)? checkInApiBuilder;

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
    // Every service client shares this session: the lazy token guard stops an
    // expired token being attached, and the callback ends the session when the
    // service rejects it.
    final session = ApiSession(
      token: () => _auth.token,
      onUnauthenticated: _auth.handleUnauthenticated,
    );
    _state = AppState(
      categoryApi: widget.categoryApiBuilder?.call(session),
      settingsApi: widget.settingsApiBuilder?.call(session),
      entryApi: widget.entryApiBuilder?.call(session),
      timerApi: widget.timerApiBuilder?.call(session),
      summaryApi: widget.summaryApiBuilder?.call(session),
      noteApi: widget.noteApiBuilder?.call(session),
      milestoneApi: widget.milestoneApiBuilder?.call(session),
      checkInApi: widget.checkInApiBuilder?.call(session),
      roleCheck: widget.isAdmin ?? () => _auth.session?.user.role == 'admin',
    );
    _router = buildRouter(_state, _auth, initialLocation: widget.initialRoute);
    _auth.onSessionEnded = _handleSessionEnded;
    // The service-backed clients send the session bearer token, so loading
    // before sign-in would only produce unauthenticated errors. The login
    // screen reloads once a session exists.
    if (_auth.signedIn) unawaited(_state.load());
  }

  /// Shared cleanup for every session-ending path: sign-out today, token
  /// expiry later. Drop the account's cached data, then go to the login screen
  /// explicitly because the router deliberately does not listen to auth.
  void _handleSessionEnded() {
    _state.reset();
    _router.go('/login');
  }

  @override
  void dispose() {
    _auth.onSessionEnded = null;
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
