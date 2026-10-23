import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import '../models/drafts.dart';
import '../models/enums.dart';
import '../models/initiative.dart' show LinkRef;
import '../models/work_entry.dart';
import '../src/generated/categories.pb.dart' as categories_generated;
import '../src/generated/entries.pbgrpc.dart' as generated;
import 'grpc_channel.dart';
import 'grpc_errors.dart';

/// A user-facing entry failure, with the field the service rejected.
class EntryFailure extends ServiceFailure {
  const EntryFailure(super.message, {super.field});
}

/// The work-entry operations the Today screen consumes. Every call is scoped
/// to the signed-in account by the service.
abstract class EntryApi {
  Future<List<WorkEntry>> listEntries({
    String localDate = '',
    bool today = false,
    DateTime? from,
    DateTime? to,
    String categoryId = '',
    String subcategoryId = '',
    String person = '',
    String query = '',
  });

  Future<WorkEntry> createEntry(EntryDraft draft);

  Future<WorkEntry> updateEntry(WorkEntry entry);

  Future<void> deleteEntry(String id);
}

/// The narrow generated-client surface, separated so field mapping and error
/// translation can be tested without a network channel.
abstract class EntryRpc {
  Future<generated.ListEntriesResponse> listEntries(
    generated.ListEntriesRequest request,
  );

  Future<generated.CreateEntryResponse> createEntry(
    generated.CreateEntryRequest request,
  );

  Future<generated.UpdateEntryResponse> updateEntry(
    generated.UpdateEntryRequest request,
  );

  Future<generated.DeleteEntryResponse> deleteEntry(
    generated.DeleteEntryRequest request,
  );
}

/// The generated Connect client over gRPC-Web.
class GrpcEntryRpc implements EntryRpc {
  GrpcEntryRpc({
    generated.EntryServiceClient? client,
    String? Function()? token,
  }) : _client =
           client ??
           generated.EntryServiceClient(
             openAppChannel(),
             interceptors: [bearerInterceptor(token ?? (() => null))],
           );

  final generated.EntryServiceClient _client;

  @override
  Future<generated.ListEntriesResponse> listEntries(
    generated.ListEntriesRequest request,
  ) => _client.listEntries(request);

  @override
  Future<generated.CreateEntryResponse> createEntry(
    generated.CreateEntryRequest request,
  ) => _client.createEntry(request);

  @override
  Future<generated.UpdateEntryResponse> updateEntry(
    generated.UpdateEntryRequest request,
  ) => _client.updateEntry(request);

  @override
  Future<generated.DeleteEntryResponse> deleteEntry(
    generated.DeleteEntryRequest request,
  ) => _client.deleteEntry(request);
}

/// Work entries over Connect/gRPC-Web.
class GrpcEntryApi implements EntryApi {
  GrpcEntryApi({EntryRpc? rpc}) : _rpc = rpc ?? GrpcEntryRpc();

  static const _pageSize = 200;

  final EntryRpc _rpc;

  @override
  Future<List<WorkEntry>> listEntries({
    String localDate = '',
    bool today = false,
    DateTime? from,
    DateTime? to,
    String categoryId = '',
    String subcategoryId = '',
    String person = '',
    String query = '',
  }) async {
    try {
      return [
        for (final response in await _pages(
          (token) => _rpc.listEntries(
            generated.ListEntriesRequest(
              localDate: localDate,
              today: today,
              from: from == null ? null : Timestamp.fromDateTime(from.toUtc()),
              to: to == null ? null : Timestamp.fromDateTime(to.toUtc()),
              categoryId: categoryId,
              subcategoryId: subcategoryId,
              person: person,
              query: query,
              pageSize: _pageSize,
              pageToken: token,
            ),
          ),
          (response) => response.nextPageToken,
        ))
          ...response.entries.map(entryFromProto),
      ];
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  Future<List<T>> _pages<T>(
    Future<T> Function(String token) fetch,
    String Function(T response) nextToken,
  ) async {
    final pages = <T>[];
    var token = '';
    do {
      final page = await fetch(token);
      pages.add(page);
      token = nextToken(page);
    } while (token.isNotEmpty);
    return pages;
  }

  @override
  Future<WorkEntry> createEntry(EntryDraft draft) async {
    try {
      final response = await _rpc.createEntry(
        generated.CreateEntryRequest(
          categoryId: draft.categoryId,
          subcategoryId: draft.subcategoryId,
          description: draft.description,
          outcome: draft.outcome,
          startedAt: Timestamp.fromDateTime(draft.startedAt.toUtc()),
          duration: draft.minutes > 0 ? _minutesDuration(draft.minutes) : null,
          person: draft.person,
          team: draft.team,
          tags: draft.tags,
          links: _linksToProto(draft.links),
          source: _sourceToProto(draft.source),
        ),
      );
      return entryFromProto(response.entry);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<WorkEntry> updateEntry(WorkEntry entry) async {
    try {
      final response = await _rpc.updateEntry(
        generated.UpdateEntryRequest(
          id: entry.id,
          categoryId: entry.categoryId,
          subcategoryId: entry.subcategoryId,
          description: entry.description,
          outcome: entry.outcome,
          startedAt: Timestamp.fromDateTime(entry.startedAt.toUtc()),
          endedAt: Timestamp.fromDateTime(entry.endedAt.toUtc()),
          duration: _minutesDuration(entry.minutes),
          person: entry.person,
          team: entry.team,
          tags: entry.tags,
          links: _linksToProto(entry.links),
        ),
      );
      return entryFromProto(response.entry);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    try {
      await _rpc.deleteEntry(generated.DeleteEntryRequest(id: id));
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  EntryFailure _failure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The service is unreachable. Check that the server is running.',
      unauthenticated: 'Sign in again to capture work.',
      failedPrecondition: 'That entry cannot be changed in its current state.',
      notFound: 'That entry no longer exists.',
    );
    return EntryFailure(text.message, field: text.field);
  }
}

/// Maps a wire entry onto the UI model. Exposed for tests that want to check
/// the mapping without a network channel.
WorkEntry entryFromProto(generated.WorkEntry entry) => WorkEntry(
  id: entry.id,
  categoryId: entry.categoryId,
  subcategoryId: entry.subcategoryId,
  description: entry.description,
  outcome: entry.outcome,
  startedAt: entry.startedAt.toDateTime(),
  endedAt: entry.endedAt.toDateTime(),
  minutes: entry.duration.seconds.toInt() ~/ 60,
  localDate: entry.localDate,
  person: entry.person,
  team: entry.team,
  tags: entry.tags,
  links: entry.links
      .map((link) => LinkRef(label: link.label, url: link.url))
      .toList(),
  source: entrySourceFromProto(entry.source),
  createdAt: entry.createdAt.toDateTime(),
  updatedAt: entry.updatedAt.toDateTime(),
);

duration.Duration _minutesDuration(int minutes) =>
    duration.Duration(seconds: Int64(minutes * 60));

List<categories_generated.Link> _linksToProto(List<LinkRef> links) => [
  for (final link in links)
    categories_generated.Link(label: link.label, url: link.url),
];

generated.EntrySource _sourceToProto(EntrySource source) =>
    source == EntrySource.timer
    ? generated.EntrySource.ENTRY_SOURCE_TIMER
    : generated.EntrySource.ENTRY_SOURCE_MANUAL;

/// Maps the wire source onto the UI enum.
EntrySource entrySourceFromProto(generated.EntrySource source) =>
    source == generated.EntrySource.ENTRY_SOURCE_TIMER
    ? EntrySource.timer
    : EntrySource.manual;
