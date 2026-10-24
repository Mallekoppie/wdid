import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/milestone_api.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/milestone.dart';
import 'package:wdid_web/src/generated/milestones.pb.dart' as generated;

class _FakeMilestoneRpc implements MilestoneRpc {
  final List<generated.ListMilestonesRequest> listRequests = [];
  final List<generated.CreateMilestoneRequest> createRequests = [];
  final List<generated.UpdateMilestoneRequest> updateRequests = [];
  final List<generated.DeleteMilestoneRequest> deleteRequests = [];

  generated.ListMilestonesResponse? listResponse;
  generated.CreateMilestoneResponse? createResponse;
  generated.UpdateMilestoneResponse? updateResponse;
  Object? failure;

  @override
  Future<generated.ListMilestonesResponse> listMilestones(
    generated.ListMilestonesRequest request,
  ) async {
    listRequests.add(request);
    if (failure != null) throw failure!;
    final response =
        listResponse ??
        generated.ListMilestonesResponse(
          milestones: [
            generated.Milestone(
              id: 'milestone-1',
              subcategoryId: 'sub-1',
              title: 'Plan the backfill',
              createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20)),
              updatedAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20)),
            ),
            generated.Milestone(
              id: 'milestone-2',
              subcategoryId: 'sub-1',
              title: 'Ship to production',
              dueDate: '2026-11-15',
              done: true,
              createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 19)),
              updatedAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 21)),
            ),
          ],
        );
    // A paged response is only handed out once, so the client terminates.
    if (listRequests.length > 1 && response.nextPageToken.isNotEmpty) {
      return generated.ListMilestonesResponse();
    }
    return response;
  }

  @override
  Future<generated.CreateMilestoneResponse> createMilestone(
    generated.CreateMilestoneRequest request,
  ) async {
    createRequests.add(request);
    if (failure != null) throw failure!;
    return createResponse ??
        generated.CreateMilestoneResponse(
          milestone: generated.Milestone(
            id: 'milestone-created',
            subcategoryId: request.subcategoryId,
            title: request.title,
            dueDate: request.dueDate,
            done: request.done,
            createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 22)),
            updatedAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 22)),
          ),
        );
  }

  @override
  Future<generated.UpdateMilestoneResponse> updateMilestone(
    generated.UpdateMilestoneRequest request,
  ) async {
    updateRequests.add(request);
    if (failure != null) throw failure!;
    return updateResponse ??
        generated.UpdateMilestoneResponse(
          milestone: generated.Milestone(
            id: request.id,
            subcategoryId: 'sub-1',
            title: request.title,
            dueDate: request.dueDate,
            done: request.done,
            createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20)),
            updatedAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 22)),
          ),
        );
  }

  @override
  Future<generated.DeleteMilestoneResponse> deleteMilestone(
    generated.DeleteMilestoneRequest request,
  ) async {
    deleteRequests.add(request);
    if (failure != null) throw failure!;
    return generated.DeleteMilestoneResponse();
  }
}

