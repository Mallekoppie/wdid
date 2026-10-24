import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

enum PanelTone { normal, accent, support, warning }

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.tone = PanelTone.normal,
    this.onTap,
    this.radius = AppRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final PanelTone tone;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, border, accent) = switch (tone) {
      PanelTone.normal => (scheme.surface, scheme.outlineVariant, null),
      PanelTone.accent => (
        Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.38),
          scheme.surface,
        ),
        scheme.outlineVariant,
        scheme.primary,
      ),
      PanelTone.support => (
        Color.alphaBlend(
          scheme.tertiaryContainer.withValues(alpha: 0.30),
          scheme.surface,
        ),
        scheme.outlineVariant,
        scheme.tertiary,
      ),
      PanelTone.warning => (
        Color.alphaBlend(
          scheme.errorContainer.withValues(alpha: 0.25),
          scheme.surface,
        ),
        scheme.outlineVariant,
        scheme.error,
      ),
    };
    final radiusValue = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: radiusValue,
        border: Border.all(color: border),
      ),
      child: ClipRRect(
        borderRadius: radiusValue,
        child: Stack(
          children: [
            if (accent != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 2,
                child: ColoredBox(color: accent),
              ),
            Material(
              type: MaterialType.transparency,
              child: onTap == null
                  ? Padding(padding: padding, child: child)
                  : InkWell(
                      onTap: onTap,
                      child: Padding(padding: padding, child: child),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          ?trailing,
        ],
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.meta,
    this.trailing,
  });

  final String title;
  final String? meta;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (meta != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            meta!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
