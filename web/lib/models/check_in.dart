import 'enums.dart';

class CheckInTotals {
  const CheckInTotals({
    this.minutes = 0,
    this.byInitiative = const {},
    this.byCategory = const {},
  });

  final int minutes;
  final Map<String, int> byInitiative;
  final Map<String, int> byCategory;

  factory CheckInTotals.fromJson(Map<String, dynamic> json) => CheckInTotals(
        minutes: (json['minutes'] as num?)?.round() ?? 0,
        byInitiative: _intMap(json['byInitiative']),
        byCategory: _intMap(json['byCategory']),
      );

  Map<String, dynamic> toJson() => {
        'minutes': minutes,
        'byInitiative': byInitiative,
        'byCategory': byCategory,
      };

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (key, item) => MapEntry(key.toString(), (item as num?)?.round() ?? 0),
    );
  }
}

class CheckIn {
  const CheckIn({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.createdAt,
    this.state = CheckInState.draft,
    this.focusNotes = '',
    this.summaryMarkdown = '',
    this.summaryModel,
    this.promptVersion = 'v1',
    this.totals = const CheckInTotals(),
  });

  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime createdAt;
  final CheckInState state;
  final String focusNotes;
  final String summaryMarkdown;
  final String? summaryModel;
  final String promptVersion;
  final CheckInTotals totals;

  bool get isFinal => state == CheckInState.final_;
  int get daysCovered => periodEnd.difference(periodStart).inDays + 1;

  CheckIn copyWith({
    String? id,
    DateTime? periodStart,
    DateTime? periodEnd,
    DateTime? createdAt,
    CheckInState? state,
    String? focusNotes,
    String? summaryMarkdown,
    String? summaryModel,
    String? promptVersion,
    CheckInTotals? totals,
  }) {
    return CheckIn(
      id: id ?? this.id,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      createdAt: createdAt ?? this.createdAt,
      state: state ?? this.state,
      focusNotes: focusNotes ?? this.focusNotes,
      summaryMarkdown: summaryMarkdown ?? this.summaryMarkdown,
      summaryModel: summaryModel ?? this.summaryModel,
      promptVersion: promptVersion ?? this.promptVersion,
      totals: totals ?? this.totals,
    );
  }

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    final start = _date(json['periodStart']) ?? DateTime.now();
    return CheckIn(
      id: json['id'].toString(),
      periodStart: start,
      periodEnd: _date(json['periodEnd']) ?? start,
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      state: CheckInState.parse(json['state']),
      focusNotes: json['focusNotes']?.toString() ?? '',
      summaryMarkdown: json['summaryMarkdown']?.toString() ?? '',
      summaryModel: json['summaryModel']?.toString(),
      promptVersion: json['promptVersion']?.toString() ?? 'v1',
      totals: json['totals'] is Map
          ? CheckInTotals.fromJson(
              Map<String, dynamic>.from(json['totals'] as Map),
            )
          : const CheckInTotals(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'periodStart': _isoDate(periodStart),
        'periodEnd': _isoDate(periodEnd),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'state': state.wireName,
        'focusNotes': focusNotes,
        'summaryMarkdown': summaryMarkdown,
        'summaryModel': summaryModel,
        'promptVersion': promptVersion,
        'totals': totals.toJson(),
      };

  static DateTime? _date(Object? value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _isoDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}
