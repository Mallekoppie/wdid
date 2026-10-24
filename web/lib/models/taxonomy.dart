import 'link_ref.dart';

/// What a category means for reporting and validation.
///
/// The role is chosen when the category is created and never changes.
enum CategoryRole {
  initiative,
  support,
  other;

  String get label => switch (this) {
    CategoryRole.initiative => 'Initiative',
    CategoryRole.support => 'Support',
    CategoryRole.other => 'Other',
  };
}

/// Where a subcategory sits in its lifecycle.
enum SubcategoryStatus {
  planned,
  active,
  blocked,
  done,
  archived;

  String get label => switch (this) {
    SubcategoryStatus.planned => 'Planned',
    SubcategoryStatus.active => 'Active',
    SubcategoryStatus.blocked => 'Blocked',
    SubcategoryStatus.done => 'Done',
    SubcategoryStatus.archived => 'Archived',
  };
}

/// A user-defined top-level grouping of work.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.role,
    this.color = '',
    this.sortOrder = 0,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final CategoryRole role;
  final String color;
  final int sortOrder;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  Category copyWith({
    String? name,
    String? color,
    int? sortOrder,
    bool? archived,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      role: role,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// The optional second level under a category. It never has children.
class Subcategory {
  const Subcategory({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description = '',
    this.status = SubcategoryStatus.active,
    this.progress = 0,
    this.targetOutcome = '',
    this.targetDate = '',
    this.links = const [],
    this.sortOrder = 0,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String categoryId;
  final String name;
  final String description;
  final SubcategoryStatus status;
  final int progress;
  final String targetOutcome;
  final String targetDate;
  final List<LinkRef> links;
  final int sortOrder;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  Subcategory copyWith({
    String? name,
    String? description,
    SubcategoryStatus? status,
    int? progress,
    String? targetOutcome,
    String? targetDate,
    List<LinkRef>? links,
    int? sortOrder,
    bool? archived,
    DateTime? updatedAt,
  }) {
    return Subcategory(
      id: id,
      categoryId: categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      targetOutcome: targetOutcome ?? this.targetOutcome,
      targetDate: targetDate ?? this.targetDate,
      links: links ?? this.links,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
