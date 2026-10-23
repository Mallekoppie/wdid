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
  generated.SplitEntryRequest? splitRequest;
  generated.SplitEntryResponse splitResponse = generated.SplitEntryResponse();
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

  @override
  Future<generated.SplitEntryResponse> splitEntry(
    generated.SplitEntryRequest request,
  ) async {
    splitRequest = request;
    _maybeFail();
    return splitResponse;
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

    final listing = await GrpcEntryApi(rpc: rpc).listEntries(today: true);

    expect(rpc.listRequest!.today, isTrue);
    expect(listing.entries, hasLength(1));
    expect(listing.entries.first.id, 'entry-1');
    expect(listing.entries.first.categoryId, 'cat-1');
    expect(listing.entries.first.subcategoryId, 'sub-1');
    expect(listing.entries.first.description, 'Backfill script skeleton');
    expect(listing.entries.first.outcome, 'Script runs against staging');
    expect(listing.entries.first.minutes, 42);
    expect(listing.entries.first.localDate, '2026-10-17');
    expect(listing.entries.first.source, EntrySource.manual);
  });

  test('listEntries sends every filter and keeps overlap ids', () async {
    final rpc = FakeEntryRpc()
      ..listResponse = generated.ListEntriesResponse(
        entries: [protoEntry()],
        overlappingEntryIds: ['entry-1', 'entry-9'],
      );
    final listing = await GrpcEntryApi(rpc: rpc).listEntries(
      fromDate: '2026-10-17',
      toDate: '2026-10-18',
      categoryId: 'cat-1',
      subcategoryId: 'sub-1',
      query: 'backfill',
    );

    expect(rpc.listRequest!.fromDate, '2026-10-17');
    expect(rpc.listRequest!.toDate, '2026-10-18');
    expect(rpc.listRequest!.categoryId, 'cat-1');
    expect(rpc.listRequest!.subcategoryId, 'sub-1');
    expect(rpc.listRequest!.query, 'backfill');
    expect(listing.overlappingIds, {'entry-1', 'entry-9'});
  });

  test('splitEntry sends the offset and returns both halves', () async {
    final rpc = FakeEntryRpc()
      ..splitResponse = generated.SplitEntryResponse(
        first: protoEntry(id: 'entry-1', minutes: 20),
        second: protoEntry(id: 'entry-2', minutes: 22),
      );

    final halves = await GrpcEntryApi(rpc: rpc).splitEntry('entry-1', 20);

    expect(rpc.splitRequest!.id, 'entry-1');
    expect(rpc.splitRequest!.at.seconds.toInt(), 20 * 60);
    expect(halves.first.id, 'entry-1');
    expect(halves.first.minutes, 20);
    expect(halves.second.id, 'entry-2');
    expect(halves.second.minutes, 22);
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
