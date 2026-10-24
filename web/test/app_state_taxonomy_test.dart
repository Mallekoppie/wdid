import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/data/category_api.dart';
import 'package:wdid_web/data/settings_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/state/app_state.dart';

import 'fake_preferences_api.dart';

Category testCategory(
  String id,
  String name, {
  CategoryRole role = CategoryRole.initiative,
  bool archived = false,
}) {
  return Category(
    id: id,
    name: name,
    role: role,
    archived: archived,
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
  );
}

void main() {
  Future<(AppState, FakeCategoryApi, FakeSettingsApi)> buildState() async {
    final categories = FakeCategoryApi(
      categories: [
        testCategory('cat-1', 'Initiatives'),
        testCategory('cat-2', 'Support', role: CategoryRole.support),
        testCategory('cat-3', 'Old work', archived: true),
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
    final settings = FakeSettingsApi();
    final state = AppState(
      categoryApi: categories,
      settingsApi: settings,
    );
    await state.load();
    addTearDown(state.dispose);
    return (state, categories, settings);
  }

  test('entry selectors are built from the live taxonomy', () async {
    final (state, _, _) = await buildState();

    expect(state.selectableCategories.map((category) => category.name), [
      'Initiatives',
      'Support',
    ]);
    expect(state.subcategoriesFor('cat-1').single.name, 'Billing migration');
  });

  test(
    'creating and renaming a category updates the entry selectors',
    () async {
      final (state, _, _) = await buildState();

      final created = await state.createCategory(
        name: 'Deep work',
        role: CategoryRole.other,
      );
      expect(
        state.selectableCategories.map((category) => category.name),
        contains('Deep work'),
      );

      await state.renameCategory(created, 'Focused work');
      final labels = state.selectableCategories.map(
        (category) => category.name,
      );
      expect(labels, contains('Focused work'));
      expect(labels, isNot(contains('Deep work')));

      await state.archiveCategory(created);
      expect(
        state.selectableCategories.map((category) => category.name),
        isNot(contains('Focused work')),
      );
    },
  );

  test('subcategory CRUD stays attached to its category', () async {
    final (state, _, _) = await buildState();
    final category = state.categories.first;

    final created = await state.createSubcategory(
      category: category,
      name: 'Milestone work',
    );
    expect(
      state.subcategoriesFor(category.id).map((s) => s.name),
      contains('Milestone work'),
    );

    await state.renameSubcategory(created, 'Milestone delivery');
    expect(
      state.subcategoriesFor(category.id).map((s) => s.name),
      contains('Milestone delivery'),
    );

    await state.deleteSubcategory(created);
    expect(
      state.subcategoriesFor(category.id).map((s) => s.name),
      isNot(contains('Milestone delivery')),
    );
  });

  test('preferences load from the service and apply immediately', () async {
    final (state, _, settings) = await buildState();

    expect(state.about!.version, '0.1.0');
    expect(state.settings.schemaVersion, 1);

    await state.setTheme(ThemePreference.dark);
    expect(state.settings.theme, ThemePreference.dark);
    expect(settings.settings.theme, ThemePreference.dark);
    expect(settings.updateCalls, 1);

    await state.setDensity(DensityPreference.compact);
    expect(state.settings.density, DensityPreference.compact);
    expect(settings.settings.density, DensityPreference.compact);
  });

  test('a rejected settings save rolls the optimistic change back', () async {
    final (state, _, settings) = await buildState();
    final original = state.settings;

    settings.failure = const SettingsFailure(
      'weekStart: must be between 1 and 7',
    );

    await expectLater(
      state.saveSettings(state.settings.copyWith(weekStart: 9)),
      throwsA(isA<SettingsFailure>()),
    );
    expect(state.settings, same(original));
  });

  test('taxonomy failures stay inside the categories surface', () async {
    final categories = FakeCategoryApi()
      ..failure = const CategoryFailure('The service is unreachable.');
    final state = AppState(
      categoryApi: categories,
      settingsApi: FakeSettingsApi(),
    );
    await state.load();
    addTearDown(state.dispose);

    expect(state.status, AppStatus.ready);
    expect(state.taxonomyError, 'The service is unreachable.');
    // No taxonomy loaded, so no capture choices are fabricated.
    expect(state.selectableCategories, isEmpty);
  });
}
