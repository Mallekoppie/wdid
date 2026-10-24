import 'dart:async';

import 'package:wdid_web/data/note_api.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/note.dart';

/// In-memory day/project note service used by widget and state tests.
class FakeNoteApi implements NoteApi {
  FakeNoteApi({List<Note>? notes}) : notes = notes ?? [];

  final List<Note> notes;
  final List<NoteDraft> drafts = [];

  NoteFailure? listFailure;
  NoteFailure? createFailure;
  NoteFailure? updateFailure;
  NoteFailure? deleteFailure;

  /// When set, listing waits for it so tests can observe the loading state.
  Completer<List<Note>>? listGate;

  /// Like [listGate], but only for a project listing. The initial day-note
  /// load stays responsive while the project tab is still in flight.
  Completer<List<Note>>? projectGate;

  String lastDate = '';
  String lastSubcategoryId = '';
  int listCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int _sequence = 0;

  String _id() {
    _sequence++;
    return 'note-$_sequence';
  }

  @override
  Future<List<Note>> listNotes({
    String date = '',
    String subcategoryId = '',
  }) async {
    listCalls++;
    lastDate = date;
    lastSubcategoryId = subcategoryId;
    if (listGate != null) {
      final gate = listGate!;
      listGate = null;
      notes
        ..clear()
        ..addAll(await gate.future);
    }
    if (subcategoryId.isNotEmpty && projectGate != null) {
      final gate = projectGate!;
      projectGate = null;
      notes
        ..clear()
        ..addAll(await gate.future);
    }
    if (listFailure != null) throw listFailure!;
    final matches =
        notes
            .where(
              (note) =>
                  (date.isEmpty || note.date == date) &&
                  (subcategoryId.isEmpty || note.initiativeId == subcategoryId),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches;
  }

  @override
  Future<Note> createNote(NoteDraft draft) async {
    drafts.add(draft);
    if (createFailure != null) throw createFailure!;
    final note = Note(
      id: _id(),
      date: draft.date,
      initiativeId: draft.initiativeId,
      text: draft.text,
      createdAt: DateTime.now().toUtc(),
    );
    notes.add(note);
    return note;
  }

  @override
  Future<Note> updateNote(Note note) async {
    updateCalls++;
    if (updateFailure != null) throw updateFailure!;
    final index = notes.indexWhere((existing) => existing.id == note.id);
    if (index == -1) {
      throw const NoteFailure('That note no longer exists.');
    }
    notes[index] = note;
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    deleteCalls++;
    if (deleteFailure != null) throw deleteFailure!;
    notes.removeWhere((note) => note.id == id);
  }
}
