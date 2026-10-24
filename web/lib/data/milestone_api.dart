import 'package:grpc/grpc_or_grpcweb.dart';

import '../models/drafts.dart';
import '../models/milestone.dart';
import '../src/generated/milestones.pb.dart' as generated;
import '../src/generated/milestones.pbgrpc.dart' as generated_rpc;
import 'grpc_channel.dart';
import 'grpc_errors.dart';

/// A user-facing milestone failure, with the field the service rejected.
class MilestoneFailure extends ServiceFailure {
  const MilestoneFailure(super.message, {super.field});
}

/// Project milestones over Connect/gRPC-Web. Every milestone belongs to a
/// subcategory, so listing is always scoped to the open project.
abstract class MilestoneApi {
  Future<List<Milestone>> listMilestones({String subcategoryId = ''});

  Future<Milestone> createMilestone(MilestoneDraft draft);

  Future<Milestone> updateMilestone(Milestone milestone);

  Future<void> deleteMilestone(String id);
}

/// The narrow generated-client surface, separated so field mapping and error
/// translation can be tested without a network channel.
abstract class MilestoneRpc {
  Future<generated.ListMilestonesResponse> listMilestones(
    generated.ListMilestonesRequest request,
  );

  Future<generated.CreateMilestoneResponse> createMilestone(
    generated.CreateMilestoneRequest request,
  );

  Future<generated.UpdateMilestoneResponse> updateMilestone(
    generated.UpdateMilestoneRequest request,
  );

  Future<generated.DeleteMilestoneResponse> deleteMilestone(
    generated.DeleteMilestoneRequest request,
  );
}

/// The generated Connect client over gRPC-Web.
class GrpcMilestoneRpc implements MilestoneRpc {
  GrpcMilestoneRpc({
    generated_rpc.MilestoneServiceClient? client,
    String? Function()? token,
  }) : _client =
           client ??
           generated_rpc.MilestoneServiceClient(
             openAppChannel(),
             interceptors: [bearerInterceptor(token ?? (() => null))],
           );

  final generated_rpc.MilestoneServiceClient _client;

  @override
  Future<generated.ListMilestonesResponse> listMilestones(
    generated.ListMilestonesRequest request,
  ) => _client.listMilestones(request);

  @override
  Future<generated.CreateMilestoneResponse> createMilestone(
    generated.CreateMilestoneRequest request,
  ) => _client.createMilestone(request);

  @override
  Future<generated.UpdateMilestoneResponse> updateMilestone(
    generated.UpdateMilestoneRequest request,
  ) => _client.updateMilestone(request);

  @override
  Future<generated.DeleteMilestoneResponse> deleteMilestone(
    generated.DeleteMilestoneRequest request,
  ) => _client.deleteMilestone(request);
}

/// Milestones over Connect/gRPC-Web.
class GrpcMilestoneApi implements MilestoneApi {
  GrpcMilestoneApi({MilestoneRpc? rpc}) : _rpc = rpc ?? GrpcMilestoneRpc();

  static const _pageSize = 200;

  final MilestoneRpc _rpc;

  @override
  Future<List<Milestone>> listMilestones({String subcategoryId = ''}) async {
    try {
      final milestones = <Milestone>[];
      var pageToken = '';
      do {
        final response = await _rpc.listMilestones(
          generated.ListMilestonesRequest(
            subcategoryId: subcategoryId,
            pageSize: _pageSize,
            pageToken: pageToken,
          ),
        );
        milestones.addAll(response.milestones.map(milestoneFromProto));
        pageToken = response.nextPageToken;
      } while (pageToken.isNotEmpty);
      return milestones;
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Milestone> createMilestone(MilestoneDraft draft) async {
    try {
      final response = await _rpc.createMilestone(
        generated.CreateMilestoneRequest(
          subcategoryId: draft.subcategoryId,
          title: draft.title,
          dueDate: draft.dueDate,
          done: draft.done,
        ),
      );
      return milestoneFromProto(response.milestone);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<Milestone> updateMilestone(Milestone milestone) async {
    try {
      final response = await _rpc.updateMilestone(
        generated.UpdateMilestoneRequest(
          id: milestone.id,
          title: milestone.title,
          dueDate: milestone.dueDate,
          done: milestone.done,
        ),
      );
      return milestoneFromProto(response.milestone);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteMilestone(String id) async {
    try {
      await _rpc.deleteMilestone(generated.DeleteMilestoneRequest(id: id));
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  MilestoneFailure _failure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The service is unreachable. Check that the server is running.',
      unauthenticated: 'Sign in again to save milestones.',
      notFound: 'That milestone no longer exists.',
    );
    return MilestoneFailure(text.message, field: text.field);
  }
}

/// Maps a wire milestone onto the UI model. Exposed so tests can check the
/// mapping without a network channel.
Milestone milestoneFromProto(generated.Milestone milestone) => Milestone(
  id: milestone.id,
  subcategoryId: milestone.subcategoryId,
  title: milestone.title,
  dueDate: milestone.dueDate,
  done: milestone.done,
  createdAt: milestone.createdAt.toDateTime(),
  updatedAt: milestone.updatedAt.toDateTime(),
);
