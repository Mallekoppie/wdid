/// Enumerations shared by the wdid client.
///
/// Values mirror the contract documented in `plan.md` so that JSON from the
/// service can be parsed without translation tables.
library;

enum InitiativeStatus {
  planned,
  active,
  blocked,
  done,
  archived;

  static InitiativeStatus parse(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return InitiativeStatus.values.firstWhere(
      (status) => status.name == normalized,
      orElse: () => InitiativeStatus.active,
    );
  }

  String get label => switch (this) {
    InitiativeStatus.planned => 'Planned',
    InitiativeStatus.active => 'Active',
    InitiativeStatus.blocked => 'Blocked',
    InitiativeStatus.done => 'Done',
    InitiativeStatus.archived => 'Archived',
  };
}

enum WorkType {
  initiative,
  category;

  static WorkType parse(Object? value) => value?.toString() == 'initiative'
      ? WorkType.initiative
      : WorkType.category;
}

/// How a work entry was captured. Mirrors `EntrySource` in the service.
enum EntrySource {
  manual,
  timer;

  static EntrySource parse(Object? value) =>
      value?.toString() == 'timer' ? EntrySource.timer : EntrySource.manual;
}

/// Manager-facing check-in or personal self-review.
enum CheckInKind {
  manager,
  personal;

  static CheckInKind parse(Object? value) =>
      value?.toString().toLowerCase() == 'personal'
      ? CheckInKind.personal
      : CheckInKind.manager;

  String get label => this == CheckInKind.manager ? 'Manager' : 'Personal';
}

/// Who a manager check-in is prepared for. A personal review has no audience.
enum CheckInAudience {
  oneOnOne,
  performanceReview;

  static CheckInAudience? parse(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return switch (normalized) {
      'one_on_one' || 'oneonone' => CheckInAudience.oneOnOne,
      'performance_review' ||
      'performancereview' => CheckInAudience.performanceReview,
      _ => null,
    };
  }

  String get wireName =>
      this == CheckInAudience.oneOnOne ? 'one_on_one' : 'performance_review';

  String get label => switch (this) {
    CheckInAudience.oneOnOne => '1:1',
    CheckInAudience.performanceReview => 'Performance review',
  };
}

/// Which prompt template a check-in uses. The audience selects the manager
/// variant; a personal review always uses the personal one. The variant
/// changes the prompt only, never the stored data.
enum CheckInPromptVariant {
  managerOneOnOne,
  managerPerformanceReview,
  personalReview;

  static CheckInPromptVariant parse(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return switch (normalized) {
      'manager_performance_review' || 'managerperformancereview' =>
        CheckInPromptVariant.managerPerformanceReview,
      'personal_review' ||
      'personalreview' => CheckInPromptVariant.personalReview,
      _ => CheckInPromptVariant.managerOneOnOne,
    };
  }

  String get wireName => switch (this) {
    CheckInPromptVariant.managerOneOnOne => 'manager_one_on_one',
    CheckInPromptVariant.managerPerformanceReview =>
      'manager_performance_review',
    CheckInPromptVariant.personalReview => 'personal_review',
  };

  String get label => switch (this) {
    CheckInPromptVariant.managerOneOnOne => '1:1',
    CheckInPromptVariant.managerPerformanceReview => 'Performance review',
    CheckInPromptVariant.personalReview => 'Personal review',
  };
}

/// Whether a summary update is the user's own text or generated output. Only
/// generated text is blocked from replacing a manual edit without confirmation.
enum CheckInSummarySource {
  manual,
  generated;

  String get wireName =>
      this == CheckInSummarySource.manual ? 'manual' : 'generated';
}

enum CheckInState {
  draft,
  generated,
  edited,
  final_;

  static CheckInState parse(Object? value) {
    final normalized = value?.toString().toLowerCase();
    if (normalized == 'final') return CheckInState.final_;
    return CheckInState.values.firstWhere(
      (state) => state.name == normalized,
      orElse: () => CheckInState.draft,
    );
  }

  String get wireName => this == CheckInState.final_ ? 'final' : name;

  String get label => switch (this) {
    CheckInState.draft => 'Draft',
    CheckInState.generated => 'Generated',
    CheckInState.edited => 'Edited',
    CheckInState.final_ => 'Final',
  };
}

/// Support modes from the Support screen design.
///
/// The service stores these as the `category` of a category-type work item and
/// uses `person` to mark the entry as support.
enum SupportMode {
  review,
  pair,
  unblock,
  mentor,
  incident,
  other;

  static SupportMode parse(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return SupportMode.values.firstWhere(
      (mode) => mode.name == normalized,
      orElse: () => SupportMode.other,
    );
  }

  String get label => switch (this) {
    SupportMode.review => 'Review',
    SupportMode.pair => 'Pair',
    SupportMode.unblock => 'Unblock',
    SupportMode.mentor => 'Mentor',
    SupportMode.incident => 'Incident',
    SupportMode.other => 'Other',
  };
}
