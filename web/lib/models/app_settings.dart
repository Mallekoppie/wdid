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

  static DensityPreference parse(Object? value) => value?.toString() == 'compact'
      ? DensityPreference.compact
      : DensityPreference.comfortable;

  String get label => this == DensityPreference.compact ? 'Compact' : 'Comfortable';
}

class AppSettings {
  const AppSettings({
    this.timezone = 'UTC',
    this.weekStart = 1,
    this.dailyTargetHours = 7.5,
    this.rounding = 'none',
    this.longTimerHours = 4,
    this.defaultDurationMinutes = 30,
    this.theme = ThemePreference.system,
    this.density = DensityPreference.comfortable,
    this.dataDir = '/var/lib/logloop/data',
    this.databasePath = '/var/lib/logloop/data/logloop.db',
    this.backupDir = '/var/lib/logloop/backups',
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
  final String rounding;
  final int longTimerHours;
  final int defaultDurationMinutes;
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
    String? rounding,
    int? longTimerHours,
    int? defaultDurationMinutes,
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
  }) {
    return AppSettings(
      timezone: timezone ?? this.timezone,
      weekStart: weekStart ?? this.weekStart,
      dailyTargetHours: dailyTargetHours ?? this.dailyTargetHours,
      rounding: rounding ?? this.rounding,
      longTimerHours: longTimerHours ?? this.longTimerHours,
      defaultDurationMinutes:
          defaultDurationMinutes ?? this.defaultDurationMinutes,
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
      version: version,
      schemaVersion: schemaVersion,
      license: license,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        timezone: json['timezone']?.toString() ?? 'UTC',
        weekStart: (json['weekStart'] as num?)?.round() ?? 1,
        dailyTargetHours:
            (json['dailyTargetHours'] as num?)?.toDouble() ?? 7.5,
        rounding: json['rounding']?.toString() ?? 'none',
        longTimerHours: (json['longTimerHours'] as num?)?.round() ?? 4,
        defaultDurationMinutes:
            (json['defaultDurationMinutes'] as num?)?.round() ?? 30,
        theme: ThemePreference.parse(json['theme']),
        density: DensityPreference.parse(json['density']),
        dataDir: json['dataDir']?.toString() ?? '/var/lib/logloop/data',
        databasePath: json['databasePath']?.toString() ??
            '/var/lib/logloop/data/logloop.db',
        backupDir: json['backupDir']?.toString() ?? '/var/lib/logloop/backups',
        backupIntervalHours:
            (json['backupIntervalHours'] as num?)?.round() ?? 6,
        retentionCount: (json['retentionCount'] as num?)?.round() ?? 30,
        aiProvider: json['aiProvider']?.toString() ?? 'OpenAI-compatible',
        aiBaseUrl:
            json['aiBaseUrl']?.toString() ?? 'https://api.openai.com/v1',
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
        'rounding': rounding,
        'longTimerHours': longTimerHours,
        'defaultDurationMinutes': defaultDurationMinutes,
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
