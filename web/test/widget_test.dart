import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/models/taxonomy.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';

Category _category(String id, String name) => Category(
  id: id,
  name: name,
  role: CategoryRole.initiative,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

Subcategory _subcategory(String id, String categoryId, String name) =>
    Subcategory(
      id: id,
      categoryId: categoryId,
      name: name,
      createdAt: DateTime.utc(2026, 10, 23),
      updatedAt: DateTime.utc(2026, 10, 23),
    );

void main() {
  testWidgets('renders Today and navigates to Log', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        categoryApiBuilder: (_) => FakeCategoryApi(
          categories: [_category('cat-1', 'Initiatives')],
          subcategories: [
            _subcategory('sub-1', 'cat-1', 'Billing migration'),
          ],
        ),
        settingsApiBuilder: (_) => FakeSettingsApi(),
        entryApiBuilder: (_) => FakeEntryApi(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Start a timer'), findsOneWidget);
    expect(find.text('Nothing logged yet'), findsOneWidget);

    await tester.tap(find.text('Log').first);
    await tester.pumpAndSettle();

    expect(find.text('Add entry'), findsWidgets);
    expect(find.text('Week by attribution'), findsNothing);
  });
}
