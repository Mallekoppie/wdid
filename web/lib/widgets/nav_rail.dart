import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_tokens.dart';
import 'focus_ring.dart';
import 'forms/shortcuts_dialog.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;
}

const _items = [
  _NavItem('/today', 'Today', Icons.today_outlined),
  _NavItem('/log', 'Log', Icons.history),
  _NavItem('/initiatives', 'Initiatives', Icons.flag_outlined),
  _NavItem('/support', 'Support', Icons.volunteer_activism_outlined),
  _NavItem('/checkins', 'Check-ins', Icons.event_note_outlined),
];

class NavRail extends StatelessWidget {
  const NavRail({super.key, required this.currentPath, this.compact = false});

  final String currentPath;
  final bool compact;

  bool _selected(String path) {
    if (path == '/today') return currentPath == '/today';
    return currentPath == path || currentPath.startsWith('$path/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: compact ? 56 : AppSizes.navWidth,
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 8),
              child: Text(
                'JOURNAL',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const SizedBox(height: 14),
          for (final item in _items)
            _NavEntry(
              item: item,
              selected: _selected(item.path),
              compact: compact,
              onTap: () => context.go(item.path),
            ),
          const Spacer(),
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
              child: Text(
                'WORKSPACE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          _NavEntry(
            item: const _NavItem(
              '/settings',
              'Settings',
              Icons.settings_outlined,
            ),
            selected: _selected('/settings'),
            compact: compact,
            onTap: () => context.go('/settings'),
          ),
          _NavEntry(
            item: const _NavItem('', 'Shortcuts', Icons.keyboard_outlined),
            selected: false,
            compact: compact,
            onTap: () => showShortcutsDialog(context),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _NavEntry extends StatelessWidget {
  const _NavEntry({
    required this.item,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dense = theme.visualDensity.vertical < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: FocusRing(
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Material(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.72)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: InkWell(
            onTap: onTap,
            focusColor: scheme.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Tooltip(
              message: compact ? item.label : '',
              child: SizedBox(
                height: dense ? 34 : 38,
                child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (!compact) const SizedBox(width: 10),
                    Icon(
                      item.icon,
                      size: 18,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      Text(
                        item.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
