/// Throwaway UI prototype for issues #21 (timer header) and #23 (Today mode
/// selector).
///
/// Run:
///   make prototype-ui
///
/// Open:
///   http://127.0.0.1:5174/#/prototype-ui-review?header=A&row=A
///
/// `header` and `row` each accept A, B, or C. The floating bar switches them,
/// and the arrow keys work too:
///   ←/→ header variants, ↑/↓ Today-row variants, P timer state, T theme,
///   C density.
///
/// This file is not part of the production app. Delete it and the
/// `prototype-ui` Makefile target once a variant has been chosen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/app_settings.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/panel.dart';

const _prototypePath = '/prototype-ui-review';
const _clearMode = '__clear_mode__';

const _headerNames = [
  'Separate labeled buttons',
  'Segmented control',
  'Second-row strip',
];

const _rowNames = ['Bordered dropdown', 'Mode chips', 'Labeled control line'];

const _timerNames = ['Running', 'Paused', 'Stopping'];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('The UI prototype is dev-only.')),
        ),
      ),
    );
    return;
  }
  runApp(const PrototypeApp());
}

class PrototypeApp extends StatefulWidget {
  const PrototypeApp({super.key});

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  final GlobalKey<_PrototypePageState> _pageKey =
      GlobalKey<_PrototypePageState>();
  late final GoRouter _router;

  bool _dark = false;
  DensityPreference _density = DensityPreference.comfortable;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '$_prototypePath?header=A&row=A',
      routes: [
        GoRoute(
          path: _prototypePath,
          builder: (context, state) {
            final header = _variantIndex(state.uri.queryParameters['header']);
            final row = _variantIndex(state.uri.queryParameters['row']);
            return PrototypePage(
              key: _pageKey,
              headerVariant: header,
              rowVariant: row,
              onHeaderVariant: (next) => _go(header: next, row: row),
              onRowVariant: (next) => _go(header: header, row: next),
              onToggleTheme: () => setState(() => _dark = !_dark),
              onToggleDensity: () => setState(
                () => _density = _density == DensityPreference.comfortable
                    ? DensityPreference.compact
                    : DensityPreference.comfortable,
              ),
            );
          },
        ),
      ],
    );
  }

  void _go({required int header, required int row}) {
    _router.go(
      '$_prototypePath?header=${_variantKey(header)}&row=${_variantKey(row)}',
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'wdid UI prototype',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(ThemePreference.light, density: _density),
      darkTheme: AppTheme.build(ThemePreference.dark, density: _density),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router,
    );
  }
}

int _variantIndex(String? key) {
  switch (key?.toUpperCase()) {
    case 'B':
      return 1;
    case 'C':
      return 2;
    default:
      return 0;
  }
}

String _variantKey(int index) {
  final safe = index < 0 ? 0 : (index > 2 ? 2 : index);
  return const ['A', 'B', 'C'][safe];
}

void _prototypeToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class PrototypePage extends StatefulWidget {
  const PrototypePage({
    super.key,
    required this.headerVariant,
    required this.rowVariant,
    required this.onHeaderVariant,
    required this.onRowVariant,
    required this.onToggleTheme,
    required this.onToggleDensity,
  });

  final int headerVariant;
  final int rowVariant;
  final ValueChanged<int> onHeaderVariant;
  final ValueChanged<int> onRowVariant;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleDensity;

  @override
  State<PrototypePage> createState() => _PrototypePageState();
}

class _PrototypePageState extends State<PrototypePage> {
  int _timerState = 0;
  Timer? _stopTimer;
  late final Map<String, String?> _modes;

  @override
  void initState() {
    super.initState();
    _modes = {
      for (final entry in _entries)
        if (entry.role == _Role.support) entry.id: entry.mode,
    };
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    super.dispose();
  }

  void _setMode(String id, String? mode) {
    setState(() => _modes[id] = mode);
    _prototypeToast(
      context,
      mode == null ? 'Mode cleared' : 'Mode set · $mode',
    );
  }

