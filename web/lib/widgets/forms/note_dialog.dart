import 'package:flutter/material.dart';

import '../../models/note.dart';
import '../../state/app_state.dart';
import '../../utils/time_utils.dart';
import 'dialog_frame.dart';

Future<Note?> showNoteDialog(
  BuildContext context, {
  required AppState state,
  String? initiativeId,
  Note? existing,
  String title = 'Add note',
  String? subtitle,
  String initialText = '',
}) {
  return showDialog<Note>(
    context: context,
    builder: (context) => _NoteDialog(
      state: state,
      initiativeId: initiativeId,
      existing: existing,
      title: title,
      subtitle: subtitle,
      initialText: initialText.isEmpty ? existing?.text ?? '' : initialText,
    ),
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.state,
    this.initiativeId,
    this.existing,
    required this.title,
    this.subtitle,
    this.initialText = '',
  });

  final AppState state;
  final String? initiativeId;
  final Note? existing;
  final String title;
  final String? subtitle;
  final String initialText;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Write a note first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final trimmed = _text.text.trim();
      final note = widget.existing != null
          ? await widget.state.updateNote(
              widget.existing!.copyWith(text: trimmed),
            )
          : await widget.state.addNote(
              text: trimmed,
              initiativeId: widget.initiativeId,
              date: DateTime.now(),
            );
      if (!mounted) return;
      Navigator.of(context).pop(note);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the note. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DialogFrame(
      title: widget.title,
      subtitle: widget.subtitle ?? isoDate(DateTime.now()),
      icon: Icons.notes_outlined,
      maxWidth: 520,
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 5,
        maxLines: 10,
        decoration: const InputDecoration(
          hintText: 'Decisions, context, or things to revisit…',
        ),
      ),
      actions: Row(
        children: [
          if (_error != null) Expanded(child: FormError(message: _error!)),
          const Spacer(),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save note'),
          ),
        ],
      ),
    );
  }
}
