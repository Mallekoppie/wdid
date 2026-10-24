import 'dart:async';

import 'package:wdid_web/data/milestone_api.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/milestone.dart';

/// In-memory project milestone service used by widget and state tests.
class FakeMilestoneApi implements MilestoneApi {
  FakeMilestoneApi({List<Milestone>? milestones})
    : milestones = milestones ?? [];

  final List<Milestone> milestones;
  final List<MilestoneDraft> drafts = [];

  MilestoneFailure? listFailure;
  MilestoneFailure? createFailure;
  MilestoneFailure? updateFailure;
  MilestoneFailure? deleteFailure;

  /// When set, listing waits for it so tests can observe the loading state.
  Completer<List<Milestone>>? listGate;

  String lastSubcategoryId = '';
  int listCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  int _sequence = 0;

  String _id() {
    _sequence++;
    return 'milestone-$_sequence';
  }

  @override
  Future<List<Milestone>> listMilestones({String subcategoryId = ''}) async {
    listCalls++;
    lastSubcategoryId = subcategoryId;
    if (listGate != null) {
      final gate = listGate!;
      listGate = null;
      milestones
        ..clear()
        ..addAll(await gate.future);
    }
    if (listFailure != null) throw listFailure!;
    return _sorted(
      milestones.where(
        (milestone) =>
            subcategoryId.isEmpty || milestone.subcategoryId == subcategoryId,
      ),
    );
  }

  @override
  Future<Milestone> createMilestone(MilestoneDraft draft) async {
    drafts.add(draft);
    if (createFailure != null) throw createFailure!;
    final now = DateTime.now().toUtc();
    final milestone = Milestone(
      id: _id(),
      subcategoryId: draft.subcategoryId,
      title: draft.title,
      dueDate: draft.dueDate,
      done: draft.done,
      createdAt: now,
      updatedAt: now,
    );
    milestones.add(milestone);
    return milestone;
  }

  @override
  Future<Milestone> updateMilestone(Milestone milestone) async {
    updateCalls++;
    if (updateFailure != null) throw updateFailure!;
    final index = milestones.indexWhere(
      (existing) => existing.id == milestone.id,
    );
    if (index == -1) {
      throw const MilestoneFailure('That milestone no longer exists.');
    }
    milestones[index] = milestone;
    return milestone;
  }

  @override
  Future<void> deleteMilestone(String id) async {
    deleteCalls++;
    if (deleteFailure != null) throw deleteFailure!;
    milestones.removeWhere((milestone) => milestone.id == id);
  }

  static List<Milestone> _sorted(Iterable<Milestone> source) {
    return [...source]..sort((first, second) {
      final firstUndated = first.dueDate.isEmpty;
      final secondUndated = second.dueDate.isEmpty;
      if (firstUndated != secondUndated) return firstUndated ? 1 : -1;
      if (first.dueDate != second.dueDate) {
        return first.dueDate.compareTo(second.dueDate);
      }
      return first.createdAt.compareTo(second.createdAt);
    });
  }
}