  void _togglePause() {
    if (_timerState == 2) return;
    setState(() => _timerState = _timerState == 1 ? 0 : 1);
    _prototypeToast(
      context,
      _timerState == 1 ? 'Timer paused' : 'Timer resumed',
    );
  }

  void _stop() {
    if (_timerState == 2) return;
    setState(() => _timerState = 2);
    _stopTimer?.cancel();
    _stopTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() => _timerState = 0);
      _prototypeToast(
        context,
        'Saved 42 min · Initiatives · Code review (prototype)',
      );
    });
  }

  void _interrupt() {
    _prototypeToast(
      context,
      'Interrupt (prototype) — the bottom card is issue #14',
    );
  }

  void _cycleTimer() {
    setState(() => _timerState = (_timerState + 1) % 3);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        focused.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onHeaderVariant((widget.headerVariant + 2) % 3);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onHeaderVariant((widget.headerVariant + 1) % 3);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onRowVariant((widget.rowVariant + 2) % 3);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onRowVariant((widget.rowVariant + 1) % 3);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      _cycleTimer();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      widget.onToggleTheme();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      widget.onToggleDensity();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timer = _TimerData(
      paused: _timerState == 1,
      stopping: _timerState == 2,
    );

    final header = switch (widget.headerVariant) {
      1 => _HeaderVariantB(
        timer: timer,
        onPause: _togglePause,
        onStop: _stop,
        onInterrupt: _interrupt,
      ),
      2 => _HeaderVariantC(
        timer: timer,
        onPause: _togglePause,
        onStop: _stop,
        onInterrupt: _interrupt,
      ),
      _ => _HeaderVariantA(
        timer: timer,
        onPause: _togglePause,
        onStop: _stop,
        onInterrupt: _interrupt,
      ),
    };

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                header,
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 820;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FakeNavRail(compact: compact),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: scheme.outlineVariant,
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _PageFrame(
                                child: _TodayPreview(
                                  variant: widget.rowVariant,
                                  modes: _modes,
                                  onSetMode: _setMode,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: PrototypeSwitcher(
                    headerVariant: widget.headerVariant,
                    rowVariant: widget.rowVariant,
                    timerState: _timerState,
                    onHeaderVariant: widget.onHeaderVariant,
                    onRowVariant: widget.onRowVariant,
                    onTimerState: (next) => setState(() => _timerState = next),
                    onToggleTheme: widget.onToggleTheme,
                    onToggleDensity: widget.onToggleDensity,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerData {
  const _TimerData({required this.paused, required this.stopping});

  final bool paused;
  final bool stopping;

  String get label => 'Initiatives · Code review';
  String get clock => '00:42:17';
}

// ---------------------------------------------------------------------------
// Header variants
// ---------------------------------------------------------------------------

class _HeaderVariantA extends StatelessWidget {
  const _HeaderVariantA({
    required this.timer,
    required this.onPause,
    required this.onStop,
    required this.onInterrupt,
  });

  final _TimerData timer;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onInterrupt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labels = constraints.maxWidth >= 900;
        final tagline = constraints.maxWidth >= 1080;
        final gap = labels ? 8.0 : 4.0;
        return _HeaderFrame(
          height: 64,
          child: Row(
            children: [
              _Brand(showTagline: tagline),
              const Spacer(),
              _TimerSummary(timer: timer, boxed: true),
              const SizedBox(width: 12),
              _HeaderAction(
                icon: Icons.swap_horiz,
                label: 'Interrupt',
                tone: _ActionTone.tertiary,
                labels: labels,
                onPressed: timer.stopping ? null : onInterrupt,
              ),
              SizedBox(width: gap),
              _HeaderAction(
                icon: timer.paused ? Icons.play_arrow : Icons.pause,
                label: timer.paused ? 'Resume' : 'Pause',
                filled: true,
                labels: labels,
                onPressed: timer.stopping ? null : onPause,
              ),
              SizedBox(width: gap),
              _HeaderAction(
                icon: Icons.stop,
                label: 'Stop',
                tone: _ActionTone.error,
                labels: labels,
                spinner: timer.stopping,
                onPressed: timer.stopping ? null : onStop,
              ),
              const SizedBox(width: 12),
              const _HeaderIcons(),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderVariantB extends StatelessWidget {
  const _HeaderVariantB({
    required this.timer,
    required this.onPause,
    required this.onStop,
    required this.onInterrupt,
  });

  final _TimerData timer;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onInterrupt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labels = constraints.maxWidth >= 900;
        final tagline = constraints.maxWidth >= 1080;
        return _HeaderFrame(
          height: 64,
          child: Row(
            children: [
              _Brand(showTagline: tagline),
              const Spacer(),
              _TimerSummary(timer: timer, boxed: false),
              const SizedBox(width: 14),
              _SegmentedActions(
                timer: timer,
                labels: labels,
                onPause: onPause,
                onStop: onStop,
                onInterrupt: onInterrupt,
              ),
              const SizedBox(width: 12),
              const _HeaderIcons(),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderVariantC extends StatelessWidget {
  const _HeaderVariantC({
    required this.timer,
    required this.onPause,
    required this.onStop,
    required this.onInterrupt,
  });

  final _TimerData timer;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onInterrupt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return _HeaderFrame(
              height: 48,
              borderBottom: false,
              child: Row(
                children: [
                  _Brand(showTagline: constraints.maxWidth >= 1080),
                  const Spacer(),
                  const _HeaderIcons(),
                ],
              ),
            );
          },
        ),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.34),
              scheme.surface,
            ),
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final labels = constraints.maxWidth >= 760;
              return Row(
                children: [
                  Icon(
                    timer.paused
                        ? Icons.pause_circle_outline
                        : Icons.timer_outlined,
                    size: 20,
                    color: timer.paused
                        ? scheme.onSurfaceVariant
                        : scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      timer.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    timer.clock,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFeatures: tabularFigures,
                      fontWeight: FontWeight.w600,
                      color: timer.paused ? scheme.tertiary : scheme.primary,
                    ),
                  ),
                  if (timer.paused && labels) ...[
                    const SizedBox(width: 8),
                    Text(
                      'Paused',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(width: 16),
                  _HeaderAction(
                    icon: Icons.swap_horiz,
                    label: 'Interrupt',
                    tone: _ActionTone.tertiary,
                    labels: labels,
                    onPressed: timer.stopping ? null : onInterrupt,
                  ),
                  const SizedBox(width: 6),
                  _HeaderAction(
                    icon: timer.paused ? Icons.play_arrow : Icons.pause,
                    label: timer.paused ? 'Resume' : 'Pause',
                    filled: true,
                    labels: labels,
                    onPressed: timer.stopping ? null : onPause,
                  ),
                  const SizedBox(width: 6),
                  _HeaderAction(
                    icon: Icons.stop,
                    label: 'Stop',
                    tone: _ActionTone.error,
                    labels: labels,
                    spinner: timer.stopping,
                    onPressed: timer.stopping ? null : onStop,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeaderFrame extends StatelessWidget {
  const _HeaderFrame({
    required this.height,
    required this.child,
    this.borderBottom = true,
  });

  final double height;
  final Widget child;
  final bool borderBottom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: borderBottom
            ? Border(bottom: BorderSide(color: scheme.outlineVariant))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: child,
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.showTagline});

  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        const SizedBox(width: 9),
        Text(
          'wdid',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        if (showTagline) ...[
          const SizedBox(width: 8),
          Text(
            'what did you do',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ],
    );
  }
}

class _TimerSummary extends StatelessWidget {
  const _TimerSummary({required this.timer, required this.boxed});

  final _TimerData timer;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          timer.paused ? Icons.pause_circle_outline : Icons.timer_outlined,
          size: 20,
          color: timer.paused ? scheme.onSurfaceVariant : scheme.primary,
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timer.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                timer.paused ? 'Paused · ${timer.clock}' : timer.clock,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFeatures: tabularFigures,
                  color: timer.paused
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!boxed) return content;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.45),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: content,
    );
  }
}

enum _ActionTone { neutral, tertiary, error }

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.labels,
    this.tone = _ActionTone.neutral,
    this.filled = false,
    this.spinner = false,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool labels;
  final _ActionTone tone;
  final bool filled;
  final bool spinner;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (tone) {
      _ActionTone.neutral => scheme.onSurface,
      _ActionTone.tertiary => scheme.tertiary,
      _ActionTone.error => scheme.error,
    };
    final foreground = filled ? scheme.onPrimary : color;
    final iconWidget = spinner
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : Icon(icon, size: labels ? 18 : 20, color: foreground);

    if (labels) {
      if (filled) {
        return FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: theme.textTheme.labelLarge,
          ),
          icon: iconWidget,
          label: Text(label),
        );
      }
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: theme.textTheme.labelLarge,
        ),
        icon: iconWidget,
        label: Text(label),
      );
    }

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
    );
    if (filled) {
      return IconButton.filled(
        tooltip: label,
        onPressed: onPressed,
        icon: iconWidget,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.zero,
          shape: shape,
        ),
      );
    }
    return IconButton.outlined(
      tooltip: label,
      onPressed: onPressed,
      icon: iconWidget,
      style: IconButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        shape: shape,
      ),
    );
  }
}

