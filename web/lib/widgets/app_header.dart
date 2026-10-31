import 'package:flutter/material.dart';

import '../state/app_state_scope.dart';
import '../state/auth_state.dart';
import '../theme/app_tokens.dart';
import 'checkin_pill.dart';
import 'forms/entry_form.dart';
import 'forms/shortcuts_dialog.dart';
import 'forms/support_dialog.dart';
import 'timer_pill.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.auth});

  final AuthState auth;

  Future<void> _newEntry(BuildContext context) async {
    final item = await showServiceEntryDialog(context);
    if (item != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry saved')));
    }
  }

  Future<void> _logSupport(BuildContext context) async {
    final state = AppStateScope.read(context);
    final saved = await showServiceSupportDialog(context, state: state);
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Support entry saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: AppSizes.headerHeight,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 1080;
          final showQuickActions = constraints.maxWidth >= 700;
          final showHelp = constraints.maxWidth >= 520;
          final showWordmark = constraints.maxWidth >= 560;
          final showBrandLogo = constraints.maxWidth >= 480;
          return Row(
            children: [
              if (showBrandLogo) ...[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'w',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
                if (showWordmark) ...[
                  const SizedBox(width: 9),
                  Text(
                    'wdid',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 8),
                    Text(
                      'what did you do',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ],
              const Spacer(),
              const TimerPill(),
              const SizedBox(width: AppSpacing.sm),
              if (wide) ...[
                const CheckInPill(),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (showQuickActions) ...[
                IconButton(
                  tooltip: 'New entry (N)',
                  onPressed: () => _newEntry(context),
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                ),
                IconButton(
                  tooltip: 'Log support (S)',
                  onPressed: () => _logSupport(context),
                  icon: const Icon(Icons.volunteer_activism_outlined, size: 20),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
              if (showHelp)
                PopupMenuButton<String>(
                  tooltip: 'Help and account',
                  onSelected: (value) {
                    if (value == 'shortcuts') {
                      showShortcutsDialog(context);
                    } else if (value == 'signout') {
                      // AuthState invokes the app's session-ended callback,
                      // which drops account data and navigates explicitly.
                      auth.signOut();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'shortcuts',
                      child: Text('Keyboard shortcuts'),
                    ),
                    PopupMenuItem(
                      value: 'signout',
                      child: Text('Sign out'),
                    ),
                  ],
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.more_horiz, size: 20),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
