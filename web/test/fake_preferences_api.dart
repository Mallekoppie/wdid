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

  /// When set, the next `getSettings` waits for it so tests can observe the
  /// screen before the preferences arrive.
  Completer<void>? gate;

  @override
  Future<SettingsSnapshot> getSettings() async {
    if (gate != null) {
      final pending = gate!;
      gate = null;
      await pending.future;
    }
    if (failure != null) throw failure!;
    return SettingsSnapshot(settings: settings, about: about);
  }

  BackupStatusInfo backupStatus = const BackupStatusInfo(
    overdue: true,
    backupDirectory: '/var/lib/wdid/backups',
    backupIntervalHours: 6,
    backupRetention: 30,
  );
  List<BackupSnapshot> backups = [];
  SettingsFailure? backupFailure;
  int statusCalls = 0;
  int listCalls = 0;
  int backupNowCalls = 0;
  int restoreCalls = 0;
  String? restoredName;

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

  @override
  Future<BackupStatusInfo> getBackupStatus() async {
    statusCalls++;
    if (backupFailure != null) throw backupFailure!;
    return backupStatus;
  }

  @override
  Future<List<BackupSnapshot>> listBackups() async {
    listCalls++;
    if (backupFailure != null) throw backupFailure!;
    return List.unmodifiable(backups);
  }

  @override
  Future<BackupNowResult> backupNow() async {
    backupNowCalls++;
    if (backupFailure != null) throw backupFailure!;
    final now = DateTime.now();
    final snapshot = BackupSnapshot(
      name: 'wdid-manual-$backupNowCalls.db',
      createdAt: now,
      sizeBytes: 1024 * backupNowCalls,
      manual: true,
    );
    backups = [snapshot, ...backups];
    backupStatus = BackupStatusInfo(
      lastBackupAt: snapshot.createdAt,
      lastBackupSizeBytes: snapshot.sizeBytes,
      overdue: backupStatus.overdue,
      backupDirectory: backupStatus.backupDirectory,
      backupIntervalHours: backupStatus.backupIntervalHours,
      backupRetention: backupStatus.backupRetention,
      scheduledCount: backupStatus.scheduledCount,
      manualCount: backups.where((item) => item.manual).length,
      lastBackupManual: true,
    );
    return BackupNowResult(backup: snapshot, status: backupStatus);
  }

  @override
  Future<RestoreBackupResult> restoreBackup(String name) async {
    restoreCalls++;
    restoredName = name;
    if (backupFailure != null) throw backupFailure!;
    final snapshot = backups.firstWhere((item) => item.name == name);
    backupStatus = BackupStatusInfo(
      lastBackupAt: snapshot.createdAt,
      lastBackupSizeBytes: snapshot.sizeBytes,
      overdue: backupStatus.overdue,
      backupDirectory: backupStatus.backupDirectory,
      backupIntervalHours: backupStatus.backupIntervalHours,
      backupRetention: backupStatus.backupRetention,
      scheduledCount: backupStatus.scheduledCount,
      manualCount: backupStatus.manualCount,
      lastBackupManual: snapshot.manual,
    );
    backups = backups
        .where((item) => !item.createdAt.isAfter(snapshot.createdAt))
        .toList();
    return RestoreBackupResult(
      backup: snapshot,
      status: backupStatus,
      preRestorePath: '/var/lib/wdid/data/wdid-before-restore-test.db',
    );
  }
}
