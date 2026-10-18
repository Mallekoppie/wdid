import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Small Markdown renderer for summaries.
///
/// Supports headings, bullet and numbered lists, blockquotes, rules, bold and
/// inline code — enough for the AI summary contract without pulling a large
/// rendering dependency into the shell.
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.markdown, {super.key, this.dense = false});

  final String markdown;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = markdown.trim().split('\n');
    final children = <Widget>[];
    final bodyStyle = (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
        ?.copyWith(height: 1.5);
    final bulletStyle = bodyStyle?.copyWith(color: scheme.onSurface);

    for (var index = 0; index < lines.length; index++) {
      final raw = lines[index];
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) {
          children.add(SizedBox(height: dense ? 6 : 8));
        }
        continue;
      }
      if (line.trim() == '---') {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Divider(height: 1),
        ));
        continue;
      }
      if (line.startsWith('### ')) {
        children.add(Padding(
          padding: EdgeInsets.only(top: dense ? 6 : 10, bottom: 2),
          child: Text(
            line.substring(4),
            style: theme.textTheme.titleSmall,
          ),
        ));
        continue;
      }
      if (line.startsWith('## ')) {
        children.add(Padding(
          padding: EdgeInsets.only(top: dense ? 8 : 14, bottom: 3),
          child: Text(
            line.substring(3),
            style: theme.textTheme.titleMedium,
          ),
        ));
        continue;
      }
      if (line.startsWith('# ')) {
        children.add(Padding(
          padding: EdgeInsets.only(top: dense ? 8 : 14, bottom: 4),
          child: Text(
            line.substring(2),
            style: theme.textTheme.titleLarge,
          ),
        ));
        continue;
      }
      if (line.startsWith('> ')) {
        children.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.tertiary, width: 2),
            ),
            color: scheme.tertiaryContainer.withValues(alpha: 0.18),
          ),
          child: _richText(
            context,
            line.substring(2),
            bodyStyle?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ));
        continue;
      }
      final bulletMatch = RegExp(r'^[-*]\s+(.*)$').firstMatch(line);
      if (bulletMatch != null) {
        children.add(_listItem(context, bulletMatch.group(1)!, bodyStyle, numbered: null));
        continue;
      }
      final numberMatch = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (numberMatch != null) {
        children.add(_listItem(
          context,
          numberMatch.group(2)!,
          bodyStyle,
          numbered: numberMatch.group(1)!,
        ));
        continue;
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: _richText(context, line, bulletStyle),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _listItem(
    BuildContext context,
    String text,
    TextStyle? style, {
    required String? numbered,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: numbered == null ? 14 : 22,
            child: Text(
              numbered == null ? '•' : '$numbered.',
              style: style?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: _richText(context, text, style)),
        ],
      ),
    );
  }

  Widget _richText(BuildContext context, String text, TextStyle? style) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    final pattern = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
      } else {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: (base?.fontSize ?? 13) - 0.5,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ),
        ));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
