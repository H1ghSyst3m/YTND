class AppSettings {
  const AppSettings({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.userId = '',
    this.sessionCookie = '',
    this.syncIntervalHours = 0,
    this.syncWifiOnly = false,
    this.syncOnStartup = false,
    this.storagePath = defaultStoragePath,
  });

  static const String defaultStoragePath = '/storage/emulated/0/Music/YTND';

  final String serverUrl;
  final String username;
  final String password;
  final String userId;
  final String sessionCookie;
  final int syncIntervalHours;
  final bool syncWifiOnly;
  final bool syncOnStartup;
  final String storagePath;

  AppSettings copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? userId,
    String? sessionCookie,
    int? syncIntervalHours,
    bool? syncWifiOnly,
    bool? syncOnStartup,
    String? storagePath,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      userId: userId ?? this.userId,
      sessionCookie: sessionCookie ?? this.sessionCookie,
      syncIntervalHours: syncIntervalHours ?? this.syncIntervalHours,
      syncWifiOnly: syncWifiOnly ?? this.syncWifiOnly,
      syncOnStartup: syncOnStartup ?? this.syncOnStartup,
      storagePath: storagePath ?? this.storagePath,
    );
  }
}