class _SegmentedActions extends StatelessWidget {
  const _SegmentedActions({
    required this.timer,
    required this.labels,
    required this.onPause,
    required this.onStop,
    required this.onInterrupt,
  });

  final _TimerData timer;
  final bool labels;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onInterrupt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.swap_horiz,
            label: 'Interrupt',
            color: scheme.tertiary,
            labels: labels,
            onTap: timer.stopping ? null : onInterrupt,
          ),
          _SegmentDivider(color: scheme.outlineVariant),
          _Segment(
            icon: timer.paused ? Icons.play_arrow : Icons.pause,
            label: timer.paused ? 'Resume' : 'Pause',
            color: scheme.onPrimary,
            background: scheme.primary,
            labels: labels,
            onTap: timer.stopping ? null : onPause,
          ),
          _SegmentDivider(color: scheme.outlineVariant),
          _Segment(
            icon: Icons.stop,
            label: 'Stop',
            color: scheme.error,
            labels: labels,
            spinner: timer.stopping,
            onTap: timer.stopping ? null : onStop,
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.color,
    required this.labels,
    this.background,
    this.spinner = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool labels;
  final Color? background;
  final bool spinner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = spinner
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        : Icon(icon, size: 18, color: color);

    return Material(
      color: background ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          width: labels ? null : 48,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: labels ? 14 : 0),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconWidget,
                  if (labels) ...[
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(color: color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentDivider extends StatelessWidget {
  const _SegmentDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: color);
  }
}

class _HeaderIcons extends StatelessWidget {
  const _HeaderIcons();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderIconButton(
          icon: Icons.add_circle_outline,
          tooltip: 'New entry (N)',
        ),
        _HeaderIconButton(
          icon: Icons.volunteer_activism_outlined,
          tooltip: 'Log support (S)',
        ),
        _HeaderIconButton(icon: Icons.more_horiz, tooltip: 'Help and account'),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: () =>
          _prototypeToast(context, '$tooltip — not part of this prototype'),
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today preview
// ---------------------------------------------------------------------------

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 220),
          child: child,
        ),
      ),
    );
  }
}

