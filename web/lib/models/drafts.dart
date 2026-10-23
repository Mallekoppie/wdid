import 'enums.dart';
import 'initiative.dart';

/// Inputs accepted by the service when creating records. IDs and timestamps are
/// always assigned by the service.
class WorkItemDraft {
  const WorkItemDraft({
    required this.type,
    this.initiativeId,
    this.category,
    this.categoryLabel,
    required this.startedAt,
    required this.minutes,
    required this.summary,
    this.outcome = '',
    this.notes = '',
    this.links = const [],
    this.tags = const [],
    this.person,
    this.team,
    this.source = 'manual',
  });

  final WorkType type;
  final String? initiativeId;
  final String? category;
  final String? categoryLabel;
  final DateTime startedAt;
  final int minutes;
  final String summary;
  final String outcome;
  final String notes;
  final List<LinkRef> links;
  final List<String> tags;
  final String? person;
  final String? team;
  final String source;
}

/// Inputs accepted by `EntryService` when capturing a work entry. IDs and the
/// local grouping day are assigned by the service.
class EntryDraft {
  const EntryDraft({
    required this.categoryId,
    this.subcategoryId = '',
    required this.description,
    this.outcome = '',
    required this.startedAt,
    this.minutes = 0,
    this.person = '',
    this.team = '',
    this.tags = const [],
    this.links = const [],
    this.source = EntrySource.manual,
  });

  final String categoryId;
  final String subcategoryId;
  final String description;
  final String outcome;
  final DateTime startedAt;
  final int minutes;
  final String person;
  final String team;
  final List<String> tags;
  final List<LinkRef> links;
  final EntrySource source;
}

class InitiativeDraft {
  const InitiativeDraft({
    required this.name,
    this.summary = '',
    this.targetOutcome = '',
    this.status = InitiativeStatus.active,
    this.progress = 0,
    this.targetDate,
    this.tags = const [],
    this.links = const [],
  });

  final String name;
  final String summary;
  final String targetOutcome;
  final InitiativeStatus status;
  final int progress;
  final DateTime? targetDate;
  final List<String> tags;
  final List<LinkRef> links;
}

class CheckInDraft {
  const CheckInDraft({
    required this.periodStart,
    required this.periodEnd,
    this.focusNotes = '',
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final String focusNotes;
}

class NoteDraft {
  const NoteDraft({required this.date, this.initiativeId, required this.text});

  final String date;
  final String? initiativeId;
  final String text;
}
