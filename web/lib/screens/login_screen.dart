import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state_scope.dart';
import '../state/auth_state.dart';
import '../theme/app_tokens.dart';
import '../widgets/panel.dart';
import '../widgets/status_badge.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthState auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();
  final _localUsername = TextEditingController();
  final _localPassword = TextEditingController();
  final _registerName = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerPassword = TextEditingController();
  final _inviteCode = TextEditingController();
  final _bootstrapSecret = TextEditingController();

  String? _formError;

  @override
  void initState() {
    super.initState();
    unawaited(_startAuth());
  }

  Future<void> _startAuth() async {
    if (widget.auth.config == null) {
      await widget.auth.loadConfig();
    }
    if (!mounted) return;
    _prefillLocalUsername();
  }

  /// A later local launch prefills the one account's username.
  void _prefillLocalUsername() {
    final username = widget.auth.config?.username ?? '';
    if (username.isNotEmpty && _localUsername.text.isEmpty) {
      _localUsername.text = username;
    }
  }

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPassword.dispose();
    _localUsername.dispose();
    _localPassword.dispose();
    _registerName.dispose();
    _registerEmail.dispose();
    _registerPassword.dispose();
    _inviteCode.dispose();
    _bootstrapSecret.dispose();
    super.dispose();
  }

  Future<void> _setupLocal() async {
    final username = _localUsername.text.trim();
    if (username.isEmpty) {
      setState(() => _formError = 'Enter a username.');
      return;
    }
    setState(() => _formError = null);
    final ok = await widget.auth.register(
      username: username,
      password: _localPassword.text,
      displayName: username,
    );
    _enterApp(ok);
  }

  Future<void> _signInLocal() async {
    final username = _localUsername.text.trim();
    final passwordRequired = widget.auth.config?.passwordRequired ?? false;
    if (username.isEmpty || (passwordRequired && _localPassword.text.isEmpty)) {
      setState(
        () => _formError = passwordRequired
            ? 'Enter your username and password.'
            : 'Enter your username.',
      );
      return;
    }
    setState(() => _formError = null);
    final ok = await widget.auth.login(
      username: username,
      password: _localPassword.text,
    );
    _enterApp(ok);
  }

  Future<void> _signIn() async {
    if (_loginEmail.text.trim().isEmpty || _loginPassword.text.isEmpty) {
      setState(() => _formError = 'Enter your email and password.');
      return;
    }
    setState(() => _formError = null);
    final ok = await widget.auth.login(
      email: _loginEmail.text.trim(),
      password: _loginPassword.text,
    );
    _enterApp(ok);
  }

  Future<void> _register() async {
    if (_registerEmail.text.trim().isEmpty ||
        _registerPassword.text.isEmpty ||
        _inviteCode.text.trim().isEmpty) {
      setState(
        () => _formError = 'Enter your email, password, and the invite code from your administrator.',
      );
      return;
    }
    setState(() => _formError = null);
    final ok = await widget.auth.register(
      email: _registerEmail.text.trim(),
      password: _registerPassword.text,
      displayName: _registerName.text.trim(),
      inviteCode: _inviteCode.text.trim(),
    );
    _enterApp(ok);
  }

  Future<void> _bootstrap() async {
    if (_registerEmail.text.trim().isEmpty ||
        _registerPassword.text.isEmpty ||
        _bootstrapSecret.text.isEmpty) {
      setState(
        () => _formError = 'Enter the admin email, password, and the deployment bootstrap secret.',
      );
      return;
    }
    setState(() => _formError = null);
    final ok = await widget.auth.register(
      email: _registerEmail.text.trim(),
      password: _registerPassword.text,
      displayName: _registerName.text.trim(),
      bootstrapSecret: _bootstrapSecret.text,
    );
    _enterApp(ok);
  }

  void _enterApp(bool ok) {
    if (!ok || !mounted) return;
    // The settings and taxonomy clients read the bearer token lazily, so a
    // reload after sign-in picks up this account's data.
    AppStateScope.read(context).reload();
    context.go('/today');
  }

  void _oidcPending() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Zitadel sign-in uses a browser redirect that is not wired into '
          'this build yet.',
        ),
      ),
    );
  }

  String? get _activeError => _formError ?? widget.auth.error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: ListenableBuilder(
        listenable: widget.auth,
        builder: (context, _) {
          final auth = widget.auth;
          final config = auth.config;
          final localMode = config?.isLocal ?? false;
          return LayoutBuilder(
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
                      localMode
                          ? 'This is a private single-user ledger. Set a '
                                'username and add a password only if you want one.'
                          : 'The first account is created with the deployment '
                                'bootstrap secret. Later accounts need a single-use invite code.',
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
                      child: _authForm(theme, scheme, auth, localMode),
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
          );
        },
      ),
    );
  }

  Widget _authForm(
    ThemeData theme,
    ColorScheme scheme,
    AuthState auth,
    bool localMode,
  ) {
    final config = auth.config;
    if (config == null && auth.loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final setup = localMode && (config?.setupRequired ?? false);
    final bootstrap = !localMode && (config?.bootstrapRequired ?? false);
    final passwordRequired = localMode && (config?.passwordRequired ?? false);

    final String title;
    final String subtitle;
    if (setup) {
      title = 'Set up wdid';
      subtitle =
          'Choose a username. Add a password only if you want one.';
    } else if (bootstrap) {
      title = 'Set up the first account';
      subtitle =
          'Use the deployment bootstrap secret to create the admin account.';
    } else if (localMode) {
      title = 'Sign in';
      subtitle = passwordRequired
          ? 'Enter the password for this account.'
          : 'No password is set. Select Sign in to continue.';
    } else {
      title = 'Sign in';
      subtitle =
          'Use your email and password, or register with an invite code.';
    }

    final List<Widget> fields;
    if (setup) {
      fields = _localSetupFields(auth.loading);
    } else if (bootstrap) {
      fields = _bootstrapFields(theme, auth.loading);
    } else if (localMode) {
      fields = _localLoginFields(auth.loading, passwordRequired);
    } else {
      fields = _loginFields(theme, auth.loading);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (auth.sessionNotice != null) ...[
          Text(
            auth.sessionNotice!,
            key: const Key('session-expired'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        ...fields,
        if (_activeError != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _activeError!,
            key: const Key('auth-error'),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        if (config == null) ...[
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: auth.loadConfig,
            child: const Text('Retry connection'),
          ),
        ],
        if (!localMode && config?.oidcEnabled == true) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _oidcPending,
            icon: const Icon(Icons.login, size: 17),
            label: const Text('Continue with Zitadel'),
          ),
        ],
      ],
    );
  }

  List<Widget> _localSetupFields(bool busy) {
    return [
      _field(
        key: const Key('local-setup-username'),
        controller: _localUsername,
        label: 'Username',
        onSubmitted: (_) => _setupLocal(),
      ),
      const SizedBox(height: AppSpacing.sm),
      _field(
        key: const Key('local-setup-password'),
        controller: _localPassword,
        label: 'Password (optional)',
        hint: 'Leave blank if you do not want a password',
        obscure: true,
        onSubmitted: (_) => _setupLocal(),
      ),
      const SizedBox(height: AppSpacing.md),
      FilledButton(
        key: const Key('local-setup-submit'),
        onPressed: busy ? null : _setupLocal,
        child: const Text('Create account'),
      ),
    ];
  }

  List<Widget> _localLoginFields(bool busy, bool passwordRequired) {
    return [
      _field(
        key: const Key('local-login-username'),
        controller: _localUsername,
        label: 'Username',
        onSubmitted: passwordRequired ? (_) => _signInLocal() : null,
      ),
      if (passwordRequired) ...[
        const SizedBox(height: AppSpacing.sm),
        _field(
          key: const Key('local-login-password'),
          controller: _localPassword,
          label: 'Password',
          obscure: true,
          onSubmitted: (_) => _signInLocal(),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      FilledButton(
        key: const Key('local-login-submit'),
        onPressed: busy ? null : _signInLocal,
        child: const Text('Sign in'),
      ),
    ];
  }

  List<Widget> _loginFields(ThemeData theme, bool busy) {
    return [
      _field(
        key: const Key('login-email'),
        controller: _loginEmail,
        label: 'Email',
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: AppSpacing.sm),
      _field(
        key: const Key('login-password'),
        controller: _loginPassword,
        label: 'Password',
        obscure: true,
        onSubmitted: (_) => _signIn(),
      ),
      const SizedBox(height: AppSpacing.md),
      FilledButton(
        key: const Key('login-submit'),
        onPressed: busy ? null : _signIn,
        child: const Text('Sign in'),
      ),
      const SizedBox(height: AppSpacing.xl),
      Row(
        children: [
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              'INVITE REGISTRATION',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      _field(
        key: const Key('register-name'),
        controller: _registerName,
        label: 'Display name',
      ),
      const SizedBox(height: AppSpacing.sm),
      _field(
        key: const Key('register-email'),
        controller: _registerEmail,
        label: 'Email',
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: AppSpacing.sm),
      _field(
        key: const Key('register-password'),
        controller: _registerPassword,
        label: 'Password',
        obscure: true,
      ),
      const SizedBox(height: AppSpacing.sm),
      _field(
        key: const Key('register-invite'),
        controller: _inviteCode,
        label: 'Invite code',
        hint: 'wdid-XXXX-XXXX-XXXX-XXXX',
        onSubmitted: (_) => _register(),
      ),
      const SizedBox(height: AppSpacing.md),
      OutlinedButton(
        key: const Key('register-submit'),
        onPressed: busy ? null : _register,
        child: const Text('Create account'),
      ),
    ];
  }

  List<Widget> _bootstrapFields(ThemeData theme, bool busy) {
    return [
      _field(
        key: const Key('bootstrap-name'),
        controller: _registerName,
        label: 'Display name',
      ),
      const SizedBox(height: AppSpacing.sm),
      _field(
        key: const Key('bootstrap-email'),
        controller: _registerEmail,
        label: 'Email',
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: AppSpacing.sm),
      _field(
        key: const Key('bootstrap-password'),
        controller: _registerPassword,
        label: 'Password',
        obscure: true,
      ),
      const SizedBox(height: AppSpacing.sm),
      _field(
        key: const Key('bootstrap-secret'),
        controller: _bootstrapSecret,
        label: 'Bootstrap secret',
        obscure: true,
        onSubmitted: (_) => _bootstrap(),
      ),
      const SizedBox(height: AppSpacing.md),
      FilledButton(
        key: const Key('bootstrap-submit'),
        onPressed: busy ? null : _bootstrap,
        child: const Text('Create admin account'),
      ),
    ];
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? hint,
    bool obscure = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}
