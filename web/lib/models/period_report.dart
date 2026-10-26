import 'taxonomy.dart';

/// The service's authoritative aggregate for an inclusive range of local
/// calendar dates. Screens render these values instead of composing period
/// totals from entry listings.
class PeriodReport {
  const PeriodReport({
    required this.fromDate,
    required this.toDate,
    this.totalMinutes = 0,
    this.entryCount = 0,
    this.supportMinutes = 0,
    this.supportInteractions = 0,
    this.categories = const [],
    this.subcategories = const [],
    this.supportPeople = const [],
    this.supportModes = const [],
    this.weeks = const [],
    this.notes = const [],
    this.milestoneProgress = const [],
  });

  final String fromDate;
  final String toDate;
  final int totalMinutes;
  final int entryCount;

  /// Authoritative support totals: minutes of every support entry and the
  /// number of support entries. Per-person allocations credit each name the
  /// entry's full minutes, so they may add up to more than these totals.
  final int supportMinutes;
  final int supportInteractions;

  final List<CategoryAllocation> categories;
  final List<SubcategoryAllocation> subcategories;
  final List<SupportPersonAllocation> supportPeople;
  final List<SupportModeAllocation> supportModes;
  final List<WeekRhythm> weeks;
  final List<PeriodNote> notes;

  /// Completion per project. Completion is a property of the project, not the
  /// period, so a project with milestones is listed even when it has no time
  /// inside the period.
  final List<MilestoneProgress> milestoneProgress;
}

/// How many milestones a project has and how many are done.
class MilestoneProgress {
  const MilestoneProgress({
    required this.subcategoryId,
    required this.total,
    required this.done,
  });

  final String subcategoryId;
  final int total;
  final int done;
}

/// The time attributed to one category in a period.
class CategoryAllocation {
  const CategoryAllocation({
    required this.categoryId,
    required this.name,
    required this.role,
    required this.minutes,
    required this.entryCount,
  });

  final String categoryId;
  final String name;
  final CategoryRole role;
  final int minutes;
  final int entryCount;
}

/// The time attributed to one subcategory in a period.
class SubcategoryAllocation {
  const SubcategoryAllocation({
    required this.subcategoryId,
    required this.categoryId,
    required this.name,
    required this.minutes,
    required this.entryCount,
    this.lastActivityDate = '',
    this.lastActivityDescription = '',
  });

  final String subcategoryId;
  final String categoryId;
  final String name;
  final int minutes;
  final int entryCount;

  /// Local date of the latest entry in the period, empty when there is none.
  final String lastActivityDate;

  /// Description of that latest entry, empty when it had none.
  final String lastActivityDescription;
}

/// Support time and interaction count for one person.
class SupportPersonAllocation {
  const SupportPersonAllocation({
    required this.person,
    required this.minutes,
    required this.interactions,
  });

  final String person;
  final int minutes;
  final int interactions;
}

/// Support time and interaction count for one mode (a support subcategory).
class SupportModeAllocation {
  const SupportModeAllocation({
    required this.subcategoryId,
    required this.name,
    required this.minutes,
    required this.interactions,
  });

  final String subcategoryId;
  final String name;
  final int minutes;
  final int interactions;
}

/// One local week's logged time and where most of it went.
class WeekRhythm {
  const WeekRhythm({
    required this.weekStartDate,
    this.minutes = 0,
    this.topCategoryId = '',
    this.topCategoryName = '',
  });

  final String weekStartDate;
  final int minutes;
  final String topCategoryId;
  final String topCategoryName;
}

/// Context attached to the period: a day note dated inside it or a project
/// note on a subcategory worked on during it.
class PeriodNote {
  const PeriodNote({
    required this.id,
    required this.date,
    required this.subcategoryId,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String date;
  final String subcategoryId;
  final String text;
  final DateTime createdAt;
}