class _TodayPreview extends StatelessWidget {
  const _TodayPreview({
    required this.variant,
    required this.modes,
    required this.onSetMode,
  });

  final int variant;
  final Map<String, String?> modes;
  final void Function(String id, String? mode) onSetMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _entries.fold<int>(0, (sum, entry) => sum + entry.minutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Sunday 26 October · ${_entries.length} entries',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatMinutes(total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabularFigures,
                  ),
                ),
                Text(
                  'logged today',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final entry in _entries)
                _TodayRow(
                  entry: entry,
                  mode: modes[entry.id],
                  variant: variant,
                  onSetMode: (mode) => onSetMode(entry.id, mode),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({
    required this.entry,
    required this.mode,
    required this.variant,
    required this.onSetMode,
  });

  final _FakeEntry entry;
  final String? mode;
  final int variant;
  final ValueChanged<String?> onSetMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final support = entry.role == _Role.support;
    final accent = switch (entry.role) {
      _Role.initiative => scheme.primary,
      _Role.support => scheme.tertiary,
      _Role.other => scheme.onSurfaceVariant,
    };
    final verticalPadding = AppTheme.isCompact(context) ? 6.0 : 10.0;
    final attribution = [
      entry.category,
      if (!support && entry.mode != null) entry.mode!,
      if (support && mode != null) mode!,
      if (entry.person != null) entry.person!,
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: support
            ? scheme.tertiaryContainer.withValues(alpha: 0.14)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        verticalPadding,
        12,
        verticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 98,
                child: Text(
                  entry.time,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              Icon(
                switch (entry.role) {
                  _Role.initiative => Icons.flag_outlined,
                  _Role.support => Icons.volunteer_activism_outlined,
                  _Role.other => Icons.category_outlined,
                },
                size: 14,
                color: accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: attribution,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (entry.description.isNotEmpty)
                        TextSpan(
                          text: '   ${entry.description}',
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entry.outcome.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.verified_outlined,
                    size: 13,
                    color: scheme.tertiary,
                  ),
                ),
              SizedBox(
                width: 52,
                child: Text(
                  _formatMinutes(entry.minutes),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            ],
          ),
          if (support) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 104),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _RowModeSelector(
                  variant: variant,
                  mode: mode,
                  onChanged: onSetMode,
                ),
              ),
            ),
          ],
          const SizedBox(height: 2),
          if (entry.outcome.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 104),
              child: TextButton.icon(
                onPressed: () => _prototypeToast(
                  context,
                  'Outcome editor is not part of this prototype',
                ),
                icon: const Icon(Icons.add_circle_outline, size: 14),
                label: const Text('Add outcome'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 104),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 13,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      entry.outcome,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _prototypeToast(
                      context,
                      'Outcome editor is not part of this prototype',
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                    child: const Text('Edit outcome'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today mode selectors
// ---------------------------------------------------------------------------

class _RowModeSelector extends StatelessWidget {
  const _RowModeSelector({
    required this.variant,
    required this.mode,
    required this.onChanged,
  });

  final int variant;
  final String? mode;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selector = switch (variant) {
      1 => _ModeSelectorChips(
        mode: mode,
        modes: _supportModes,
        onChanged: onChanged,
      ),
      2 => _ModeSelectorLabeled(
        mode: mode,
        modes: _supportModes,
        onChanged: onChanged,
      ),
      _ => _ModeSelectorDropdown(
        mode: mode,
        modes: _supportModes,
        onChanged: onChanged,
      ),
    };
    if (variant == 1) return selector;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: selector,
    );
  }
}

List<PopupMenuEntry<String>> _modeMenuItems(String? mode, List<String> modes) {
  return [
    for (final name in modes)
      PopupMenuItem<String>(
        value: name,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: mode == name ? const Icon(Icons.check, size: 16) : null,
            ),
            Text(name),
          ],
        ),
      ),
    const PopupMenuItem<String>(value: _clearMode, child: Text('Clear mode')),
  ];
}

