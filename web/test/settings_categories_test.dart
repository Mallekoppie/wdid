import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/category_api.dart';
import 'package:wdid_web/models/taxonomy.dart';

import 'fake_auth_api.dart';
import 'fake_preferences_api.dart';

Category category(String id, String name, {bool archived = false}) {
  return Category(
    id: id,
    name: name,
    role: CategoryRole.initiative,
    archived: archived,
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
  );
}

void main() {
  Future<void> pumpSettings(
    WidgetTester tester,
    FakeCategoryApi categoryApi,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/settings',
        categoryApiBuilder: (_) => categoryApi,
        settingsApiBuilder: (_) => FakeSettingsApi(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists categories with role, archive state and subcategories', (
    tester,
  ) async {
    final api = FakeCategoryApi(
      categories: [
        category('cat-1', 'Initiatives'),
        category('cat-2', 'Retired', archived: true),
      ],
      subcategories: [
        Subcategory(
          id: 'sub-1',
          categoryId: 'cat-1',
          name: 'Billing migration',
          createdAt: DateTime.utc(2026, 10, 23),
          updatedAt: DateTime.utc(2026, 10, 23),
        ),
      ],
    );

    await pumpSettings(tester, api);

    expect(find.text('Categories'), findsOneWidget);
    // The live taxonomy also feeds the app's capture selector.
    expect(find.text('Initiatives'), findsWidgets);
    expect(find.text('Retired'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Billing migration'), findsWidgets);
    expect(find.text('Initiative'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a category from the panel and shows it immediately', (
    tester,
  ) async {
    final api = FakeCategoryApi(categories: [category('cat-1', 'Initiatives')]);
    await pumpSettings(tester, api);

    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final nameField = find
        .descendant(of: dialog, matching: find.byType(TextField))
        .first;
    await tester.enterText(nameField, 'Deep work');
    await tester.tap(find.byType(DropdownButton<CategoryRole>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('Deep work'), findsOneWidget);
    expect(api.categories.map((item) => item.name), contains('Deep work'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the empty state when the taxonomy is empty', (
    tester,
  ) async {
    await pumpSettings(tester, FakeCategoryApi());

    expect(find.text('No categories yet'), findsOneWidget);
    expect(find.text('Create category'), findsOneWidget);
  });

  testWidgets('shows a retryable error when the taxonomy cannot load', (
    tester,
  ) async {
    final api = FakeCategoryApi()
      ..failure = const CategoryFailure('The service is unreachable.');
    await pumpSettings(tester, api);

    expect(find.text('The service is unreachable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a create validation error stays in the dialog', (tester) async {
    final api = FakeCategoryApi();
    await pumpSettings(tester, api);

    await tester.tap(find.text('Create category'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(api.categories, isEmpty);
  });
}
