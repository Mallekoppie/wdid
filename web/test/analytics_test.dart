import 'package:flutter_test/flutter_test.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/models/initiative.dart';
import 'package:wdid_web/models/work_item.dart';
import 'package:wdid_web/utils/analytics.dart';

void main() {
  final now = DateTime(2026, 10, 17, 9);

  WorkItem item({
    required String id,
    required WorkType type,
    String? initiativeId,
    String? category,
    String? categoryLabel,
    String? person,
    required int minutes,
  }) {
    return WorkItem(
      id: id,
      type: type,
      initiativeId: initiativeId,
      category: category,
      categoryLabel: categoryLabel,
      startedAt: now,
      endedAt: now.add(Duration(minutes: minutes)),
      minutes: minutes,
      localDate: '2026-10-17',
      summary: 'Entry $id',
      person: person,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('support stays separate from initiative allocation', () {
    final billing = Initiative(
      id: 'billing',
      name: 'Billing migration',
      createdAt: now,
      updatedAt: now,
    );
    final items = [
      item(
        id: '1',
        type: WorkType.initiative,
        initiativeId: billing.id,
        minutes: 60,
      ),
      item(
        id: '2',
        type: WorkType.category,
        category: 'review',
        categoryLabel: 'Review',
        person: 'Priya',
        minutes: 30,
      ),
      item(
        id: '3',
        type: WorkType.category,
        category: 'meetings',
        categoryLabel: 'Meetings',
        minutes: 10,
      ),
    ];

    final slices = allocationFor(items, [billing]);

    expect(slices.map((slice) => slice.label), [
      'Billing migration',
      'Support',
      'Meetings',
    ]);
    expect(totalMinutes(items), 100);
    expect(supportMinutes(items), 30);
    expect(supportPeople(items), {'Priya'});
  });
}
