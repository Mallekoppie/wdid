import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_tokens.dart';
import '../widgets/panel.dart';
import '../widgets/status_badge.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _invite = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  void _pending(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label is handled by the auth service. '
          'Connect Zitadel to enable this flow.',
        ),
      ),
    );
  }

  void _continueWithInvite() {
    if (_invite.text.trim().isEmpty) {
      setState(() => _error = 'Enter the invite code from your administrator.');
      return;
    }
    setState(() => _error = null);
    _pending('Invite registration');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final brand = Container(
            width: wide ? constraints.maxWidth * 0.48 : null,
            color: Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.30),
              scheme.surface,
            ),
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        'w',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'wdid',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    StatusBadge(
                      label: 'Preview',
                      color: scheme.secondary,
                      icon: Icons.visibility_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'What did you do?',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: scheme.onSurface,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'A private work ledger for time, initiatives, support, and '
                  'review-ready outcomes. Capture in seconds; export when it counts.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                for (final line in const [
                  'Local-first, portable data',
                  'Initiative and support attribution',
                  'AI-ready check-in summaries',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check, size: 15, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(line, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Zitadel OIDC is the baseline identity provider. '
                  'Registration requires an invite code during closed alpha.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );

          final form = Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Panel(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Sign in', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Use your identity provider, or enter an invite code.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton.icon(
                        onPressed: () => _pending('Zitadel sign-in'),
                        icon: const Icon(Icons.login, size: 17),
                        label: const Text('Continue with Zitadel'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () => _pending('Google sign-in'),
                        icon: const Icon(Icons.account_circle_outlined, size: 17),
                        label: const Text('Continue with Google'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () => _pending('Enterprise OIDC sign-in'),
                        icon: const Icon(Icons.domain, size: 17),
                        label: const Text('Enterprise OIDC'),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Expanded(child: Divider(color: scheme.outlineVariant)),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Text(
                              'CLOSED ALPHA',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: scheme.outlineVariant)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _invite,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _continueWithInvite(),
                        decoration: InputDecoration(
                          labelText: 'Invite code',
                          hintText: 'wdid-XXXX-XXXX',
                          errorText: _error,
                          prefixIcon: const Icon(Icons.key_outlined, size: 17),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: _continueWithInvite,
                        child: const Text('Continue with invite'),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextButton.icon(
                        onPressed: () => _pending('Break-glass passkey'),
                        icon: const Icon(Icons.fingerprint, size: 17),
                        label: const Text('Use break-glass master passkey'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'The auth service is not connected in this UI build. '
                        'Sign-in actions explain the pending contract instead of '
                        'simulating a session.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextButton(
                        onPressed: () => context.go('/today'),
                        child: const Text('Back to the demo journal'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          if (!wide) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [brand, form],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: brand),
              Expanded(child: form),
            ],
          );
        },
      ),
    );
  }
}
