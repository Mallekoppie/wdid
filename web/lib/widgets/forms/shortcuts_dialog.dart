import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import 'dialog_frame.dart';

Future<void> showShortcutsDialog(BuildContext context) {
  const shortcuts = [
    ('T', 'Start or stop the timer'),
    ('N', 'New work entry'),
    ('S', 'Log support'),
    ('/', 'Focus search in Log'),
    ('G then T', 'Go to Today'),
    ('G then L', 'Go to Log'),
    ('G then I', 'Go to Initiatives'),
    ('G then C', 'Go to Check-ins'),
    ('Esc', 'Close a dialog'),
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => DialogFrame(
      title: 'Keyboard shortcuts',
      subtitle: 'Capture without leaving the keyboard.',
      icon: Icons.keyboard_outlined,
      maxWidth: 460,
      content: Column(
        children: [
          for (final (key, label) in shortcuts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(5),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                        ),
                        child: Text(
                          key,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontFeatures: tabularFigures,
                              ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}
