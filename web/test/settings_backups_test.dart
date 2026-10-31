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
    // The administrator edits the live backup configuration rather than
    // reading a summary line.
    expect(find.byKey(const Key('backupDirectoryField')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('backupDirectoryField')))
          .controller!
          .text,
      '/srv/wdid/backups',
    );
    expect(find.textContaining('new snapshot set'), findsOneWidget);

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
    // Backup location, interval and retention stay read-only.
    expect(find.byKey(const Key('backupDirectoryField')), findsNothing);
    expect(find.byKey(const Key('backupIntervalField')), findsNothing);
    expect(find.byKey(const Key('backupRetentionField')), findsNothing);
    expect(
      find.textContaining('Every 6h · keep 30 scheduled backups'),
      findsOneWidget,
    );
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

  testWidgets(
    'an administrator edits and saves the live backup configuration',
    (tester) async {
      final api = FakeSettingsApi()
        ..backupStatus = const BackupStatusInfo(
          overdue: false,
          backupDirectory: '/srv/wdid/backups',
          backupIntervalHours: 6,
          backupRetention: 30,
        );

      await pumpSettings(tester, admin: true, api: api);
      final statusCallsBefore = api.statusCalls;

      // The editor is prefilled from the live status, not the empty per-user
      // record the fresh install returns.
      await tester.enterText(
        find.byKey(const Key('backupDirectoryField')),
        '/srv/wdid/archive',
      );
      await tester.enterText(
        find.byKey(const Key('backupIntervalField')),
        '12',
      );
      await tester.enterText(
        find.byKey(const Key('backupRetentionField')),
        '7',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save backup settings'),
      );
      await tester.pumpAndSettle();

      expect(api.updateCalls, 1);
      expect(api.settings.backupDir, '/srv/wdid/archive');
      expect(api.settings.backupIntervalHours, 12);
      expect(api.settings.retentionCount, 7);
      // The snapshot list and status are reloaded so they follow the new directory.
      expect(api.statusCalls, greaterThan(statusCallsBefore));
      expect(find.text('Backup settings saved'), findsOneWidget);
      expect(find.textContaining('new snapshot set'), findsOneWidget);
    },
  );

  testWidgets('an empty backup directory is rejected before saving', (
    tester,
  ) async {
    final api = FakeSettingsApi();
    await pumpSettings(tester, admin: true, api: api);

    await tester.enterText(find.byKey(const Key('backupDirectoryField')), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save backup settings'));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 0);
    expect(
      find.textContaining('Enter the backup directory path'),
      findsOneWidget,
    );
  });

  testWidgets('a relative backup directory is rejected before saving', (
    tester,
  ) async {
    final api = FakeSettingsApi();
    await pumpSettings(tester, admin: true, api: api);

    await tester.enterText(
      find.byKey(const Key('backupDirectoryField')),
      'relative/backups',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save backup settings'));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 0);
    expect(find.textContaining('absolute path'), findsOneWidget);
  });

  testWidgets('a service directory error is shown on the directory field', (
    tester,
  ) async {
    final api = FakeSettingsApi();
    await pumpSettings(tester, admin: true, api: api);

    api.failure = const SettingsFailure(
      'cannot create the directory: permission denied',
      field: 'backupDirectory',
    );
    await tester.enterText(
      find.byKey(const Key('backupDirectoryField')),
      '/srv/locked/backups',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save backup settings'));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 1);
    expect(find.textContaining('cannot create the directory'), findsOneWidget);
  });

  testWidgets('database and data directory rows stay read-only for admins', (
    tester,
  ) async {
    await pumpSettings(tester, admin: true);

    expect(find.text('Database'), findsOneWidget);
    expect(find.text('Data directory'), findsOneWidget);
    expect(find.byKey(const Key('databasePathField')), findsNothing);
    expect(find.byKey(const Key('dataDirectoryField')), findsNothing);
    // Only the backup configuration has editors.
    expect(find.byKey(const Key('backupDirectoryField')), findsOneWidget);
  });
}
