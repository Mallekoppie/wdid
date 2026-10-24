import '../models/enums.dart';
import '../models/initiative.dart';

/// A selectable attribution in capture flows.
///
/// This is a UI projection over the documented WorkItem shape: either an
/// initiative, or a category-based "other" block. Support entries are captured
/// through their own form because they need person and mode fields.
class AttributionChoice {
  const AttributionChoice.initiative(this.initiativeId, this.label)
    : type = WorkType.initiative,
      category = null,
      categoryLabel = null;

  const AttributionChoice.category(
    this.category,
    this.label, {
    this.categoryLabel,
  }) : type = WorkType.category,
       initiativeId = null;

  final WorkType type;
  final String? initiativeId;
  final String? category;
  final String? categoryLabel;
  final String label;

  String get key => type == WorkType.initiative
      ? 'initiative:$initiativeId'
      : 'category:$category';

  bool get isInitiative => type == WorkType.initiative;

  @override
  bool operator ==(Object other) =>
      other is AttributionChoice && other.key == key;

  @override
  int get hashCode => key.hashCode;

  static List<AttributionChoice> forInitiatives(List<Initiative> initiatives) {
    final open = initiatives.where((initiative) => !initiative.isArchived);
    return [
      ...open.map(
        (initiative) =>
            AttributionChoice.initiative(initiative.id, initiative.name),
      ),
      ...otherWorkChoices,
    ];
  }

  static const List<AttributionChoice> otherWorkChoices = [
    AttributionChoice.category('other', 'Other work'),
    AttributionChoice.category('meetings', 'Meetings'),
    AttributionChoice.category('admin', 'Admin'),
    AttributionChoice.category('learning', 'Learning'),
    AttributionChoice.category('review', 'PR reviews'),
    AttributionChoice.category('design-review', 'Design reviews'),
    AttributionChoice.category('unplanned', 'Unplanned'),
  ];
}
