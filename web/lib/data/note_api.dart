import 'package:grpc/grpc_or_grpcweb.dart';

import '../models/drafts.dart';
import '../models/note.dart';
import '../src/generated/notes.pb.dart' as generated;
import '../src/generated/notes.pbgrpc.dart' as generated_rpc;
import 'grpc_channel.dart';
import 'grpc_errors.dart';

/// A user-facing note failure, with the field the service rejected.
class NoteFailure extends ServiceFailure {
  const NoteFailure(super.message, {super.field});
}

/// Day notes and project notes over Connect/gRPC-Web. Both contexts use the
/// same [Note] model; a project note carries the project's subcategory id in
/// its [Note.initiativeId] slot, and a day note carries only its date.
abstract class NoteApi {
  /// Lists the caller's notes, newest first. A [date] selects day notes and a
  /// [subcategoryId] selects project notes.
  Future<List<Note>> listNotes({String date = '', String subcategoryId = ''});

  Future<Note> createNote(NoteDraft draft);

  Future<Note> updateNote(Note note);

  Future<void> deleteNote(String id);
}

/// The narrow generated-client surface, separated so field mapping and error
/// translation can be tested without a network channel.
abstract class NoteRpc {
  Future<generated.ListNotesResponse> listNotes(
    generated.ListNotesRequest request,
  );

  Future<generated.CreateNoteResponse> createNote(
    generated.CreateNoteRequest request,
  );

  Future<generated.UpdateNoteResponse> updateNote(
    generated.UpdateNoteRequest request,
  );

  Future<generated.DeleteNoteResponse> deleteNote(
    generated.DeleteNoteRequest request,
  );
}

/// The generated Connect client over gRPC-Web.
class GrpcNoteRpc implements NoteRpc {
  GrpcNoteRpc({generated_rpc.NoteServiceClient? client, ApiSession? session})
    : _client =
          client ??
          generated_rpc.NoteServiceClient(
            openAppChannel(),
            interceptors: [
              bearerInterceptor(
                session?.token ?? (() => null),
                onUnauthenticated: session?.onUnauthenticated,
              ),
            ],
          );

  final generated_rpc.NoteServiceClient _client;

  @override
  Future<generated.ListNotesResponse> listNotes(
    generated.ListNotesRequest request,
  ) => _client.listNotes(request);

  @override
  Future<generated.CreateNoteResponse> createNote(
    generated.CreateNoteRequest request,
  ) => _client.createNote(request);

  @override
  Future<generated.UpdateNoteResponse> updateNote(
    generated.UpdateNoteRequest request,
  ) => _client.updateNote(request);

  @override
  Future<generated.DeleteNoteResponse> deleteNote(
    generated.DeleteNoteRequest request,
  ) => _client.deleteNote(request);
}

/// Notes over Connect/gRPC-Web.
class GrpcNoteApi implements NoteApi {
  GrpcNoteApi({NoteRpc? rpc}) : _rpc = rpc ?? GrpcNoteRpc();

  static const _pageSize = 200;

  final NoteRpc _rpc;

  @override
  Future<List<Note>> listNotes({
    String date = '',
    String subcategoryId = '',
  }) async {
    try {
      final notes = <Note>[];
      var pageToken = '';
      do {
        final response = await _rpc.listNotes(
          generated.ListNotesRequest(
            date: date,
            subcategoryId: subcategoryId,
            pageSize: _pageSize,
            pageToken: pageToken,
          ),
        );
        notes.addAll(response.notes.map(noteFromProto));
        pageToken = response.nextPageToken;
      } while (pageToken.isNotEmpty);
      return notes;
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Note> createNote(NoteDraft draft) async {
    try {
      final response = await _rpc.createNote(
        generated.CreateNoteRequest(
          date: draft.date,
          subcategoryId: draft.initiativeId ?? '',
          text: draft.text,
        ),
      );
      return noteFromProto(response.note);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Note> updateNote(Note note) async {
    try {
      final response = await _rpc.updateNote(
        generated.UpdateNoteRequest(
          id: note.id,
          date: note.date,
          subcategoryId: note.initiativeId ?? '',
          text: note.text,
        ),
      );
      return noteFromProto(response.note);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteNote(String id) async {
    try {
      await _rpc.deleteNote(generated.DeleteNoteRequest(id: id));
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  NoteFailure _failure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The service is unreachable. Check that the server is running.',
      unauthenticated: 'Sign in again to save notes.',
      failedPrecondition: 'That note cannot be changed in its current state.',
      notFound: 'That note no longer exists.',
    );
    return NoteFailure(text.message, field: text.field);
  }
}

/// Maps a wire note onto the UI model. A note's subcategory is exposed through
/// the existing `initiativeId` slot, so one model serves both contexts.
Note noteFromProto(generated.Note note) => Note(
  id: note.id,
  date: note.date,
  initiativeId: note.subcategoryId.isEmpty ? null : note.subcategoryId,
  text: note.text,
  createdAt: note.createdAt.toDateTime(),
);
