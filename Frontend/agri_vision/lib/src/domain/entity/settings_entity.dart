import 'package:equatable/equatable.dart';

/// The pilot's app preferences, from `GET /api/users/me/preferences`.
///
/// These live on the server rather than the device so the alerting a pilot
/// configures survives a reinstall, or signing in on the spare tablet in the
/// truck. Defaults are all-on: a new operator should hear about a problem and
/// then turn things down, not miss one because a toggle started off.
class UserPreferencesEntity extends Equatable {
  const UserPreferencesEntity({
    this.missionUpdates = true,
    this.aiAlerts = true,
    this.fieldReports = true,
    this.autoSync = true,
    this.pushNotifications = true,
  });

  // Profile → NOTIFICATION PREFERENCES
  final bool missionUpdates;
  final bool aiAlerts;
  final bool fieldReports;

  // Settings screen
  final bool autoSync;
  final bool pushNotifications;

  /// Wire keys, matching the backend's `PREFERENCE_DEFAULTS`.
  static const keyMissionUpdates = 'mission_updates';
  static const keyAiAlerts = 'ai_alerts';
  static const keyFieldReports = 'field_reports';
  static const keyAutoSync = 'auto_sync';
  static const keyPushNotifications = 'push_notifications';

  factory UserPreferencesEntity.fromJson(Map<String, dynamic> json) {
    bool read(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;

    return UserPreferencesEntity(
      missionUpdates: read(keyMissionUpdates, true),
      aiAlerts: read(keyAiAlerts, true),
      fieldReports: read(keyFieldReports, true),
      autoSync: read(keyAutoSync, true),
      pushNotifications: read(keyPushNotifications, true),
    );
  }

  /// Value of one toggle by its wire key — lets the UI drive every switch
  /// through a single handler instead of five near-identical ones.
  bool valueOf(String key) => switch (key) {
    keyMissionUpdates => missionUpdates,
    keyAiAlerts => aiAlerts,
    keyFieldReports => fieldReports,
    keyAutoSync => autoSync,
    keyPushNotifications => pushNotifications,
    _ => false,
  };

  UserPreferencesEntity withValue(String key, bool value) => switch (key) {
    keyMissionUpdates => copyWith(missionUpdates: value),
    keyAiAlerts => copyWith(aiAlerts: value),
    keyFieldReports => copyWith(fieldReports: value),
    keyAutoSync => copyWith(autoSync: value),
    keyPushNotifications => copyWith(pushNotifications: value),
    _ => this,
  };

  UserPreferencesEntity copyWith({
    bool? missionUpdates,
    bool? aiAlerts,
    bool? fieldReports,
    bool? autoSync,
    bool? pushNotifications,
  }) {
    return UserPreferencesEntity(
      missionUpdates: missionUpdates ?? this.missionUpdates,
      aiAlerts: aiAlerts ?? this.aiAlerts,
      fieldReports: fieldReports ?? this.fieldReports,
      autoSync: autoSync ?? this.autoSync,
      pushNotifications: pushNotifications ?? this.pushNotifications,
    );
  }

  @override
  List<Object?> get props => [
    missionUpdates,
    aiAlerts,
    fieldReports,
    autoSync,
    pushNotifications,
  ];
}

/// One row of the Settings screen's SYNC QUEUE, from
/// `GET /api/users/me/sync-status`.
///
/// [pending] counts records the *server* still considers open (a flight that
/// was never closed out). It never guesses at records still sitting unsent on
/// a device — the server cannot know about those.
class SyncItemEntity extends Equatable {
  const SyncItemEntity({
    required this.key,
    required this.label,
    required this.total,
    required this.pending,
  });

  final String key;
  final String label;
  final int total;
  final int pending;

  bool get isPending => pending > 0;

  /// What the row's count should read: outstanding work if there is any,
  /// otherwise how much is safely stored.
  int get displayCount => isPending ? pending : total;

  factory SyncItemEntity.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : 0;
    return SyncItemEntity(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '—',
      total: asInt(json['total']),
      pending: asInt(json['pending']),
    );
  }

  static List<SyncItemEntity> fromJsonList(List<dynamic> items) => [
    for (final item in items)
      if (item is Map) SyncItemEntity.fromJson(Map<String, dynamic>.from(item)),
  ];

  @override
  List<Object?> get props => [key, label, total, pending];
}
