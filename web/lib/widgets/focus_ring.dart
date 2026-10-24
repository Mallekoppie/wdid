import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Paints a visible focus ring around [child] whenever keyboard focus is on
/// the child or one of its descendants.
///
/// Material's default focus treatment is a low-contrast overlay fill. The ring
/// here is an explicit 2 px outline in the theme primary colour so focus stays
/// obvious in every theme, including High Contrast.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, this.borderRadius});

  final Widget child;
  final BorderRadius? borderRadius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  final FocusNode _node = FocusNode(
    debugLabel: 'FocusRing',
    canRequestFocus: false,
    skipTraversal: true,
  );
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_sync);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_sync);
    _node.dispose();
    super.dispose();
  }

  void _sync() {
    var focused = false;
    for (
      FocusNode? node = FocusManager.instance.primaryFocus;
      node != null;
      node = node.parent
    ) {
      if (identical(node, _node)) {
        focused = true;
        break;
      }
    }
    if (focused != _focused && mounted) setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _node,
      canRequestFocus: false,
      skipTraversal: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_focused)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('focus-ring'),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: scheme.primary,
                      width: AppTheme.focusRingWidth,
                    ),
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
