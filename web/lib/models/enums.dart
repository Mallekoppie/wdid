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
