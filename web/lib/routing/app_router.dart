import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/checkin_detail_screen.dart';
import '../screens/checkins_screen.dart';
import '../screens/initiatives_screen.dart';
import '../screens/log_screen.dart';
import '../screens/login_screen.dart';
import '../screens/project_detail_screen.dart';
import '../screens/review_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/support_screen.dart';
import '../screens/today_screen.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../utils/review_timeframe.dart';
import '../utils/time_utils.dart';
import '../widgets/app_shell.dart';

ReviewTimeframe? _reviewTimeframe(String? value) {
  for (final timeframe in ReviewTimeframe.values) {
    if (timeframe.name == value) return timeframe;
  }
  return null;
}

GoRouter buildRouter(
  AppState state,
  AuthState auth, {
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? '/today',
    // Sign-in navigation is explicit (`LoginScreen` goes to `/today`), so the
    // router does not listen to auth notifications. Listening here would fire
    // while the login screen loads its config and rebuild the router mid-build.
    redirect: (context, routerState) {
      final loggingIn = routerState.matchedLocation == '/login';
      if (!auth.signedIn && !loggingIn) return '/login';
      if (auth.signedIn && loggingIn) return '/today';
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, routerState, child) {
          return AppShell(currentPath: routerState.uri.path, child: child);
        },
        routes: [
          GoRoute(
            path: '/today',
            builder: (context, routerState) => const TodayScreen(),
          ),
          GoRoute(
            path: '/log',
            builder: (context, routerState) => const LogScreen(),
          ),
          GoRoute(
            path: '/initiatives',
            builder: (context, routerState) => const InitiativesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, routerState) {
                  final id = routerState.pathParameters['id']!;
                  return ProjectDetailScreen(projectId: id);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/support',
            builder: (context, routerState) => const SupportScreen(),
          ),
          GoRoute(
            path: '/checkins',
            builder: (context, routerState) => const CheckinsScreen(),
            routes: [
              // The live review is static and must be matched before the
              // detail route's `:id`, so `/checkins/review` is never mistaken
              // for a check-in id.
              GoRoute(
                path: 'review',
                builder: (context, routerState) {
                  final query = routerState.uri.queryParameters;
                  final start =
                      DateTime.tryParse(query['start'] ?? '') ?? state.today;
                  final end =
                      DateTime.tryParse(query['end'] ?? '') ?? state.today;
                  return ReviewScreen(
                    start: dateOnly(start),
                    end: dateOnly(end),
                    timeframe: _reviewTimeframe(query['timeframe']),
                  );
                },
              ),
              GoRoute(
                path: ':id',
                builder: (context, routerState) => CheckinDetailScreen(
                  checkInId: routerState.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, routerState) => SettingsScreen(auth: auth),
          ),
        ],
      ),
      GoRoute(
        path: '/login',
        builder: (context, routerState) => LoginScreen(auth: auth),
      ),
    ],
    errorBuilder: (context, routerState) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 32),
            const SizedBox(height: 12),
            Text('No screen at ${routerState.uri.path}'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/today'),
              child: const Text('Back to Today'),
            ),
          ],
        ),
      ),
    ),
  );
}