String? _modeFromMenu(String value) => value == _clearMode ? null : value;

class _ModeSelectorDropdown extends StatelessWidget {
  const _ModeSelectorDropdown({
    required this.mode,
    required this.modes,
    required this.onChanged,
  });

  final String? mode;
  final List<String> modes;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: 'Set support mode',
          onSelected: (value) => onChanged(_modeFromMenu(value)),
          itemBuilder: (_) => _modeMenuItems(mode, modes),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: mode == null
                      ? scheme.tertiaryContainer.withValues(alpha: 0.18)
                      : scheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: Border.all(
                    color: mode == null
                        ? scheme.tertiary.withValues(alpha: 0.55)
                        : scheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mode',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      mode ?? 'Not set',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: mode == null
                            ? scheme.tertiary
                            : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (mode != null) ...[
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => onChanged(null),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Clear'),
          ),
        ],
      ],
    );
  }
}

class _ModeSelectorChips extends StatelessWidget {
  const _ModeSelectorChips({
    required this.mode,
    required this.modes,
    required this.onChanged,
  });

  final String? mode;
  final List<String> modes;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _ModeChip(
          label: 'No mode',
          selected: mode == null,
          onTap: () => onChanged(null),
        ),
        for (final name in modes)
          _ModeChip(
            label: name,
            selected: mode == name,
            onTap: () => onChanged(name),
          ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 48,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Center(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.tertiaryContainer.withValues(alpha: 0.55)
                  : scheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? scheme.tertiary : scheme.outlineVariant,
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? scheme.onTertiaryContainer : scheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSelectorLabeled extends StatelessWidget {
  const _ModeSelectorLabeled({
    required this.mode,
    required this.modes,
    required this.onChanged,
  });

  final String? mode;
  final List<String> modes;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Change support mode',
      onSelected: (value) => onChanged(_modeFromMenu(value)),
      itemBuilder: (_) => _modeMenuItems(mode, modes),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: mode == null
              ? scheme.tertiaryContainer.withValues(alpha: 0.16)
              : scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: mode == null
                ? scheme.tertiary.withValues(alpha: 0.55)
                : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outline, size: 16, color: scheme.tertiary),
            const SizedBox(width: 8),
            Text(
              'Support mode',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              mode ?? 'Not set',
              style: theme.textTheme.labelMedium?.copyWith(
                color: mode == null ? scheme.tertiary : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating variant switcher
// ---------------------------------------------------------------------------

class PrototypeSwitcher extends StatelessWidget {
  const PrototypeSwitcher({
    super.key,
    required this.headerVariant,
    required this.rowVariant,
    required this.timerState,
    required this.onHeaderVariant,
    required this.onRowVariant,
    required this.onTimerState,
    required this.onToggleTheme,
    required this.onToggleDensity,
  });

  final int headerVariant;
  final int rowVariant;
  final int timerState;
  final ValueChanged<int> onHeaderVariant;
  final ValueChanged<int> onRowVariant;
  final ValueChanged<int> onTimerState;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleDensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final compact = theme.visualDensity.vertical < 0;
    final onBar = scheme.onInverseSurface;

    return Material(
      color: scheme.inverseSurface,
      elevation: 16,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'PROTOTYPE · throwaway UI review',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onBar.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                _BarTextButton(
                  icon: dark ? Icons.dark_mode : Icons.light_mode,
                  label: dark ? 'Dark' : 'Light',
                  onPressed: onToggleTheme,
                ),
                _BarTextButton(
                  icon: compact ? Icons.density_small : Icons.density_medium,
                  label: compact ? 'Compact' : 'Comfortable',
                  onPressed: onToggleDensity,
                ),
                _BarTextButton(
                  icon: Icons.timer_outlined,
                  label: _timerNames[timerState],
                  onPressed: () => onTimerState((timerState + 1) % 3),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _VariantRow(
              label: 'Header',
              value:
                  '${_variantKey(headerVariant)} · ${_headerNames[headerVariant]}',
              onPrevious: () => onHeaderVariant((headerVariant + 2) % 3),
              onNext: () => onHeaderVariant((headerVariant + 1) % 3),
            ),
            const SizedBox(height: 2),
            _VariantRow(
              label: 'Today row',
              value: '${_variantKey(rowVariant)} · ${_rowNames[rowVariant]}',
              onPrevious: () => onRowVariant((rowVariant + 2) % 3),
              onNext: () => onRowVariant((rowVariant + 1) % 3),
            ),
            const SizedBox(height: 6),
            Text(
              '←/→ header · ↑/↓ Today row · P timer state · T theme · C density',
              style: theme.textTheme.labelSmall?.copyWith(
                color: onBar.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.label,
    required this.value,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final String value;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBar = theme.colorScheme.onInverseSurface;
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: onBar.withValues(alpha: 0.75),
            ),
          ),
        ),
        _BarIconButton(
          icon: Icons.chevron_left,
          tooltip: 'Previous $label',
          onPressed: onPrevious,
        ),
        Expanded(
          child: Center(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: onBar,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        _BarIconButton(
          icon: Icons.chevron_right,
          tooltip: 'Next $label',
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final onBar = Theme.of(context).colorScheme.onInverseSurface;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        foregroundColor: onBar,
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _BarTextButton extends StatelessWidget {
  const _BarTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBar = theme.colorScheme.onInverseSurface;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: onBar,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: theme.textTheme.labelSmall,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fake app chrome and data
// ---------------------------------------------------------------------------

class _FakeNavRail extends StatelessWidget {
  const _FakeNavRail({required this.compact});

  final bool compact;

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
          for (final item in _navItems)
            _NavEntry(
              item: item,
              selected: item.path == '/today',
              compact: compact,
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
            selected: false,
            compact: compact,
          ),
          _NavEntry(
            item: const _NavItem('', 'Shortcuts', Icons.keyboard_outlined),
            selected: false,
            compact: compact,
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
    required this.compact,
  });

  final _NavItem item;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dense = theme.visualDensity.vertical < 0;
    final entry = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.72)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.input),
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
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: item.label, child: entry) : entry;
  }
}

class _NavItem {
  const _NavItem(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;
}

enum _Role { initiative, support, other }

class _FakeEntry {
  const _FakeEntry({
    required this.id,
    required this.time,
    required this.category,
    required this.role,
    this.mode,
    this.person,
    required this.description,
    this.outcome = '',
    required this.minutes,
  });

  final String id;
  final String time;
  final String category;
  final _Role role;
  final String? mode;
  final String? person;
  final String description;
  final String outcome;
  final int minutes;
}

const _supportModes = ['Pairing', 'Review', 'Mentoring'];

const _entries = [
  _FakeEntry(
    id: 'init-1',
    time: '09:00 – 10:12',
    category: 'Initiatives',
    role: _Role.initiative,
    mode: 'Code review',
    description: 'Review the billing migration PR',
    outcome: 'Two blocking comments posted',
    minutes: 72,
  ),
  _FakeEntry(
    id: 'sup-1',
    time: '10:20 – 10:55',
    category: 'Support',
    role: _Role.support,
    person: 'Priya',
    description: 'Unblock the payments team',
    outcome: 'Merged the fix',
    minutes: 35,
  ),
  _FakeEntry(
    id: 'sup-2',
    time: '11:05 – 11:30',
    category: 'Support',
    role: _Role.support,
    mode: 'Pairing',
    person: 'Sam',
    description: 'Pair on the webhook retry logic',
    minutes: 25,
  ),
  _FakeEntry(
    id: 'oth-1',
    time: '13:00 – 13:30',
    category: 'Other',
    role: _Role.other,
    mode: 'Meetings',
    description: 'Sprint planning',
    minutes: 30,
  ),
];

const _navItems = [
  _NavItem('/today', 'Today', Icons.today_outlined),
  _NavItem('/log', 'Log', Icons.history),
  _NavItem('/initiatives', 'Initiatives', Icons.flag_outlined),
  _NavItem('/support', 'Support', Icons.volunteer_activism_outlined),
  _NavItem('/checkins', 'Check-ins', Icons.event_note_outlined),
];

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${rest}m';
  if (rest == 0) return '${hours}h';
  return '${hours}h ${rest}m';
}
