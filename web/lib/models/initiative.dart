import 'enums.dart';

class LinkRef {
  const LinkRef({required this.label, required this.url});

  final String label;
  final String url;

  factory LinkRef.fromJson(Map<String, dynamic> json) => LinkRef(
        label: json['label']?.toString() ?? json['url']?.toString() ?? 'Link',
        url: json['url']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}

class Initiative {
  const Initiative({
    required this.id,
    required this.name,
    this.summary = '',
    this.targetOutcome = '',
    this.status = InitiativeStatus.active,
    this.progress = 0,
    this.startedAt,
    this.targetDate,
    this.links = const [],
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String summary;
  final String targetOutcome;
  final InitiativeStatus status;

  /// Manual progress, 0-100.
  final int progress;
  final DateTime? startedAt;
  final DateTime? targetDate;
  final List<LinkRef> links;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => status == InitiativeStatus.archived;
  bool get isOpen =>
      status == InitiativeStatus.planned ||
      status == InitiativeStatus.active ||
      status == InitiativeStatus.blocked;

  Initiative copyWith({
    String? id,
    String? name,
    String? summary,
    String? targetOutcome,
    InitiativeStatus? status,
    int? progress,
    DateTime? startedAt,
    DateTime? targetDate,
    List<LinkRef>? links,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearTargetDate = false,
  }) {
    return Initiative(
      id: id ?? this.id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      targetOutcome: targetOutcome ?? this.targetOutcome,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      startedAt: startedAt ?? this.startedAt,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      links: links ?? this.links,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Initiative.fromJson(Map<String, dynamic> json) {
    return Initiative(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? 'Untitled initiative',
      summary: json['summary']?.toString() ?? '',
      targetOutcome: json['targetOutcome']?.toString() ?? '',
      status: InitiativeStatus.parse(json['status']),
      progress: (json['progress'] as num?)?.round().clamp(0, 100) ?? 0,
      startedAt: _tryParse(json['startedAt']),
      targetDate: _tryParse(json['targetDate']),
      links: _links(json['links']),
      tags: _strings(json['tags']),
      createdAt: _tryParse(json['createdAt']) ?? DateTime.now(),
      updatedAt: _tryParse(json['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'summary': summary,
        'targetOutcome': targetOutcome,
        'status': status.name,
        'progress': progress,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'targetDate': targetDate == null ? null : _isoDate(targetDate!),
        'links': links.map((link) => link.toJson()).toList(),
        'tags': tags,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  static DateTime? _tryParse(Object? value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
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
