import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/checkin_detail_screen.dart';
import '../screens/checkins_screen.dart';
import '../screens/initiative_detail_screen.dart';
import '../screens/initiatives_screen.dart';
import '../screens/log_screen.dart';
import '../screens/login_screen.dart';
import '../screens/project_detail_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/support_screen.dart';
import '../screens/today_screen.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../widgets/app_shell.dart';

GoRouter buildRouter(
  AppState state,
  AuthState auth, {
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? '/today',
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
                  return state.hasTaxonomyService
                      ? ProjectDetailScreen(projectId: id)
                      : InitiativeDetailScreen(initiativeId: id);
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
            builder: (context, routerState) => const SettingsScreen(),
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
