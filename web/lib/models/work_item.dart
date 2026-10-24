import 'enums.dart';
import 'initiative.dart';

/// A block of time. Mirrors the `WorkItem` entity in `plan.md`.
class WorkItem {
  const WorkItem({
    required this.id,
    required this.type,
    this.initiativeId,
    this.category,
    this.categoryLabel,
    required this.startedAt,
    required this.endedAt,
    required this.minutes,
    required this.localDate,
    this.summary = '',
    this.outcome = '',
    this.notes = '',
    this.links = const [],
    this.tags = const [],
    this.person,
    this.team,
    this.source = 'manual',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final WorkType type;
  final String? initiativeId;
  final String? category;
  final String? categoryLabel;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Authoritative duration used for reporting.
  final int minutes;

  /// Grouping day in the configured timezone, `YYYY-MM-DD`.
  final String localDate;
  final String summary;
  final String outcome;
  final String notes;
  final List<LinkRef> links;
  final List<String> tags;
  final String? person;
  final String? team;

  /// `timer` or `manual`.
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get startedLocal => startedAt.toLocal();
  DateTime get endedLocal => endedAt.toLocal();

  bool get isSupport =>
      type == WorkType.category && (person?.isNotEmpty ?? false);

  SupportMode? get supportMode =>
      isSupport ? SupportMode.parse(category) : null;

  String attributionLabel(List<Initiative> initiatives) {
    if (isSupport) {
      final mode = supportMode?.label ?? 'Support';
      return person == null ? 'Support · $mode' : 'Support · $person · $mode';
    }
    if (type == WorkType.initiative && initiativeId != null) {
      for (final initiative in initiatives) {
        if (initiative.id == initiativeId) return initiative.name;
      }
      return 'Initiative';
    }
    return categoryLabel ?? 'Other work';
  }

  WorkItem copyWith({
    String? id,
    WorkType? type,
    String? initiativeId,
    String? category,
    String? categoryLabel,
    DateTime? startedAt,
    DateTime? endedAt,
    int? minutes,
    String? localDate,
    String? summary,
    String? outcome,
    String? notes,
    List<LinkRef>? links,
    List<String>? tags,
    String? person,
    String? team,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearInitiative = false,
    bool clearPerson = false,
  }) {
    return WorkItem(
      id: id ?? this.id,
      type: type ?? this.type,
      initiativeId: clearInitiative
          ? null
          : (initiativeId ?? this.initiativeId),
      category: category ?? this.category,
      categoryLabel: categoryLabel ?? this.categoryLabel,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      minutes: minutes ?? this.minutes,
      localDate: localDate ?? this.localDate,
      summary: summary ?? this.summary,
      outcome: outcome ?? this.outcome,
      notes: notes ?? this.notes,
      links: links ?? this.links,
      tags: tags ?? this.tags,
      person: clearPerson ? null : (person ?? this.person),
      team: team ?? this.team,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory WorkItem.fromJson(Map<String, dynamic> json) {
    final startedAt = _date(json['startedAt']) ?? DateTime.now();
    final localDate = json['localDate']?.toString() ?? _isoDate(startedAt);
    final supportJson = json['support'] is Map
        ? Map<String, dynamic>.from(json['support'] as Map)
        : null;
    final kind = json['kind']?.toString();
    final type = json['type'] != null
        ? WorkType.parse(json['type'])
        : kind == 'initiative'
        ? WorkType.initiative
        : WorkType.category;
    final supportMode = _nullableString(supportJson?['mode']);
    return WorkItem(
      id: json['id'].toString(),
      type: type,
      initiativeId: _nullableString(json['initiativeId']),
      category: supportMode ?? _nullableString(json['category']),
      categoryLabel: supportMode != null
          ? SupportMode.parse(supportMode).label
          : _nullableString(json['categoryLabel']),
      startedAt: startedAt,
      endedAt: _date(json['endedAt']) ?? startedAt,
      minutes: (json['minutes'] as num?)?.round() ?? 0,
      localDate: localDate,
      summary:
          json['summary']?.toString() ?? json['description']?.toString() ?? '',
      outcome:
          json['outcome']?.toString() ??
          _nullableString(supportJson?['impact']) ??
          '',
      notes: json['notes']?.toString() ?? '',
      links: _links(json['links']),
      tags: _strings(json['tags']),
      person:
          _nullableString(json['person']) ??
          _nullableString(supportJson?['person']),
      team:
          _nullableString(json['team']) ??
          _nullableString(supportJson?['team']),
      source: json['source']?.toString() ?? 'manual',
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'initiativeId': initiativeId,
    'category': category,
    'categoryLabel': categoryLabel,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'minutes': minutes,
    'localDate': localDate,
    'summary': summary,
    'outcome': outcome,
    'notes': notes,
    'links': links.map((link) => link.toJson()).toList(),
    'tags': tags,
    'person': person,
    'team': team,
    'source': source,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static DateTime? _date(Object? value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString();
    return (text == null || text.isEmpty) ? null : text;
  }

  static List<LinkRef> _links(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) {
          if (item is Map) {
            return LinkRef.fromJson(Map<String, dynamic>.from(item));
          }
          // The service currently stores links as plain URL strings.
          final url = item?.toString() ?? '';
          return LinkRef(label: url, url: url);
        })
        .where((link) => link.url.isNotEmpty)
        .toList();
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList();
  }

  static String _isoDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
