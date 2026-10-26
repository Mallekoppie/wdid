import 'enums.dart';
import 'link_ref.dart';

/// A recorded block of work time. This mirrors the service's `WorkEntry`: one
/// category, an optional subcategory, and an authoritative duration.
class WorkEntry {
  const WorkEntry({
    required this.id,
    required this.categoryId,
    this.subcategoryId = '',
    this.description = '',
    this.outcome = '',
    required this.startedAt,
    required this.endedAt,
    required this.minutes,
    required this.localDate,
    this.people = const [],
    this.team = '',
    this.tags = const [],
    this.links = const [],
    this.source = EntrySource.manual,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String categoryId;
  final String subcategoryId;
  final String description;
  final String outcome;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Authoritative duration used for reporting.
  final int minutes;

  /// Grouping day in the configured timezone, `YYYY-MM-DD`.
  final String localDate;

  /// The ordered names on a support entry. A person is a name, not an entity.
  final List<String> people;
  final String team;
  final List<String> tags;
  final List<LinkRef> links;

  final EntrySource source;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get startedLocal => startedAt.toLocal();
  DateTime get endedLocal => endedAt.toLocal();

  WorkEntry copyWith({
    String? categoryId,
    String? subcategoryId,
    String? description,
    String? outcome,
    DateTime? startedAt,
    DateTime? endedAt,
    int? minutes,
    String? localDate,
    List<String>? people,
    String? team,
    List<String>? tags,
    List<LinkRef>? links,
    EntrySource? source,
    DateTime? updatedAt,
  }) {
    return WorkEntry(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      description: description ?? this.description,
      outcome: outcome ?? this.outcome,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      minutes: minutes ?? this.minutes,
      localDate: localDate ?? this.localDate,
      people: people ?? this.people,
      team: team ?? this.team,
      tags: tags ?? this.tags,
      links: links ?? this.links,
      source: source ?? this.source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
