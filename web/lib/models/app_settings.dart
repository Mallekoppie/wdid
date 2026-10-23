enum ThemePreference {
  system,
  light,
  dark,
  highContrast;

  static ThemePreference parse(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return ThemePreference.values.firstWhere(
      (preference) => preference.name == normalized,
      orElse: () => ThemePreference.system,
    );
  }

  String get label => switch (this) {
    ThemePreference.system => 'System',
    ThemePreference.light => 'Light',
    ThemePreference.dark => 'Dark',
    ThemePreference.highContrast => 'High contrast',
  };
}

enum DensityPreference {
  comfortable,
  compact;

  static DensityPreference parse(Object? value) =>
      value?.toString() == 'compact'
      ? DensityPreference.compact
      : DensityPreference.comfortable;

  String get label =>
      this == DensityPreference.compact ? 'Compact' : 'Comfortable';
}

/// Controls the personal-review prompt.
enum ReviewCadence {
  weekly,
  monthly,
  off;

  static ReviewCadence parse(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return ReviewCadence.values.firstWhere(
      (cadence) => cadence.name == normalized,
      orElse: () => ReviewCadence.off,
    );
  }

  String get label => switch (this) {
    ReviewCadence.weekly => 'Weekly',
    ReviewCadence.monthly => 'Monthly',
    ReviewCadence.off => 'Off',
  };
}

class AppSettings {
  const AppSettings({
    this.timezone = 'UTC',
    this.weekStart = 1,
    this.dailyTargetHours = 7.5,
    this.longTimerMinutes = 240,
    this.defaultDurationMinutes = 30,
    this.reviewCadence = ReviewCadence.off,
    this.journalStartDate = '',
    this.theme = ThemePreference.system,
    this.density = DensityPreference.comfortable,
    this.dataDir = '/var/lib/wdid/data',
    this.databasePath = '/var/lib/wdid/data/wdid.db',
    this.backupDir = '/var/lib/wdid/backups',
    this.backupIntervalHours = 6,
    this.retentionCount = 30,
    this.aiProvider = 'OpenAI-compatible',
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiModel = 'gpt-4.1-mini',
    this.aiKeySource = 'environment',
    this.redactUrls = false,
    this.lastBackupAt,
    this.lastBackupBytes = 0,
    this.version = '0.1.0',
    this.schemaVersion = 1,
    this.license = 'MIT',
  });

  final String timezone;

  /// 1 = Monday, 7 = Sunday.
  final int weekStart;
  final double dailyTargetHours;
  final int longTimerMinutes;
  final int defaultDurationMinutes;
  final ReviewCadence reviewCadence;
  final String journalStartDate;
  final ThemePreference theme;
  final DensityPreference density;

  final String dataDir;
  final String databasePath;
  final String backupDir;
  final int backupIntervalHours;
  final int retentionCount;

  final String aiProvider;
  final String aiBaseUrl;
  final String aiModel;
  final String aiKeySource;
  final bool redactUrls;

  final DateTime? lastBackupAt;
  final int lastBackupBytes;

  final String version;
  final int schemaVersion;
  final String license;

