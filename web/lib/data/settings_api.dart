import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as duration;

import '../models/app_settings.dart';
import '../src/generated/settings.pbgrpc.dart' as generated;
import 'grpc_channel.dart';
import 'grpc_errors.dart';

/// Build and schema information shown in Settings → About.
class AboutInfo {
  const AboutInfo({
    required this.version,
    required this.schemaVersion,
    required this.license,
  });

  final String version;
  final int schemaVersion;
  final String license;
}

class SettingsSnapshot {
  const SettingsSnapshot({required this.settings, required this.about});

  final AppSettings settings;
  final AboutInfo about;
}

/// A user-facing settings failure, with the field the service rejected.
class SettingsFailure extends ServiceFailure {
  const SettingsFailure(super.message, {super.field});
}

/// The per-user behaviour and appearance operations Settings consumes.
abstract class SettingsApi {
  Future<SettingsSnapshot> getSettings();

  Future<AppSettings> updateSettings(AppSettings settings);
}

/// The narrow generated-client surface, separated so field mapping and error
/// translation can be tested without a network channel.
abstract class SettingsRpc {
  Future<generated.GetSettingsResponse> getSettings();

  Future<generated.UpdateSettingsResponse> updateSettings(
    generated.UpdateSettingsRequest request,
  );
}

/// The generated Connect client over gRPC-Web.
class GrpcSettingsRpc implements SettingsRpc {
  GrpcSettingsRpc({
    generated.SettingsServiceClient? client,
    String? Function()? token,
  }) : _client =
           client ??
           generated.SettingsServiceClient(
             openAppChannel(),
             interceptors: [bearerInterceptor(token ?? (() => null))],
           );

  final generated.SettingsServiceClient _client;

  @override
  Future<generated.GetSettingsResponse> getSettings() =>
      _client.getSettings(generated.GetSettingsRequest());

  @override
  Future<generated.UpdateSettingsResponse> updateSettings(
    generated.UpdateSettingsRequest request,
  ) => _client.updateSettings(request);
}

/// Settings over Connect/gRPC-Web.
class GrpcSettingsApi implements SettingsApi {
  GrpcSettingsApi({SettingsRpc? rpc}) : _rpc = rpc ?? GrpcSettingsRpc();

  final SettingsRpc _rpc;

  @override
  Future<SettingsSnapshot> getSettings() async {
    try {
      final response = await _rpc.getSettings();
      return SettingsSnapshot(
        settings: _fromProto(response.settings, const AppSettings()),
        about: AboutInfo(
          version: response.about.version,
          schemaVersion: response.about.schemaVersion,
          license: response.about.license,
        ),
      );
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<AppSettings> updateSettings(AppSettings settings) async {
    try {
      final response = await _rpc.updateSettings(
        generated.UpdateSettingsRequest(settings: _toProto(settings)),
      );
      return _fromProto(response.settings, settings);
    } on GrpcError catch (error) {
      throw _failure(error);
    }
  }

  AppSettings _fromProto(generated.Settings settings, AppSettings fallback) =>
      fallback.copyWith(
        timezone: settings.timezone,
        weekStart: settings.weekStart,
        dailyTargetHours: settings.dailyTarget.seconds.toInt() / 3600,
        longTimerMinutes: settings.longTimerThreshold.seconds.toInt() ~/ 60,
        defaultDurationMinutes:
            settings.defaultEntryDuration.seconds.toInt() ~/ 60,
        reviewCadence: _reviewCadenceFromProto(settings.reviewCadence),
        theme: _themeFromProto(settings.theme),
        density: _densityFromProto(settings.density),
        backupDir: settings.backupDirectory,
        backupIntervalHours: settings.backupInterval.seconds.toInt() ~/ 3600,
        retentionCount: settings.backupRetention,
        aiBaseUrl: settings.aiBaseUrl,
        aiModel: settings.aiModel,
        redactUrls: settings.aiRedact,
        journalStartDate: settings.journalStartDate,
      );

  generated.Settings _toProto(AppSettings settings) => generated.Settings(
    timezone: settings.timezone,
    weekStart: settings.weekStart,
    dailyTarget: _minutesDuration((settings.dailyTargetHours * 60).round()),
    reviewCadence: _reviewCadenceToProto(settings.reviewCadence),
    longTimerThreshold: _minutesDuration(settings.longTimerMinutes),
    defaultEntryDuration: _minutesDuration(settings.defaultDurationMinutes),
    backupDirectory: settings.backupDir,
    backupInterval: _minutesDuration(settings.backupIntervalHours * 60),
    backupRetention: settings.retentionCount,
    aiBaseUrl: settings.aiBaseUrl,
    aiModel: settings.aiModel,
    aiRedact: settings.redactUrls,
    theme: _themeToProto(settings.theme),
    density: _densityToProto(settings.density),
    journalStartDate: settings.journalStartDate,
  );

  SettingsFailure _failure(GrpcError error) {
    final text = describeGrpcError(
      error,
      unavailable:
          'The service is unreachable. Check that the server is running.',
      unauthenticated: 'Sign in again to change settings.',
    );
    return SettingsFailure(text.message, field: text.field);
  }
}

duration.Duration _minutesDuration(int minutes) =>
    duration.Duration(seconds: Int64(minutes * 60));

ReviewCadence _reviewCadenceFromProto(generated.ReviewCadence cadence) {
  switch (cadence) {
    case generated.ReviewCadence.REVIEW_CADENCE_WEEKLY:
      return ReviewCadence.weekly;
    case generated.ReviewCadence.REVIEW_CADENCE_MONTHLY:
      return ReviewCadence.monthly;
    default:
      return ReviewCadence.off;
  }
}

generated.ReviewCadence _reviewCadenceToProto(ReviewCadence cadence) {
  switch (cadence) {
    case ReviewCadence.weekly:
      return generated.ReviewCadence.REVIEW_CADENCE_WEEKLY;
    case ReviewCadence.monthly:
      return generated.ReviewCadence.REVIEW_CADENCE_MONTHLY;
    case ReviewCadence.off:
      return generated.ReviewCadence.REVIEW_CADENCE_OFF;
  }
}

ThemePreference _themeFromProto(generated.ThemePreference theme) {
  switch (theme) {
    case generated.ThemePreference.THEME_PREFERENCE_LIGHT:
      return ThemePreference.light;
    case generated.ThemePreference.THEME_PREFERENCE_DARK:
      return ThemePreference.dark;
    case generated.ThemePreference.THEME_PREFERENCE_HIGH_CONTRAST:
      return ThemePreference.highContrast;
    default:
      return ThemePreference.system;
  }
}

generated.ThemePreference _themeToProto(ThemePreference theme) {
  switch (theme) {
    case ThemePreference.system:
      return generated.ThemePreference.THEME_PREFERENCE_SYSTEM;
    case ThemePreference.light:
      return generated.ThemePreference.THEME_PREFERENCE_LIGHT;
    case ThemePreference.dark:
      return generated.ThemePreference.THEME_PREFERENCE_DARK;
    case ThemePreference.highContrast:
      return generated.ThemePreference.THEME_PREFERENCE_HIGH_CONTRAST;
  }
}

DensityPreference _densityFromProto(generated.DensityPreference density) =>
    density == generated.DensityPreference.DENSITY_PREFERENCE_COMPACT
    ? DensityPreference.compact
    : DensityPreference.comfortable;

generated.DensityPreference _densityToProto(DensityPreference density) =>
    density == DensityPreference.compact
    ? generated.DensityPreference.DENSITY_PREFERENCE_COMPACT
    : generated.DensityPreference.DENSITY_PREFERENCE_COMFORTABLE;
