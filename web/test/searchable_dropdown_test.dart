import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/widgets/searchable_dropdown.dart';

const _options = [
  SearchableDropdownOption(value: 'cat-1', label: 'Initiatives'),
  SearchableDropdownOption(value: 'cat-2', label: 'Meetings'),
  SearchableDropdownOption(value: 'cat-3', label: 'Support'),
];

Finder entry(String label) =>
    find.widgetWithText(MenuItemButton, label).hitTestable();

Future<void> pumpDropdown(
  WidgetTester tester, {
  String? value = 'cat-1',
  List<SearchableDropdownOption<String>> options = _options,
  ValueChanged<String?>? onChanged,
}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 220,
            child: SearchableDropdown<String>(
              value: value,
              label: 'Category',
              options: options,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the selected label and filters by substring', (
    tester,
  ) async {
    String? selected = 'cat-1';
    await pumpDropdown(tester, onChanged: (value) => selected = value);

    expect(find.text('Initiatives'), findsOneWidget);

    await openMenu(tester);
    expect(entry('Meetings'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'meet');
    await tester.pumpAndSettle();

    expect(entry('Meetings'), findsOneWidget);
    expect(entry('Initiatives'), findsNothing);

    await tester.tap(entry('Meetings'));
    await tester.pumpAndSettle();

    expect(selected, 'cat-2');
    expect(find.text('Meetings'), findsOneWidget);
  });

  testWidgets('selecting all on focus replaces the label with the query', (
    tester,
  ) async {
    await pumpDropdown(tester);

    await openMenu(tester);

    // The current label is selected, so the first keystroke would replace it.
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(
      editable.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 'Initiatives'.length),
    );

    await tester.enterText(find.byType(TextField), 'sup');
    await tester.pumpAndSettle();
    expect(entry('Support'), findsOneWidget);
    expect(entry('Meetings'), findsNothing);
  });

  testWidgets('a pinned option survives filtering and no matches is shown', (
    tester,
  ) async {
    await pumpDropdown(
      tester,
      value: '',
      options: const [
        SearchableDropdownOption(
          value: '',
          label: 'No subcategory',
          pinned: true,
        ),
        SearchableDropdownOption(value: 'sub-1', label: 'Billing migration'),
        SearchableDropdownOption(value: 'sub-2', label: 'Sprint planning'),
      ],
    );

    await openMenu(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(entry('No subcategory'), findsOneWidget);
    expect(entry('No matches'), findsOneWidget);
    expect(entry('Billing migration'), findsNothing);
  });

  testWidgets('a query without real matches shows the disabled hint', (
    tester,
  ) async {
    await pumpDropdown(tester);

    await openMenu(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No matches'), findsWidgets);
    expect(entry('Initiatives'), findsNothing);
  });

  testWidgets('leaving the field restores the selected label', (tester) async {
    await pumpDropdown(tester);

    await openMenu(tester);
    await tester.enterText(find.byType(TextField), 'meet');
    await tester.pumpAndSettle();

    // Move focus away without selecting anything.
    await tester.tap(find.byType(Scaffold));
    await tester.pumpAndSettle();

    expect(find.text('Initiatives'), findsOneWidget);
  });
}
