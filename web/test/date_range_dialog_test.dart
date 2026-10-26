import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/widgets/forms/date_range_dialog.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    required DateTimeRange initialRange,
    required DateTime today,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDateRangeDialog(
              context,
              initialRange: initialRange,
              today: today,
              presets: [
                DateRangePreset(
                  label: 'All time',
                  range: DateTimeRange(start: DateTime(2000), end: today),
                ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('start and end pickers keep the 2020-to-today bounds', (
    tester,
  ) async {
    final today = DateTime(2026, 10, 26);
    final start = DateTime(2026, 10, 20);
    await openDialog(
      tester,
      initialRange: DateTimeRange(start: start, end: today),
      today: today,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(DateRangeDialog),
        matching: find.byIcon(Icons.first_page),
      ),
    );
    await tester.pumpAndSettle();

    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.firstDate, DateTime(2020));
    expect(picker.lastDate, today);
    expect(picker.initialDate, start);
  });

  testWidgets('a preset before 2020 is clamped when the picker opens', (
    tester,
  ) async {
    final today = DateTime(2026, 10, 26);
    await openDialog(
      tester,
      initialRange: DateTimeRange(start: DateTime(2000), end: today),
      today: today,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(DateRangeDialog),
        matching: find.byIcon(Icons.first_page),
      ),
    );
    await tester.pumpAndSettle();

    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, DateTime(2020));
    expect(picker.firstDate, DateTime(2020));
  });
}
