import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/note_api.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/note.dart';
import 'package:wdid_web/src/generated/notes.pb.dart' as generated;

class _FakeNoteRpc implements NoteRpc {
  final List<generated.ListNotesRequest> listRequests = [];
  final List<generated.CreateNoteRequest> createRequests = [];
  final List<generated.UpdateNoteRequest> updateRequests = [];
  final List<generated.DeleteNoteRequest> deleteRequests = [];

  generated.ListNotesResponse? listResponse;
  generated.CreateNoteResponse? createResponse;
  generated.UpdateNoteResponse? updateResponse;
  Object? failure;

  @override
  Future<generated.ListNotesResponse> listNotes(
    generated.ListNotesRequest request,
  ) async {
    listRequests.add(request);
    if (failure != null) throw failure!;
    final response =
        listResponse ??
        generated.ListNotesResponse(
          notes: [
            generated.Note(
              id: 'note-1',
              date: '2026-10-20',
              text: 'Day note',
              createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20, 18)),
            ),
            generated.Note(
              id: 'note-2',
              subcategoryId: 'sub-1',
              text: 'Project note',
              createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 19, 12)),
            ),
          ],
        );
    // A paged response is only handed out once, so the client terminates.
    if (listRequests.length > 1 && response.nextPageToken.isNotEmpty) {
      return generated.ListNotesResponse();
    }
    return response;
  }

  @override
  Future<generated.CreateNoteResponse> createNote(
    generated.CreateNoteRequest request,
  ) async {
    createRequests.add(request);
    if (failure != null) throw failure!;
    return createResponse ??
        generated.CreateNoteResponse(
          note: generated.Note(
            id: 'note-created',
            date: request.date,
            subcategoryId: request.subcategoryId,
            text: request.text,
            createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20, 18)),
          ),
        );
  }

  @override
  Future<generated.UpdateNoteResponse> updateNote(
    generated.UpdateNoteRequest request,
  ) async {
    updateRequests.add(request);
    if (failure != null) throw failure!;
    return updateResponse ??
        generated.UpdateNoteResponse(
          note: generated.Note(
            id: request.id,
            date: request.date,
            subcategoryId: request.subcategoryId,
            text: request.text,
            createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20, 18)),
          ),
        );
  }

  @override
  Future<generated.DeleteNoteResponse> deleteNote(
    generated.DeleteNoteRequest request,
  ) async {
    deleteRequests.add(request);
    if (failure != null) throw failure!;
    return generated.DeleteNoteResponse();
  }
}

void main() {
  test('lists day and project notes through the generated contract', () async {
    final rpc = _FakeNoteRpc();
    final api = GrpcNoteApi(rpc: rpc);

    final notes = await api.listNotes(date: '2026-10-20');

    expect(rpc.listRequests, hasLength(1));
    expect(rpc.listRequests.single.date, '2026-10-20');
    expect(rpc.listRequests.single.subcategoryId, '');
    expect(notes, hasLength(2));
    expect(notes.first.id, 'note-1');
    expect(notes.first.date, '2026-10-20');
    expect(notes.first.initiativeId, isNull);
    expect(notes.last.initiativeId, 'sub-1');
    expect(notes.first.createdAt, DateTime.utc(2026, 10, 20, 18));
  });

  test('follows list pagination until the token is empty', () async {
    final rpc = _FakeNoteRpc()
      ..listResponse = generated.ListNotesResponse(
        notes: [
          generated.Note(
            id: 'note-1',
            date: '2026-10-20',
            text: 'First page',
            createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20)),
          ),
        ],
        nextPageToken: '2',
      );
    final api = GrpcNoteApi(rpc: rpc);

    await api.listNotes(subcategoryId: 'sub-1');

    expect(rpc.listRequests, hasLength(2));
    expect(rpc.listRequests.first.pageToken, '');
    expect(rpc.listRequests.first.subcategoryId, 'sub-1');
    expect(rpc.listRequests.last.pageToken, '2');
  });

  test('maps a day-note draft and a project-note draft', () async {
    final rpc = _FakeNoteRpc();
    final api = GrpcNoteApi(rpc: rpc);

    final day = await api.createNote(
      const NoteDraft(date: '2026-10-20', text: 'Day note'),
    );
    final project = await api.createNote(
      const NoteDraft(
        date: '2026-10-20',
        initiativeId: 'sub-1',
        text: 'Project note',
      ),
    );

    expect(rpc.createRequests, hasLength(2));
    expect(rpc.createRequests.first.subcategoryId, '');
    expect(rpc.createRequests.last.subcategoryId, 'sub-1');
    expect(rpc.createRequests.last.date, '2026-10-20');
    expect(day.initiativeId, isNull);
    expect(project.initiativeId, 'sub-1');
    expect(project.text, 'Project note');
  });

  test('updates and deletes a note by id', () async {
    final rpc = _FakeNoteRpc();
    final api = GrpcNoteApi(rpc: rpc);
    final note = Note(
      id: 'note-1',
      date: '2026-10-20',
      initiativeId: 'sub-1',
      text: 'Rewritten',
      createdAt: DateTime.utc(2026, 10, 20),
    );

    final updated = await api.updateNote(note);
    await api.deleteNote(note.id);

    expect(rpc.updateRequests.single.id, 'note-1');
    expect(rpc.updateRequests.single.subcategoryId, 'sub-1');
    expect(rpc.updateRequests.single.text, 'Rewritten');
    expect(updated.text, 'Rewritten');
    expect(rpc.deleteRequests.single.id, 'note-1');
  });

  test('maps a validation failure onto the rejected field', () async {
    final rpc = _FakeNoteRpc()
      ..failure = GrpcError.invalidArgument(
        'invalid_argument: text: is required',
      );
    final api = GrpcNoteApi(rpc: rpc);

    await expectLater(
      api.createNote(const NoteDraft(date: '2026-10-20', text: '')),
      throwsA(
        isA<NoteFailure>()
            .having((failure) => failure.field, 'field', 'text')
            .having(
              (failure) => failure.message,
              'message',
              'text: is required',
            ),
      ),
    );
  });

  test('maps an unavailable service to a retryable message', () async {
    final rpc = _FakeNoteRpc()..failure = GrpcError.unavailable('down');
    final api = GrpcNoteApi(rpc: rpc);

    await expectLater(
      api.listNotes(),
      throwsA(
        isA<NoteFailure>().having(
          (failure) => failure.message,
          'message',
          contains('unreachable'),
        ),
      ),
    );
  });
}
