import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:wdid_web/data/settings_api.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/src/generated/check_ins.pb.dart' as check_ins;
import 'package:wdid_web/src/generated/settings.pbgrpc.dart' as generated;

class FakeSettingsRpc implements SettingsRpc {
  Object? error;
  generated.GetSettingsResponse getResponse = generated.GetSettingsResponse(
    settings: generated.Settings(),
    about: generated.About(version: '0.1.0', schemaVersion: 1, license: 'MIT'),
  );
  generated.UpdateSettingsResponse updateResponse =
      generated.UpdateSettingsResponse(settings: generated.Settings());
  generated.UpdateSettingsRequest? updateRequest;

  generated.SetAIApiKeyResponse setAiApiKeyResponse =
      generated.SetAIApiKeyResponse(settings: generated.Settings());
  generated.SetAIApiKeyRequest? setAiApiKeyRequest;
  generated.ClearAIApiKeyResponse clearAiApiKeyResponse =
      generated.ClearAIApiKeyResponse(settings: generated.Settings());
  int clearAiApiKeyCalls = 0;

  generated.ListPromptTemplatesResponse listPromptTemplatesResponse =
      generated.ListPromptTemplatesResponse();
  int listPromptTemplatesCalls = 0;
  generated.UpdatePromptTemplateResponse updatePromptTemplateResponse =
      generated.UpdatePromptTemplateResponse();
  generated.UpdatePromptTemplateRequest? updatePromptTemplateRequest;
  generated.ResetPromptTemplateResponse resetPromptTemplateResponse =
      generated.ResetPromptTemplateResponse();
  generated.ResetPromptTemplateRequest? resetPromptTemplateRequest;

  generated.GetBackupStatusResponse backupStatusResponse =
      generated.GetBackupStatusResponse(
        status: generated.BackupStatus(
          backupInterval: duration.Duration(seconds: Int64(6 * 60 * 60)),
          backupRetention: 30,
        ),
      );
  generated.ListBackupsResponse listBackupsResponse =
      generated.ListBackupsResponse();
  generated.BackupNowResponse backupNowResponse = generated.BackupNowResponse();
  generated.RestoreBackupResponse restoreResponse =
      generated.RestoreBackupResponse();
  generated.RestoreBackupRequest? restoreRequest;

  void _maybeFail() {
    if (error != null) throw error!;
  }

  @override
  Future<generated.GetSettingsResponse> getSettings() async {
    _maybeFail();
    return getResponse;
  }

  @override
  Future<generated.UpdateSettingsResponse> updateSettings(
    generated.UpdateSettingsRequest request,
  ) async {
    updateRequest = request;
    _maybeFail();
    return updateResponse;
  }

  @override
  Future<generated.SetAIApiKeyResponse> setAiApiKey(
    generated.SetAIApiKeyRequest request,
  ) async {
    setAiApiKeyRequest = request;
    _maybeFail();
    return setAiApiKeyResponse;
  }

  @override
  Future<generated.ClearAIApiKeyResponse> clearAiApiKey() async {
    clearAiApiKeyCalls++;
    _maybeFail();
    return clearAiApiKeyResponse;
  }

  @override
  Future<generated.ListPromptTemplatesResponse> listPromptTemplates() async {
    listPromptTemplatesCalls++;
    _maybeFail();
    return listPromptTemplatesResponse;
  }

  @override
  Future<generated.UpdatePromptTemplateResponse> updatePromptTemplate(
    generated.UpdatePromptTemplateRequest request,
  ) async {
    updatePromptTemplateRequest = request;
    _maybeFail();
    return updatePromptTemplateResponse;
  }

  @override
  Future<generated.ResetPromptTemplateResponse> resetPromptTemplate(
    generated.ResetPromptTemplateRequest request,
  ) async {
    resetPromptTemplateRequest = request;
    _maybeFail();
    return resetPromptTemplateResponse;
  }

  @override
  Future<generated.GetBackupStatusResponse> getBackupStatus() async {
    _maybeFail();
    return backupStatusResponse;
  }

  @override
  Future<generated.ListBackupsResponse> listBackups() async {
    _maybeFail();
    return listBackupsResponse;
  }