  AppSettings copyWith({
    String? timezone,
    int? weekStart,
    double? dailyTargetHours,
    int? longTimerMinutes,
    int? defaultDurationMinutes,
    ReviewCadence? reviewCadence,
    String? journalStartDate,
    ThemePreference? theme,
    DensityPreference? density,
    String? dataDir,
    String? databasePath,
    String? backupDir,
    int? backupIntervalHours,
    int? retentionCount,
    String? aiProvider,
    String? aiBaseUrl,
    String? aiModel,
    String? aiKeySource,
    bool? redactUrls,
    DateTime? lastBackupAt,
    int? lastBackupBytes,
    String? version,
    int? schemaVersion,
    String? license,
  }) {
    return AppSettings(
      timezone: timezone ?? this.timezone,
      weekStart: weekStart ?? this.weekStart,
      dailyTargetHours: dailyTargetHours ?? this.dailyTargetHours,
      longTimerMinutes: longTimerMinutes ?? this.longTimerMinutes,
      defaultDurationMinutes:
          defaultDurationMinutes ?? this.defaultDurationMinutes,
      reviewCadence: reviewCadence ?? this.reviewCadence,
      journalStartDate: journalStartDate ?? this.journalStartDate,
      theme: theme ?? this.theme,
      density: density ?? this.density,
      dataDir: dataDir ?? this.dataDir,
      databasePath: databasePath ?? this.databasePath,
      backupDir: backupDir ?? this.backupDir,
      backupIntervalHours: backupIntervalHours ?? this.backupIntervalHours,
      retentionCount: retentionCount ?? this.retentionCount,
      aiProvider: aiProvider ?? this.aiProvider,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
      aiModel: aiModel ?? this.aiModel,
      aiKeySource: aiKeySource ?? this.aiKeySource,
      redactUrls: redactUrls ?? this.redactUrls,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastBackupBytes: lastBackupBytes ?? this.lastBackupBytes,
      version: version ?? this.version,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      license: license ?? this.license,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    timezone: json['timezone']?.toString() ?? 'UTC',
    weekStart: (json['weekStart'] as num?)?.round() ?? 1,
    dailyTargetHours: (json['dailyTargetHours'] as num?)?.toDouble() ?? 7.5,
    longTimerMinutes: (json['longTimerMinutes'] as num?)?.round() ?? 240,
    defaultDurationMinutes:
        (json['defaultDurationMinutes'] as num?)?.round() ?? 30,
    reviewCadence: ReviewCadence.parse(json['reviewCadence']),
    theme: ThemePreference.parse(json['theme']),
    density: DensityPreference.parse(json['density']),
    dataDir: json['dataDir']?.toString() ?? '/var/lib/wdid/data',
    databasePath:
        json['databasePath']?.toString() ?? '/var/lib/wdid/data/wdid.db',
    backupDir: json['backupDir']?.toString() ?? '/var/lib/wdid/backups',
    backupIntervalHours: (json['backupIntervalHours'] as num?)?.round() ?? 6,
    retentionCount: (json['retentionCount'] as num?)?.round() ?? 30,
    aiProvider: json['aiProvider']?.toString() ?? 'OpenAI-compatible',
    aiBaseUrl: json['aiBaseUrl']?.toString() ?? 'https://api.openai.com/v1',
    aiModel: json['aiModel']?.toString() ?? 'gpt-4.1-mini',
    aiKeySource: json['aiKeySource']?.toString() ?? 'environment',
    redactUrls: json['redactUrls'] == true,
    lastBackupAt: DateTime.tryParse(json['lastBackupAt']?.toString() ?? ''),
    lastBackupBytes: (json['lastBackupBytes'] as num?)?.round() ?? 0,
    version: json['version']?.toString() ?? '0.1.0',
    schemaVersion: (json['schemaVersion'] as num?)?.round() ?? 1,
    license: json['license']?.toString() ?? 'MIT',
  );

  Map<String, dynamic> toJson() => {
    'timezone': timezone,
    'weekStart': weekStart,
    'dailyTargetHours': dailyTargetHours,
    'longTimerMinutes': longTimerMinutes,
    'defaultDurationMinutes': defaultDurationMinutes,
    'reviewCadence': reviewCadence.name,
    'theme': theme.name,
    'density': density.name,
    'dataDir': dataDir,
    'databasePath': databasePath,
    'backupDir': backupDir,
    'backupIntervalHours': backupIntervalHours,
    'retentionCount': retentionCount,
    'aiProvider': aiProvider,
    'aiBaseUrl': aiBaseUrl,
    'aiModel': aiModel,
    'aiKeySource': aiKeySource,
    'redactUrls': redactUrls,
    'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
    'lastBackupBytes': lastBackupBytes,
    'version': version,
    'schemaVersion': schemaVersion,
    'license': license,
  };
}
