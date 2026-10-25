import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state_scope.dart';
import 'app_header.dart';
import 'forms/entry_form.dart';
import 'forms/shortcuts_dialog.dart';
import 'forms/support_dialog.dart';
import 'nav_rail.dart';
import 'timer_actions.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _awaitingG = false;
  Timer? _gTimer;

  @override
  void dispose() {
    _gTimer?.cancel();
    super.dispose();
  }

  bool get _isEditing {
    // The primary focus node of a text field belongs to the internal Focus
    // widget that EditableText builds, so the focused widget is never
    // EditableText itself. Walk up from the focused context instead.
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _beginGoSequence() {
    _awaitingG = true;
    _gTimer?.cancel();
    _gTimer = Timer(const Duration(milliseconds: 1200), () {
      _awaitingG = false;
    });
  }

  Future<void> _toggleTimer() async {
    final state = AppStateScope.read(context);
    try {
      if (state.activeTimer == null) {
        await state.startTimer();
        if (!mounted) return;
        final timer = state.activeTimer;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Timer started · ${timer == null ? 'timer' : state.timerLabel(timer)}',
            ),
          ),
        );
      } else {
        final result = await stopTimerWithDecision(context, state: state);
        if (!mounted || result == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          stoppedTimerSnackBar(context, state, result),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _newEntry() async {
    final item = await showServiceEntryDialog(context);
    if (item != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry saved')));
    }
  }

  Future<void> _logSupport() async {
    final state = AppStateScope.read(context);
    final saved = await showServiceSupportDialog(context, state: state);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Support entry saved')));
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_isEditing) return KeyEventResult.ignored;

    if (event.character == '?' || key == LogicalKeyboardKey.question) {
      showShortcutsDialog(context);
      return KeyEventResult.handled;
    }

    if (_awaitingG) {
      _awaitingG = false;
      _gTimer?.cancel();
      if (key == LogicalKeyboardKey.keyT) {
        context.go('/today');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyL) {
        context.go('/log');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyI) {
        context.go('/initiatives');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        context.go('/checkins');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        context.go('/support');
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.keyG) {
      _beginGoSequence();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      unawaited(_toggleTimer());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      unawaited(_newEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      unawaited(_logSupport());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.slash) {
      final state = AppStateScope.read(context);
      context.go('/log');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state.requestSearchFocus();
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        body: Column(
          children: [
            const AppHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 820;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NavRail(
                        currentPath: widget.currentPath,
                        compact: compact,
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: scheme.outlineVariant,
                      ),
                      Expanded(child: widget.child),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
