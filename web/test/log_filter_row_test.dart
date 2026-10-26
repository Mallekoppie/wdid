import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/models/app_settings.dart';
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

Future<void> pumpLog(
  WidgetTester tester, {
  Size size = const Size(1600, 1400),
  AppSettings settings = const AppSettings(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    WdidApp(
      authApi: FakeAuthApi(),
      initialSession: signedInSession(),
      initialRoute: '/log',
      categoryApiBuilder: (_) => FakeCategoryApi(
        categories: [_category('cat-1', 'Initiatives')],
        subcategories: [_subcategory('sub-1', 'cat-1', 'Billing migration')],
      ),
      settingsApiBuilder: (_) => FakeSettingsApi(settings: settings),
      entryApiBuilder: (_) => FakeEntryApi(),
    ),
  );
  await tester.pumpAndSettle();
}

Finder labelledFilter(String label) => find.byWidgetPredicate(
  (widget) => widget is InputDecorator && widget.decoration.labelText == label,
);

Finder dropdownIn(Finder container) => find
    .descendant(
      of: container,
      matching: find.byWidgetPredicate((widget) => widget is DropdownButton),
    )
    .first;

Finder searchField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.hintText == 'Search entries…  /',
);

/// The four controls of the Log filter row, bottom-aligned in the wide layout
/// and stacked below 900 px.
final filterControls = <String, Finder>{
  'Period': labelledFilter('Period'),
  'Category': labelledFilter('Category'),
  'Subcategory': labelledFilter('Subcategory'),
  'Search': searchField(),
};

const sharedHeight = 48.0;

void expectSharedControlHeight(WidgetTester tester) {
  for (final entry in filterControls.entries) {
    expect(
      tester.getSize(entry.value).height,
      sharedHeight,
      reason: '${entry.key} must render at the shared 48px control height',
    );
  }

  // A 48px outer box alone can still paint a shorter border. The dropdown's
  // content is centred inside the painted decorator, so centring proves the
  // decorator fills the height rather than hugging its content.
  for (final label in ['Period', 'Category', 'Subcategory']) {
    final box = tester.getRect(labelledFilter(label));
    final content = tester.getRect(dropdownIn(labelledFilter(label)));
    expect(
      content.center.dy,
      closeTo(box.center.dy, 0.5),
      reason: '$label content must be centred in the shared control height',
    );
  }
}

void main() {
  testWidgets('filter controls share the 48px height in the wide row', (
    tester,
  ) async {
    await pumpLog(tester);

    expectSharedControlHeight(tester);

    // Bottoms line up: the row is not top-aligned around mismatched heights.
    final bottom = tester.getRect(filterControls['Period']!).bottom;
    for (final finder in filterControls.values) {
      expect(tester.getRect(finder).bottom, bottom);
    }
  });

  testWidgets('filter controls share the 48px height when stacked', (
    tester,
  ) async {
    await pumpLog(tester, size: const Size(800, 1600));

    expectSharedControlHeight(tester);

    // Stacked controls start at the left edge and do not drift.
    final left = tester.getRect(filterControls['Period']!).left;
    for (final finder in filterControls.values) {
      expect(tester.getRect(finder).left, left);
    }
  });

  testWidgets('the shared height holds in compact density', (tester) async {
    await pumpLog(
      tester,
      settings: const AppSettings(density: DensityPreference.compact),
    );

    expectSharedControlHeight(tester);
  });
}