  @override
  Future<generated.BackupNowResponse> backupNow() async {
    _maybeFail();
    return backupNowResponse;
  }

  @override
  Future<generated.RestoreBackupResponse> restoreBackup(
    generated.RestoreBackupRequest request,
  ) async {
    restoreRequest = request;
    _maybeFail();
    return restoreResponse;
  }
}

void main() {
  test('getSettings maps minutes, enums and About information', () async {
    final rpc = FakeSettingsRpc()
      ..getResponse = generated.GetSettingsResponse(
        settings: generated.Settings(
          timezone: 'Europe/Amsterdam',
          weekStart: 1,
          dailyTarget: duration.Duration(seconds: Int64(450 * 60)),
          reviewCadence: generated.ReviewCadence.REVIEW_CADENCE_WEEKLY,
          longTimerThreshold: duration.Duration(seconds: Int64(240 * 60)),
          defaultEntryDuration: duration.Duration(seconds: Int64(45 * 60)),
          theme: generated.ThemePreference.THEME_PREFERENCE_DARK,
          density: generated.DensityPreference.DENSITY_PREFERENCE_COMPACT,
          backupInterval: duration.Duration(seconds: Int64(6 * 60 * 60)),
          backupRetention: 30,
        ),
        about: generated.About(
          version: '0.1.0',
          schemaVersion: 1,
          license: 'MIT',
        ),
      );

    final snapshot = await GrpcSettingsApi(rpc: rpc).getSettings();

    expect(snapshot.settings.timezone, 'Europe/Amsterdam');
    expect(snapshot.settings.weekStart, 1);
    expect(snapshot.settings.dailyTargetHours, 7.5);
    expect(snapshot.settings.longTimerMinutes, 240);
    expect(snapshot.settings.defaultDurationMinutes, 45);
    expect(snapshot.settings.reviewCadence, ReviewCadence.weekly);
    expect(snapshot.settings.theme, ThemePreference.dark);
    expect(snapshot.settings.density, DensityPreference.compact);
    expect(snapshot.about.version, '0.1.0');
    expect(snapshot.about.schemaVersion, 1);
    expect(snapshot.about.license, 'MIT');
  });

  test(
    'updateSettings sends every preference and keeps local-only fields',
    () async {
      final rpc = FakeSettingsRpc()
        ..updateResponse = generated.UpdateSettingsResponse(
          settings: generated.Settings(
            timezone: 'Europe/Amsterdam',
            weekStart: 1,
            dailyTarget: duration.Duration(seconds: Int64(450 * 60)),
            reviewCadence: generated.ReviewCadence.REVIEW_CADENCE_MONTHLY,
            longTimerThreshold: duration.Duration(seconds: Int64(180 * 60)),
            defaultEntryDuration: duration.Duration(seconds: Int64(45 * 60)),
            theme: generated.ThemePreference.THEME_PREFERENCE_DARK,
            density: generated.DensityPreference.DENSITY_PREFERENCE_COMPACT,
            backupInterval: duration.Duration(seconds: Int64(6 * 60 * 60)),
            backupRetention: 30,
            journalStartDate: '2026-01-01',
          ),
        );

      final saved = await GrpcSettingsApi(rpc: rpc).updateSettings(
        const AppSettings(
          timezone: 'Europe/Amsterdam',
          dailyTargetHours: 7.5,
          longTimerMinutes: 180,
          defaultDurationMinutes: 45,
          reviewCadence: ReviewCadence.monthly,
          theme: ThemePreference.dark,
          density: DensityPreference.compact,
          dataDir: '/srv/wdid',
          journalStartDate: '2026-01-01',
          version: '0.1.0',
          schemaVersion: 1,
          license: 'MIT',
        ),
      );

      final request = rpc.updateRequest!.settings;
      expect(request.timezone, 'Europe/Amsterdam');
      expect(request.dailyTarget.seconds.toInt(), 450 * 60);
      expect(request.longTimerThreshold.seconds.toInt(), 180 * 60);
      expect(request.defaultEntryDuration.seconds.toInt(), 45 * 60);
      expect(
        request.reviewCadence,
        generated.ReviewCadence.REVIEW_CADENCE_MONTHLY,
      );
      expect(request.theme, generated.ThemePreference.THEME_PREFERENCE_DARK);
      expect(
        request.density,
        generated.DensityPreference.DENSITY_PREFERENCE_COMPACT,
      );

      expect(saved.theme, ThemePreference.dark);
      expect(saved.density, DensityPreference.compact);
      expect(saved.dataDir, '/srv/wdid');
      expect(request.journalStartDate, '2026-01-01');
      expect(saved.journalStartDate, '2026-01-01');
      expect(saved.version, '0.1.0');
    },
  );

  test('validation failures expose the rejected field', () async {
    final rpc = FakeSettingsRpc()
      ..error = GrpcError.invalidArgument(
        'weekStart: must be between 1 (Monday) and 7 (Sunday)',
      );

    expect(
      () => GrpcSettingsApi(rpc: rpc).updateSettings(const AppSettings()),
      throwsA(
        isA<SettingsFailure>()
            .having((failure) => failure.field, 'field', 'weekStart')
            .having(
              (failure) => failure.message,
              'message',
              'weekStart: must be between 1 (Monday) and 7 (Sunday)',
            ),
      ),
    );
  });

  test('unauthenticated failures are explained', () async {
    final rpc = FakeSettingsRpc()
      ..error = GrpcError.unauthenticated('missing token');

    expect(
      () => GrpcSettingsApi(rpc: rpc).getSettings(),
      throwsA(
        isA<SettingsFailure>().having(
          (failure) => failure.message,
          'message',
          'missing token',
        ),
      ),
    );
  });

  test(
    'backup responses map status, snapshots and the pre-restore path',
    () async {
      final at = DateTime.utc(2026, 10, 23, 8);
      final rpc = FakeSettingsRpc()
        ..backupStatusResponse = generated.GetBackupStatusResponse(
          status: generated.BackupStatus(
            lastBackupAt: Timestamp.fromDateTime(at),
            lastBackupSizeBytes: Int64(4096),
            overdue: true,
            backupDirectory: '/srv/backups',
            backupInterval: duration.Duration(seconds: Int64(6 * 60 * 60)),
            backupRetention: 12,
            scheduledCount: 2,
            manualCount: 1,
            lastBackupManual: true,
          ),
        )
        ..listBackupsResponse = generated.ListBackupsResponse(
          backups: [
            generated.Backup(
              name: 'wdid-20261023T080000Z-manual.db',
              createdAt: Timestamp.fromDateTime(at),
              sizeBytes: Int64(4096),
              manual: true,
            ),
          ],
        )
        ..restoreResponse = generated.RestoreBackupResponse(
          backup: generated.Backup(
            name: 'wdid-20261023T080000Z-manual.db',
            createdAt: Timestamp.fromDateTime(at),
            sizeBytes: Int64(4096),
            manual: true,
          ),
          status: generated.BackupStatus(
            lastBackupAt: Timestamp.fromDateTime(at),
            lastBackupSizeBytes: Int64(4096),
            backupInterval: duration.Duration(seconds: Int64(6 * 60 * 60)),
            backupRetention: 12,
          ),
          preRestorePath: '/srv/data/wdid-before-restore-20261023T090000Z.db',
        );

      final api = GrpcSettingsApi(rpc: rpc);
      final status = await api.getBackupStatus();
      expect(status.lastBackupAt, at);
      expect(status.lastBackupSizeBytes, 4096);
      expect(status.overdue, isTrue);
      expect(status.backupDirectory, '/srv/backups');
      expect(status.backupIntervalHours, 6);
      expect(status.backupRetention, 12);
      expect(status.lastBackupManual, isTrue);

      final backups = await api.listBackups();
      expect(backups, hasLength(1));
      expect(backups.first.name, 'wdid-20261023T080000Z-manual.db');
      expect(backups.first.manual, isTrue);
      expect(backups.first.sizeBytes, 4096);

      final restored = await api.restoreBackup(backups.first.name);
      expect(rpc.restoreRequest!.name, backups.first.name);
      expect(
        restored.preRestorePath,
        '/srv/data/wdid-before-restore-20261023T090000Z.db',
      );
      expect(restored.status.lastBackupSizeBytes, 4096);
    },
  );

  test('getSettings maps the support-people roster', () async {
    final rpc = FakeSettingsRpc()
      ..getResponse = generated.GetSettingsResponse(
        settings: generated.Settings(supportPeople: ['Priya', 'Sam']),
        about: generated.About(
          version: '0.1.0',
          schemaVersion: 1,
          license: 'MIT',
        ),
      );

    final snapshot = await GrpcSettingsApi(rpc: rpc).getSettings();

    expect(snapshot.settings.supportPeople, ['Priya', 'Sam']);
  });

  test('getSettings maps the write-only AI key state', () async {
    final rpc = FakeSettingsRpc()
      ..getResponse = generated.GetSettingsResponse(
        settings: generated.Settings(hasAiApiKey: true),
        about: generated.About(
          version: '0.1.0',
          schemaVersion: 1,
          license: 'MIT',
        ),
      );

    final snapshot = await GrpcSettingsApi(rpc: rpc).getSettings();

    expect(snapshot.settings.hasAiApiKey, isTrue);
  });

  test('setAiApiKey sends the key and maps the stored state', () async {
    final rpc = FakeSettingsRpc()
      ..setAiApiKeyResponse = generated.SetAIApiKeyResponse(
        settings: generated.Settings(hasAiApiKey: true),
      );

    final saved = await GrpcSettingsApi(rpc: rpc)
        .setAiApiKey('  sk-ant-test  ');

    expect(rpc.setAiApiKeyRequest!.apiKey, 'sk-ant-test');
    expect(saved.hasAiApiKey, isTrue);
  });

  test('clearAiApiKey clears the stored state', () async {
    final rpc = FakeSettingsRpc()
      ..clearAiApiKeyResponse = generated.ClearAIApiKeyResponse(
        settings: generated.Settings(hasAiApiKey: false),
      );

    final saved = await GrpcSettingsApi(rpc: rpc).clearAiApiKey();

    expect(rpc.clearAiApiKeyCalls, 1);
    expect(saved.hasAiApiKey, isFalse);
  });

  test('listPromptTemplates maps variant, body, customised and rules', () async {
    final rpc = FakeSettingsRpc()
      ..listPromptTemplatesResponse = generated.ListPromptTemplatesResponse(
        templates: [
          generated.PromptTemplate(
            variant: check_ins
                .CheckInPromptVariant
                .CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE,
            body: 'One on one body',
            customised: true,
            rules: 'Use only the supplied data.',
          ),
          generated.PromptTemplate(
            variant: check_ins
                .CheckInPromptVariant
                .CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW,
            body: 'Personal body',
            rules: 'Use only the supplied data.',
          ),
        ],
      );

    final templates = await GrpcSettingsApi(rpc: rpc).listPromptTemplates();

    expect(rpc.listPromptTemplatesCalls, 1);
    expect(templates, hasLength(2));
    expect(templates.first.variant, CheckInPromptVariant.managerOneOnOne);
    expect(templates.first.body, 'One on one body');
    expect(templates.first.customised, isTrue);
    expect(templates.first.rules, 'Use only the supplied data.');
    expect(templates.first.promptVersion, 'custom');
    // The Settings path populates the editor fields, not the legacy preview.
    expect(templates.first.template, '');
    expect(
      templates.first.assembledPrompt,
      'One on one body\n\nUse only the supplied data.',
    );
    expect(templates.last.variant, CheckInPromptVariant.personalReview);
    expect(templates.last.body, 'Personal body');
    expect(templates.last.customised, isFalse);
    expect(templates.last.promptVersion, 'v1');
    expect(templates.last.template, '');
  });

  test('updatePromptTemplate sends the variant and body and maps the result', () async {
    final rpc = FakeSettingsRpc()
      ..updatePromptTemplateResponse = generated.UpdatePromptTemplateResponse(
        template: generated.PromptTemplate(
          variant: check_ins
              .CheckInPromptVariant
              .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW,
          body: 'Custom performance body',
          customised: true,
          rules: 'RULES',
        ),
      );

    final saved = await GrpcSettingsApi(rpc: rpc).updatePromptTemplate(
      CheckInPromptVariant.managerPerformanceReview,
      '  Custom performance body  ',
    );

    expect(
      rpc.updatePromptTemplateRequest!.variant,
      check_ins
          .CheckInPromptVariant
          .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW,
    );
    expect(rpc.updatePromptTemplateRequest!.body, 'Custom performance body');
    expect(saved.variant, CheckInPromptVariant.managerPerformanceReview);
    expect(saved.body, 'Custom performance body');
    expect(saved.customised, isTrue);
  });

  test('resetPromptTemplate sends the variant and maps the built-in result', () async {
    final rpc = FakeSettingsRpc()
      ..resetPromptTemplateResponse = generated.ResetPromptTemplateResponse(
        template: generated.PromptTemplate(
          variant: check_ins
              .CheckInPromptVariant
              .CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW,
          body: 'Built-in personal body',
          customised: false,
          rules: 'RULES',
        ),
      );

    final reset = await GrpcSettingsApi(
      rpc: rpc,
    ).resetPromptTemplate(CheckInPromptVariant.personalReview);

    expect(
      rpc.resetPromptTemplateRequest!.variant,
      check_ins
          .CheckInPromptVariant
          .CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW,
    );
    expect(reset.variant, CheckInPromptVariant.personalReview);
    expect(reset.body, 'Built-in personal body');
    expect(reset.customised, isFalse);
  });

  test('a blank prompt template failure exposes the body field', () async {
    final rpc = FakeSettingsRpc()
      ..error = GrpcError.invalidArgument(
        'body: is required; use Reset to restore the built-in',
      );

    expect(
      () => GrpcSettingsApi(
        rpc: rpc,
      ).updatePromptTemplate(CheckInPromptVariant.managerOneOnOne, 'x'),
      throwsA(
        isA<SettingsFailure>()
            .having((failure) => failure.field, 'field', 'body')
            .having(
              (failure) => failure.message,
              'message',
              'body: is required; use Reset to restore the built-in',
            ),
      ),
    );
  });

  test('AI provider presets seed a base URL and an editable model', () {
    expect(AIProviderPreset.anthropic.baseUrl, 'https://api.anthropic.com');
    expect(AIProviderPreset.anthropic.model, 'claude-sonnet-5-5');
    expect(
      AIProviderPreset.deepSeek.baseUrl,
      'https://api.deepseek.com/anthropic',
    );
    expect(AIProviderPreset.deepSeek.model, 'deepseek-flash');
    expect(
      AIProviderPreset.forBaseUrl('https://api.deepseek.com/anthropic'),
      AIProviderPreset.deepSeek,
    );
    expect(
      AIProviderPreset.forBaseUrl('https://proxy.example'),
      AIProviderPreset.custom,
    );
  });

  test('new settings start with the Anthropic preset', () {
    const settings = AppSettings();

    expect(settings.aiBaseUrl, 'https://api.anthropic.com');
    expect(settings.aiModel, 'claude-sonnet-5-5');
    expect(settings.hasAiApiKey, isFalse);
  });

  test('updateSettings sends and returns the support-people roster', () async {
    final rpc = FakeSettingsRpc()
      ..updateResponse = generated.UpdateSettingsResponse(
        settings: generated.Settings(supportPeople: ['Priya', 'Sam']),
      );

    final saved = await GrpcSettingsApi(rpc: rpc)
        .updateSettings(const AppSettings(supportPeople: ['Priya', 'Sam']));

    expect(rpc.updateRequest!.settings.supportPeople, ['Priya', 'Sam']);
    expect(saved.supportPeople, ['Priya', 'Sam']);
  });

  test('an unrelated settings change keeps the roster', () {
    const settings = AppSettings(supportPeople: ['Priya', 'Sam']);

    final changed = settings.copyWith(timezone: 'Europe/Amsterdam');
    expect(changed.supportPeople, ['Priya', 'Sam']);

    final roundTripped = AppSettings.fromJson(settings.toJson());
    expect(roundTripped.supportPeople, ['Priya', 'Sam']);
  });
}