void main() {
  test(
    'lists a project\'s milestones through the generated contract',
    () async {
      final rpc = _FakeMilestoneRpc();
      final api = GrpcMilestoneApi(rpc: rpc);

      final milestones = await api.listMilestones(subcategoryId: 'sub-1');

      expect(rpc.listRequests, hasLength(1));
      expect(rpc.listRequests.single.subcategoryId, 'sub-1');
      expect(milestones, hasLength(2));
      expect(milestones.first.id, 'milestone-1');
      expect(milestones.first.subcategoryId, 'sub-1');
      expect(milestones.first.title, 'Plan the backfill');
      expect(milestones.first.dueDate, '');
      expect(milestones.first.done, isFalse);
      expect(milestones.last.dueDate, '2026-11-15');
      expect(milestones.last.done, isTrue);
      expect(milestones.last.createdAt, DateTime.utc(2026, 10, 19));
      expect(milestones.last.updatedAt, DateTime.utc(2026, 10, 21));
    },
  );

  test('follows list pagination until the token is empty', () async {
    final rpc = _FakeMilestoneRpc()
      ..listResponse = generated.ListMilestonesResponse(
        milestones: [
          generated.Milestone(
            id: 'milestone-1',
            subcategoryId: 'sub-1',
            title: 'First page',
            createdAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20)),
            updatedAt: Timestamp.fromDateTime(DateTime.utc(2026, 10, 20)),
          ),
        ],
        nextPageToken: '2',
      );
    final api = GrpcMilestoneApi(rpc: rpc);

    await api.listMilestones(subcategoryId: 'sub-1');

    expect(rpc.listRequests, hasLength(2));
    expect(rpc.listRequests.first.pageToken, '');
    expect(rpc.listRequests.first.subcategoryId, 'sub-1');
    expect(rpc.listRequests.last.pageToken, '2');
  });

  test('creates a milestone with an optional due date and done flag', () async {
    final rpc = _FakeMilestoneRpc();
    final api = GrpcMilestoneApi(rpc: rpc);

    final undated = await api.createMilestone(
      const MilestoneDraft(subcategoryId: 'sub-1', title: 'Plan the backfill'),
    );
    final dated = await api.createMilestone(
      const MilestoneDraft(
        subcategoryId: 'sub-1',
        title: 'Ship to production',
        dueDate: '2026-11-15',
        done: true,
      ),
    );

    expect(rpc.createRequests, hasLength(2));
    expect(rpc.createRequests.first.subcategoryId, 'sub-1');
    expect(rpc.createRequests.first.dueDate, '');
    expect(rpc.createRequests.first.done, isFalse);
    expect(rpc.createRequests.last.dueDate, '2026-11-15');
    expect(rpc.createRequests.last.done, isTrue);
    expect(undated.dueDate, '');
    expect(dated.done, isTrue);
  });

  test('updates and deletes a milestone by id', () async {
    final rpc = _FakeMilestoneRpc();
    final api = GrpcMilestoneApi(rpc: rpc);
    final milestone = Milestone(
      id: 'milestone-1',
      subcategoryId: 'sub-1',
      title: 'Ship to production',
      dueDate: '2026-11-15',
      done: true,
      createdAt: DateTime.utc(2026, 10, 20),
      updatedAt: DateTime.utc(2026, 10, 20),
    );

    final updated = await api.updateMilestone(milestone);
    await api.deleteMilestone(milestone.id);

    expect(rpc.updateRequests.single.id, 'milestone-1');
    expect(rpc.updateRequests.single.title, 'Ship to production');
    expect(rpc.updateRequests.single.dueDate, '2026-11-15');
    expect(rpc.updateRequests.single.done, isTrue);
    expect(updated.done, isTrue);
    expect(rpc.deleteRequests.single.id, 'milestone-1');
  });

  test('maps a validation failure onto the rejected field', () async {
    final rpc = _FakeMilestoneRpc()
      ..failure = GrpcError.invalidArgument(
        'invalid_argument: title: is required',
      );
    final api = GrpcMilestoneApi(rpc: rpc);

    await expectLater(
      api.createMilestone(
        const MilestoneDraft(subcategoryId: 'sub-1', title: ''),
      ),
      throwsA(
        isA<MilestoneFailure>()
            .having((failure) => failure.field, 'field', 'title')
            .having(
              (failure) => failure.message,
              'message',
              'title: is required',
            ),
      ),
    );
  });

  test('maps an unavailable service to a retryable message', () async {
    final rpc = _FakeMilestoneRpc()..failure = GrpcError.unavailable('down');
    final api = GrpcMilestoneApi(rpc: rpc);

    await expectLater(
      api.listMilestones(subcategoryId: 'sub-1'),
      throwsA(
        isA<MilestoneFailure>().having(
          (failure) => failure.message,
          'message',
          contains('unreachable'),
        ),
      ),
    );
  });
}
