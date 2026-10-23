import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;

import 'package:wdid_web/data/settings_api.dart';
import 'package:wdid_web/models/app_settings.dart';
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
}
