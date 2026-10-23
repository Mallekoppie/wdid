import 'dart:async';

import 'package:wdid_web/data/category_api.dart';
import 'package:wdid_web/data/settings_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';

/// In-memory taxonomy used by widget and state tests.
class FakeCategoryApi implements CategoryApi {
  FakeCategoryApi({
    List<Category>? categories,
    List<Subcategory>? subcategories,
  }) : categories = categories ?? [],
       subcategories = subcategories ?? [];

  final List<Category> categories;
  final List<Subcategory> subcategories;

  CategoryFailure? failure;
  int listCalls = 0;
  int _sequence = 0;

  /// When set, listing waits for it so tests can observe the loading state.
  Completer<void>? gate;

  String _id() {
    _sequence++;
    return 'category-$_sequence';
  }

  void _maybeFail() {
    if (failure != null) throw failure!;
  }

  @override
  Future<List<Category>> listCategories() async {
    listCalls++;
    if (gate != null) await gate!.future;
    _maybeFail();
    return List.unmodifiable(categories);
  }

  @override
  Future<List<Subcategory>> listSubcategories({String categoryId = ''}) async {
    _maybeFail();
    return subcategories
        .where(
          (subcategory) =>
              categoryId.isEmpty || subcategory.categoryId == categoryId,
        )
        .toList();
  }

  @override
  Future<Category> createCategory({
    required String name,
    required CategoryRole role,
    String color = '',
    int sortOrder = 0,
  }) async {
    _maybeFail();
    final now = DateTime.now();
    final category = Category(
      id: _id(),
      name: name.trim(),
      role: role,
      color: color,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    categories.add(category);
    return category;
  }

  @override
  Future<Category> updateCategory(Category category) async {
    _maybeFail();
    final updated = category.copyWith(updatedAt: DateTime.now());
    _replaceCategory(updated);
    return updated;
  }

  @override
  Future<Category> archiveCategory(String id, {bool archived = true}) async {
    _maybeFail();
    final category = categories.firstWhere((item) => item.id == id);
    final updated = category.copyWith(
      archived: archived,
      updatedAt: DateTime.now(),
    );
    _replaceCategory(updated);
    return updated;
  }

  @override
  Future<void> deleteCategory(String id) async {
    _maybeFail();
    categories.removeWhere((category) => category.id == id);
    subcategories.removeWhere((subcategory) => subcategory.categoryId == id);
  }

  @override
  Future<Subcategory> createSubcategory({
    required String categoryId,
    required String name,
    SubcategoryStatus status = SubcategoryStatus.active,
    String description = '',
    int progress = 0,
    String targetOutcome = '',
    String targetDate = '',
    links = const [],
    int sortOrder = 0,
  }) async {
    _maybeFail();
    final now = DateTime.now();
    final subcategory = Subcategory(
      id: 'subcategory-$_sequence-${subcategories.length}',
      categoryId: categoryId,
      name: name.trim(),
      status: status,
      description: description,
      progress: progress,
      targetOutcome: targetOutcome,
      targetDate: targetDate,
      links: links,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    subcategories.add(subcategory);
    return subcategory;
  }

  @override
  Future<Subcategory> updateSubcategory(Subcategory subcategory) async {
    _maybeFail();
    final updated = subcategory.copyWith(updatedAt: DateTime.now());
    _replaceSubcategory(updated);
    return updated;
  }

  @override
  Future<Subcategory> archiveSubcategory(
    String id, {
    bool archived = true,
  }) async {
    _maybeFail();
    final subcategory = subcategories.firstWhere((item) => item.id == id);
    final updated = subcategory.copyWith(
      archived: archived,
      updatedAt: DateTime.now(),
    );
    _replaceSubcategory(updated);
    return updated;
  }

  @override
  Future<void> deleteSubcategory(String id) async {
    _maybeFail();
    subcategories.removeWhere((subcategory) => subcategory.id == id);
  }

  void _replaceCategory(Category updated) {
    final index = categories.indexWhere((item) => item.id == updated.id);
    if (index != -1) categories[index] = updated;
  }

  void _replaceSubcategory(Subcategory updated) {
    final index = subcategories.indexWhere((item) => item.id == updated.id);
    if (index != -1) subcategories[index] = updated;
  }
}

/// In-memory preferences used by widget and state tests.
class FakeSettingsApi implements SettingsApi {
  FakeSettingsApi({
    this.settings = const AppSettings(),
    this.about = const AboutInfo(
      version: '0.1.0',
      schemaVersion: 1,
      license: 'MIT',
    ),
  });

  AppSettings settings;
  AboutInfo about;
  SettingsFailure? failure;
  int updateCalls = 0;

  @override
  Future<SettingsSnapshot> getSettings() async {
    if (failure != null) throw failure!;
    return SettingsSnapshot(settings: settings, about: about);
  }

  @override
  Future<AppSettings> updateSettings(AppSettings updated) async {
    updateCalls++;
    if (failure != null) throw failure!;
    settings = updated.copyWith(
      version: about.version,
      schemaVersion: about.schemaVersion,
      license: about.license,
    );
    return settings;
  }
}
