import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/settings_api.dart';

import 'fake_auth_api.dart';
import 'fake_preferences_api.dart';

BackupSnapshot _snapshot(
  String name, {
  bool manual = true,
  int sizeBytes = 2048,
  DateTime? createdAt,
}) {
  return BackupSnapshot(
    name: name,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 23, 8),
    sizeBytes: sizeBytes,
    manual: manual,
  );
}

void main() {
  Future<FakeSettingsApi> pumpSettings(
    WidgetTester tester, {
    required bool admin,
    FakeSettingsApi? api,
  }) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = api ?? FakeSettingsApi();
    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/settings',
        settingsApiBuilder: (_) => settings,
        isAdmin: () => admin,
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('an administrator lists snapshots, backs up and restores', (
    tester,
  ) async {
    final newer = _snapshot(
      'wdid-20261023T080000Z-manual.db',
      createdAt: DateTime.now(),
    );
    final older = _snapshot(
      'wdid-20261020T080000Z.db',
      manual: false,
      sizeBytes: 1024,
      createdAt: DateTime.utc(2026, 10, 20, 8),
    );
    final api = FakeSettingsApi()
      ..backups = [newer, older]
      ..backupStatus = BackupStatusInfo(
        lastBackupAt: newer.createdAt,
        lastBackupSizeBytes: newer.sizeBytes,
        overdue: false,
        backupDirectory: '/srv/wdid/backups',
        backupIntervalHours: 6,
        backupRetention: 30,
        scheduledCount: 1,
        manualCount: 1,
        lastBackupManual: true,
      );

    await pumpSettings(tester, admin: true, api: api);

    expect(find.text('Data & backups'), findsOneWidget);
    expect(find.text(newer.name), findsOneWidget);
    expect(find.text(older.name), findsOneWidget);
    expect(find.textContaining('Last backup today'), findsOneWidget);
    expect(
      find.textContaining('Every 6h · keep 30 scheduled backups'),
      findsOneWidget,
    );

    // Restore needs a selection.
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Restore selected'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Backup now'));
    await tester.pumpAndSettle();
    expect(api.backupNowCalls, 1);
    expect(find.text('wdid-manual-1.db'), findsOneWidget);

    // Select the older snapshot and restore it through the confirmation.
    await tester.tap(find.text(older.name));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Restore selected'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Restore selected'));
    await tester.pumpAndSettle();
    expect(find.text('Restore ${older.name}?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();

    expect(api.restoreCalls, 1);
    expect(api.restoredName, older.name);
    expect(find.textContaining('previous database saved'), findsOneWidget);
  });

  testWidgets('a non-administrator sees an explanatory read-only state', (
    tester,
  ) async {
    final api = FakeSettingsApi()
      ..backups = [_snapshot('wdid-20261023T080000Z-manual.db')]
      ..backupFailure = const SettingsFailure(
        'backups are managed by an administrator',
      );

    await pumpSettings(tester, admin: false, api: api);

    expect(find.text('Data & backups'), findsOneWidget);
    expect(find.textContaining('managed by an administrator'), findsOneWidget);
    expect(find.text('Backup now'), findsNothing);
    expect(find.text('Restore selected'), findsNothing);
    expect(find.text('Export all data'), findsOneWidget);
    // No backup RPC is attempted, so neither the snapshot nor its error shows.
    expect(find.text('wdid-20261023T080000Z-manual.db'), findsNothing);
    expect(
      find.textContaining('backups are managed by an administrator'),
      findsNothing,
    );
    expect(api.statusCalls, 0);
    expect(api.listCalls, 0);
  });

  testWidgets('the status shows the last backup size and warns when overdue', (
    tester,
  ) async {
    final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
    final api = FakeSettingsApi()
      ..backups = [
        _snapshot(
          'wdid-20261021T080000Z.db',
          manual: false,
          createdAt: twoDaysAgo,
        ),
      ]
      ..backupStatus = BackupStatusInfo(
        lastBackupAt: twoDaysAgo,
        lastBackupSizeBytes: 2048,
        overdue: true,
        backupDirectory: '/srv/wdid/backups',
        backupIntervalHours: 6,
        backupRetention: 30,
      );

    await pumpSettings(tester, admin: true, api: api);

    expect(find.textContaining('Last backup 2d ago'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsWidgets);
    expect(find.textContaining('Backup overdue.'), findsOneWidget);
    expect(
      find.textContaining('scheduled backups run every 6h'),
      findsOneWidget,
    );
  });

  testWidgets('an empty backup directory explains how to start', (
    tester,
  ) async {
    final api = FakeSettingsApi()
      ..backups = []
      ..backupStatus = const BackupStatusInfo(
        overdue: false,
        backupDirectory: '/srv/wdid/backups',
        backupIntervalHours: 6,
        backupRetention: 30,
      );

    await pumpSettings(tester, admin: true, api: api);

    expect(
      find.textContaining(
        'No backups yet. Take a backup before changing data.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a backup load failure is shown and retry recovers', (
    tester,
  ) async {
    final api = FakeSettingsApi()
      ..backupFailure = const SettingsFailure('backup directory unreadable');

    await pumpSettings(tester, admin: true, api: api);

    expect(find.textContaining('backup directory unreadable'), findsOneWidget);

    api.backupFailure = null;
    api.backups = [_snapshot('wdid-recovered.db')];

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('wdid-recovered.db'), findsOneWidget);
    expect(find.textContaining('backup directory unreadable'), findsNothing);
  });
}
