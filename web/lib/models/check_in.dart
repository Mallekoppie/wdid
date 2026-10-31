import 'enums.dart';

class CheckInTotals {
  const CheckInTotals({
    this.minutes = 0,
    this.byInitiative = const {},
    this.byCategory = const {},
    this.bySubcategory = const {},
    this.supportByPerson = const {},
    this.supportMinutes = 0,
    this.supportInteractions = 0,
  });

  final int minutes;
  final Map<String, int> byInitiative;
  final Map<String, int> byCategory;
  final Map<String, int> bySubcategory;

  /// Per-person rows credit each name the entry's full minutes, so their sum
  /// is not the support total.
  final Map<String, int> supportByPerson;

  /// Authoritative support totals snapshotted from the period report. Never
  /// derived by adding up [supportByPerson].
  final int supportMinutes;
  final int supportInteractions;

  factory CheckInTotals.fromJson(Map<String, dynamic> json) {
    final supportByPerson = _intMap(json['supportByPerson']);
    final supportMinutes = (json['supportMinutes'] as num?)?.round() ?? 0;
    final supportInteractions =
        (json['supportInteractions'] as num?)?.round() ?? 0;
    return CheckInTotals(
      minutes: (json['minutes'] as num?)?.round() ?? 0,
      byInitiative: _intMap(json['byInitiative']),
      byCategory: _intMap(json['byCategory']),
      bySubcategory: _intMap(json['bySubcategory']),
      supportByPerson: supportByPerson,
      supportMinutes: effectiveSupportMinutes(
        supportMinutes,
        supportByPerson,
      ),
      supportInteractions: effectiveSupportInteractions(
        supportInteractions,
        supportByPerson,
      ),
    );
  }

  /// Legacy check-ins written before the authoritative support totals existed
  /// store only [supportByPerson]. A zero stored total falls back to the row
  /// sum, which is exact for single-person legacy data. A fresh snapshot keeps
  /// its authoritative value.
  static int effectiveSupportMinutes(
    int supportMinutes,
    Map<String, int> supportByPerson,
  ) => supportMinutes == 0 && supportByPerson.isNotEmpty
      ? supportByPerson.values.fold(0, (sum, minutes) => sum + minutes)
      : supportMinutes;

  /// Legacy check-ins have no stored interaction count, so a zero falls back to
  /// the number of people rows, which is what the pre-upgrade UI showed.
  static int effectiveSupportInteractions(
    int supportInteractions,
    Map<String, int> supportByPerson,
  ) => supportInteractions == 0 && supportByPerson.isNotEmpty
      ? supportByPerson.length
      : supportInteractions;

  Map<String, dynamic> toJson() => {
    'minutes': minutes,
    'byInitiative': byInitiative,
    'byCategory': byCategory,
    'bySubcategory': bySubcategory,
    'supportByPerson': supportByPerson,
    'supportMinutes': supportMinutes,
    'supportInteractions': supportInteractions,
  };

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (key, item) => MapEntry(key.toString(), (item as num?)?.round() ?? 0),
    );
  }
}

/// The server-computed period a new check-in should start with. Both dates are
/// inclusive local calendar days; the user may edit either before creating it.
class CheckInDefaults {
  const CheckInDefaults({
    required this.periodStart,
    required this.periodEnd,
    this.lastFinalCheckInId = '',
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final String lastFinalCheckInId;

  int get daysCovered {
    if (periodEnd.isBefore(periodStart)) return 0;
    return periodEnd.difference(periodStart).inDays + 1;
  }
}

/// The ready-to-paste prompt block for one check-in. The service owns the
/// instruction text; the client only displays and copies it.
class CheckInPrompt {
  const CheckInPrompt({
    required this.prompt,
    required this.variant,
    this.promptVersion = 'v1',
  });

  final String prompt;
  final CheckInPromptVariant variant;
  final String promptVersion;
}

/// One check-in prompt instruction. The server resolves the body and appends
/// the locked rules, so the client only displays and edits the body.
class PromptTemplate {
  const PromptTemplate({
    String? template,
    required this.variant,
    this.promptVersion = 'v1',
    this.body = '',
    this.customised = false,
    this.rules = '',
  }) : template = template ?? body;

  /// The full instruction returned by the legacy SummaryService preview. New
  /// callers use [body] and [rules] instead.
  final String template;

  /// The current instruction body, without the locked rules.
  final String body;

  /// True when the account stores an override for this variant.
  final bool customised;

  /// The server-owned rules, always appended to the resolved instruction.
  final String rules;

  final CheckInPromptVariant variant;
  final String promptVersion;

  /// The instruction exactly as generation will send it: the trimmed body
  /// followed by the locked rules.
  String get assembledPrompt {
    final trimmed = body.trim();
    if (rules.isEmpty) return trimmed;
    if (trimmed.isEmpty) return rules;
    return '$trimmed\n\n$rules';
  }
}

/// One streamed chunk of AI generation. Text arrives incrementally; the final
/// delta carries the persisted check-in with its model name and prompt version.
class SummaryDelta {
  const SummaryDelta({
    this.text = '',
    this.checkIn,
    this.model = '',
    this.promptVersion = '',
  });

  final String text;
  final CheckIn? checkIn;
  final String model;
  final String promptVersion;

  bool get isFinal => checkIn != null;
}

class CheckIn {
  const CheckIn({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.createdAt,
    this.updatedAt,
    this.kind = CheckInKind.manager,
    this.audience,
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
  final DateTime? updatedAt;
  final CheckInKind kind;
  final CheckInAudience? audience;
  final CheckInState state;
  final String focusNotes;
  final String summaryMarkdown;
  final String? summaryModel;
  final String promptVersion;
  final CheckInTotals totals;

  bool get isManager => kind == CheckInKind.manager;
  bool get isPersonal => kind == CheckInKind.personal;
  bool get isFinal => state == CheckInState.final_;

  /// Only a final manager check-in is read-only; a personal review remains
  /// editable for its whole life.
  bool get isReadOnly => isManager && isFinal;
  bool get canFinalize => isManager && !isFinal;
  String get audienceLabel => audience?.label ?? 'No audience';

  /// The prompt template this check-in's kind and audience select. A manager
  /// check-in defaults to the 1:1 variant when no audience is recorded.
  CheckInPromptVariant get promptVariant {
    if (isPersonal) return CheckInPromptVariant.personalReview;
    if (audience == CheckInAudience.performanceReview) {
      return CheckInPromptVariant.managerPerformanceReview;
    }
    return CheckInPromptVariant.managerOneOnOne;
  }

  int get daysCovered {
    if (periodEnd.isBefore(periodStart)) return 0;
    return periodEnd.difference(periodStart).inDays + 1;
  }

  CheckIn copyWith({
    String? id,
    DateTime? periodStart,
    DateTime? periodEnd,
    DateTime? createdAt,
    DateTime? updatedAt,
    CheckInKind? kind,
    CheckInAudience? audience,
    bool clearAudience = false,
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
      updatedAt: updatedAt ?? this.updatedAt,
      kind: kind ?? this.kind,
      audience: clearAudience ? null : (audience ?? this.audience),
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
      updatedAt: _date(json['updatedAt']),
      kind: CheckInKind.parse(json['kind']),
      audience: CheckInAudience.parse(json['audience']),
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
    'kind': kind.name,
    'periodStart': _isoDate(periodStart),
    'periodEnd': _isoDate(periodEnd),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'audience': audience?.wireName,
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
