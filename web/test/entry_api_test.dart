import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/src/generated/entries.pbgrpc.dart' as generated;

class FakeEntryRpc implements EntryRpc {
  Object? error;

  generated.ListEntriesResponse listResponse = generated.ListEntriesResponse();
  generated.WorkEntry entry = generated.WorkEntry();

  generated.ListEntriesRequest? listRequest;
  generated.CreateEntryRequest? createRequest;
  generated.UpdateEntryRequest? updateRequest;
  String? deletedId;

  void _maybeFail() {
    if (error != null) throw error!;
  }

  @override
  Future<generated.ListEntriesResponse> listEntries(
    generated.ListEntriesRequest request,
  ) async {
    listRequest = request;
    _maybeFail();
    return listResponse;
  }

  @override
  Future<generated.CreateEntryResponse> createEntry(
    generated.CreateEntryRequest request,
  ) async {
    createRequest = request;
    _maybeFail();
    return generated.CreateEntryResponse(entry: entry);
  }

  @override
  Future<generated.UpdateEntryResponse> updateEntry(
    generated.UpdateEntryRequest request,
  ) async {
    updateRequest = request;
    _maybeFail();
    return generated.UpdateEntryResponse(entry: entry);
  }

  @override
  Future<generated.DeleteEntryResponse> deleteEntry(
    generated.DeleteEntryRequest request,
  ) async {
    deletedId = request.id;
    _maybeFail();
    return generated.DeleteEntryResponse();
  }
}

generated.WorkEntry protoEntry({
  String id = 'entry-1',
  String categoryId = 'cat-1',
  String subcategoryId = 'sub-1',
  String description = 'Backfill script skeleton',
  String outcome = 'Script runs against staging',
  int minutes = 42,
  String localDate = '2026-10-17',
}) {
  final started = Timestamp.fromDateTime(DateTime.utc(2026, 10, 17, 7, 15));
  return generated.WorkEntry(
    id: id,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    description: description,
    outcome: outcome,
    startedAt: started,
    endedAt: Timestamp.fromDateTime(
      DateTime.utc(2026, 10, 17, 7, 15).add(Duration(minutes: minutes)),
    ),
    duration: duration.Duration(seconds: Int64(minutes * 60)),
    localDate: localDate,
    source: generated.EntrySource.ENTRY_SOURCE_MANUAL,
    createdAt: started,
    updatedAt: started,
  );
}

void main() {
  test('listEntries maps generated entries and asks for today', () async {
    final rpc = FakeEntryRpc()
      ..listResponse = generated.ListEntriesResponse(entries: [protoEntry()]);

    final entries = await GrpcEntryApi(rpc: rpc).listEntries(today: true);

    expect(rpc.listRequest!.today, isTrue);
    expect(entries, hasLength(1));
    expect(entries.first.id, 'entry-1');
    expect(entries.first.categoryId, 'cat-1');
    expect(entries.first.subcategoryId, 'sub-1');
    expect(entries.first.description, 'Backfill script skeleton');
    expect(entries.first.outcome, 'Script runs against staging');
    expect(entries.first.minutes, 42);
    expect(entries.first.localDate, '2026-10-17');
    expect(entries.first.source, EntrySource.manual);
  });

  test('createEntry sends attribution, duration and description', () async {
    final rpc = FakeEntryRpc()..entry = protoEntry();
    final startedAt = DateTime.utc(2026, 10, 17, 9);

    final created = await GrpcEntryApi(rpc: rpc).createEntry(
      EntryDraft(
        categoryId: 'cat-1',
        subcategoryId: 'sub-1',
        description: 'Backfill script skeleton',
        startedAt: startedAt,
        minutes: 25,
      ),
    );

    expect(rpc.createRequest!.categoryId, 'cat-1');
    expect(rpc.createRequest!.subcategoryId, 'sub-1');
    expect(rpc.createRequest!.description, 'Backfill script skeleton');
    expect(rpc.createRequest!.duration.seconds.toInt(), 25 * 60);
    expect(rpc.createRequest!.startedAt.toDateTime(), startedAt);
    expect(
      rpc.createRequest!.source,
      generated.EntrySource.ENTRY_SOURCE_MANUAL,
    );
    expect(created.id, 'entry-1');
  });

  test('updateEntry sends the outcome and never the source', () async {
    final rpc = FakeEntryRpc()..entry = protoEntry(outcome: 'Done');
    final existing = WorkEntry(
      id: 'entry-1',
      categoryId: 'cat-1',
      subcategoryId: 'sub-1',
      description: 'Backfill script skeleton',
      outcome: '',
      startedAt: DateTime.utc(2026, 10, 17, 7, 15),
      endedAt: DateTime.utc(2026, 10, 17, 7, 57),
      minutes: 42,
      localDate: '2026-10-17',
      createdAt: DateTime.utc(2026, 10, 17, 7, 15),
      updatedAt: DateTime.utc(2026, 10, 17, 7, 15),
    );

    final updated = await GrpcEntryApi(rpc: rpc)
        .updateEntry(existing.copyWith(outcome: 'Done'));

    expect(rpc.updateRequest!.id, 'entry-1');
    expect(rpc.updateRequest!.categoryId, 'cat-1');
    expect(rpc.updateRequest!.subcategoryId, 'sub-1');
    expect(rpc.updateRequest!.description, 'Backfill script skeleton');
    expect(rpc.updateRequest!.outcome, 'Done');
    expect(rpc.updateRequest!.duration.seconds.toInt(), 42 * 60);
    expect(updated.outcome, 'Done');
  });

  test('validation failures expose the rejected field', () async {
    final rpc = FakeEntryRpc()
      ..error = GrpcError.invalidArgument('description: is required');

    expect(
      () => GrpcEntryApi(rpc: rpc).createEntry(
        EntryDraft(
          categoryId: 'cat-1',
          description: '',
          startedAt: DateTime.utc(2026, 10, 17, 9),
          minutes: 30,
        ),
      ),
      throwsA(
        isA<EntryFailure>()
            .having((failure) => failure.field, 'field', 'description')
            .having(
              (failure) => failure.message,
              'message',
              'description: is required',
            ),
      ),
    );
  });

  test('deleteEntry sends the entry id', () async {
    final rpc = FakeEntryRpc();

    await GrpcEntryApi(rpc: rpc).deleteEntry('entry-7');

    expect(rpc.deletedId, 'entry-7');
  });
}
