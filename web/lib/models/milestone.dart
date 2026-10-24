/// A dated checkpoint attached to a project (a subcategory). The due date is
/// optional, so an undated milestone is a plain checklist item.
class Milestone {
  const Milestone({
    required this.id,
    required this.subcategoryId,
    required this.title,
    this.dueDate = '',
    this.done = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String subcategoryId;
  final String title;

  /// Local calendar date, `YYYY-MM-DD`, or empty when the milestone has no due
  /// date.
  final String dueDate;

  final bool done;
  final DateTime createdAt;
  final DateTime updatedAt;

  Milestone copyWith({
    String? id,
    String? subcategoryId,
    String? title,
    String? dueDate,
    bool? done,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Milestone(
      id: id ?? this.id,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      title: title ?? this.title,
      dueDate: dueDate ?? this.dueDate,
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
