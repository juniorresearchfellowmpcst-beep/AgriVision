import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

// ── Enums ──────────────────────────────────────────────────────────────────

enum CredentialStatus { valid, expiring, expired }

extension CredentialStatusX on CredentialStatus {
  String get label => switch (this) {
    CredentialStatus.valid => 'Valid',
    CredentialStatus.expiring => 'Expiring',
    CredentialStatus.expired => 'Expired',
  };

  Color get badgeBackground => switch (this) {
    CredentialStatus.valid => const Color(0xFFDCF0DE),
    CredentialStatus.expiring => const Color(0xFFFBEAC7),
    CredentialStatus.expired => const Color(0xFFFFE5E5),
  };

  Color get badgeText => switch (this) {
    CredentialStatus.valid => AppColors.themeSuccess,
    CredentialStatus.expiring => const Color(0xFF9A6A0B),
    CredentialStatus.expired => AppColors.themeError,
  };

  Color get iconBackground => switch (this) {
    CredentialStatus.valid => AppColors.primaryFade,
    CredentialStatus.expiring => const Color(0xFFFBEAC7),
    CredentialStatus.expired => const Color(0xFFFFE5E5),
  };

  Color get iconColor => switch (this) {
    CredentialStatus.valid => AppColors.primary,
    CredentialStatus.expiring => AppColors.themeWarning,
    CredentialStatus.expired => AppColors.themeError,
  };
}

enum ActivityType { missionCompleted, aiDetection, fieldReport }

extension ActivityTypeX on ActivityType {
  Color get dotColor => switch (this) {
    ActivityType.missionCompleted => AppColors.themeSuccess,
    ActivityType.aiDetection => AppColors.themeWarning,
    ActivityType.fieldReport => const Color(0xFF2E86DE),
  };
}

// ── Entities ───────────────────────────────────────────────────────────────

class PilotProfileEntity {
  const PilotProfileEntity({
    required this.initials,
    required this.name,
    required this.role,
    required this.organisation,
    required this.email,
    required this.phone,
    required this.location,
    required this.missionsFlown,
    required this.areaFlownHa,
    required this.airTimeHours,
  });

  final String initials;
  final String name;
  final String role;
  final String organisation;
  final String email;
  final String phone;
  final String location;
  final int missionsFlown;
  final int areaFlownHa;
  final int airTimeHours;

  /// Builds from the backend's GET /api/users/me payload.
  factory PilotProfileEntity.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] is Map<String, dynamic>
        ? json['stats'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final name = json['username']?.toString() ?? '';

    String orDash(dynamic v) {
      final s = v?.toString() ?? '';
      return s.isNotEmpty ? s : '—';
    }

    int asInt(dynamic v) => v is num ? v.round() : 0;

    return PilotProfileEntity(
      initials: initialsOf(name),
      name: name.isNotEmpty ? name : '—',
      role: orDash(json['role'] ?? 'Operator'),
      organisation: orDash(json['organisation']),
      email: orDash(json['email']),
      phone: orDash(json['phone']),
      location: orDash(json['location']),
      missionsFlown: asInt(stats['missions_flown']),
      areaFlownHa: asInt(stats['area_flown_ha']),
      airTimeHours: asInt(stats['air_time_hours']),
    );
  }

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  PilotProfileEntity copyWith({
    String? initials,
    String? name,
    String? email,
  }) {
    return PilotProfileEntity(
      initials: initials ?? this.initials,
      name: name ?? this.name,
      role: role,
      organisation: organisation,
      email: email ?? this.email,
      phone: phone,
      location: location,
      missionsFlown: missionsFlown,
      areaFlownHa: areaFlownHa,
      airTimeHours: airTimeHours,
    );
  }

  /// Placeholder shown while the profile is still loading, or when both the
  /// backend and the stored sign-in are unavailable.
  ///
  /// Deliberately blank rather than a plausible-looking sample pilot: showing
  /// somebody a name and licence that aren't theirs is worse than showing
  /// dashes, because they have no way to tell it is fake.
  static PilotProfileEntity empty() => const PilotProfileEntity(
    initials: '?',
    name: '—',
    role: 'Operator',
    organisation: '—',
    email: '—',
    phone: '—',
    location: '—',
    missionsFlown: 0,
    areaFlownHa: 0,
    airTimeHours: 0,
  );
}

/// A licence, certificate or clearance the pilot holds, from
/// `GET /api/credentials`.
///
/// The backend owns the status: it recomputes valid / expiring / expired from
/// the stored expiry date on every read, so the badge is never a stale value
/// the app cached at some earlier point.
class PilotCredentialEntity {
  const PilotCredentialEntity({
    required this.id,
    required this.kind,
    required this.label,
    required this.value,
    required this.status,
    this.issuer,
    this.expiresOn,
    this.daysUntilExpiry,
  });

  final int id;
  final String kind; // licence | certification | clearance | insurance | other
  final String label;
  final String value;
  final CredentialStatus status;
  final String? issuer;
  final DateTime? expiresOn;
  final int? daysUntilExpiry;

  /// Icon per credential kind, so the backend never has to know about
  /// Flutter's icon set.
  IconData get icon => switch (kind) {
    'licence' => Icons.badge_outlined,
    'certification' => Icons.shield_outlined,
    'clearance' => Icons.check_circle_outline,
    'insurance' => Icons.verified_user_outlined,
    _ => Icons.description_outlined,
  };

  /// True when the row exists but hasn't been filled in yet — a freshly
  /// seeded account starts with the required paperwork listed and blank.
  bool get isBlank => value.trim().isEmpty || value.trim() == '—';

  static CredentialStatus _statusOf(String? raw) => switch (raw) {
    'expiring' => CredentialStatus.expiring,
    'expired' => CredentialStatus.expired,
    _ => CredentialStatus.valid,
  };

  factory PilotCredentialEntity.fromJson(Map<String, dynamic> json) {
    return PilotCredentialEntity(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      kind: json['kind']?.toString() ?? 'other',
      label: json['label']?.toString() ?? '—',
      value: json['value']?.toString() ?? '—',
      status: _statusOf(json['status']?.toString()),
      issuer: json['issuer']?.toString(),
      expiresOn: DateTime.tryParse(json['expires_on']?.toString() ?? ''),
      daysUntilExpiry: json['days_until_expiry'] is num
          ? (json['days_until_expiry'] as num).toInt()
          : null,
    );
  }

  static List<PilotCredentialEntity> fromJsonList(List<dynamic> items) => [
    for (final item in items)
      if (item is Map)
        PilotCredentialEntity.fromJson(Map<String, dynamic>.from(item)),
  ];
}

/// The drone paired to this account, as the server currently sees it.
///
/// The gauges are nullable on purpose: the backend reports them only while a
/// vehicle is on the MAVLink link or the GCS is pushing telemetry. Null means
/// "not being reported", and every screen renders that as an em dash rather
/// than a plausible-looking number.
class AssignedDroneEntity {
  const AssignedDroneEntity({
    required this.unitName,
    required this.serialNumber,
    required this.frequency,
    required this.isConnected,
    required this.totalFlights,
    this.signalDbm,
    this.batteryPercent,
    this.tankPercent,
    this.gpsSatellites,
    this.status = 'available',
  });

  final String unitName;
  final String serialNumber;
  final String frequency;
  final bool isConnected;
  final int? signalDbm;
  final int? batteryPercent;
  final int? tankPercent;
  final int totalFlights;
  final int? gpsSatellites;
  final String status;

  /// Builds from the backend drone dict (GET /api/drones/status).
  factory AssignedDroneEntity.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) => v is num ? v.round() : null;

    return AssignedDroneEntity(
      unitName: json['name']?.toString() ?? 'Drone',
      serialNumber: json['serial_number']?.toString() ?? '—',
      frequency: json['frequency']?.toString() ?? '—',
      isConnected: json['is_connected'] == true,
      signalDbm: asInt(json['signal_dbm']),
      batteryPercent: asInt(json['battery_percent']),
      tankPercent: asInt(json['tank_percent']),
      totalFlights: asInt(json['total_flights']) ?? 0,
      gpsSatellites: asInt(json['gps_satellites']),
      status: json['status']?.toString() ?? 'available',
    );
  }

  /// Display helpers — one place deciding what "unknown" looks like.
  String get batteryLabel =>
      batteryPercent == null ? '—' : '$batteryPercent%';

  String get tankLabel => tankPercent == null ? '—' : '$tankPercent%';

  String get gpsLabel => gpsSatellites == null ? '—' : '$gpsSatellites';

  String get signalLabel => signalDbm == null ? '—' : '$signalDbm dBm';

  /// 'AgriDrone Unit GCS-04' → 'GCS-04' for compact chips and banners.
  String get shortId {
    final parts = unitName.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.last : unitName;
  }
}

class ProfileActivityEntity {
  const ProfileActivityEntity({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.type,
  });

  final String title;
  final String subtitle;
  final String time;
  final ActivityType type;

  static List<ProfileActivityEntity> getDummyData() => const [
    ProfileActivityEntity(
      title: 'Completed mission',
      subtitle: 'Block A – North Section',
      time: 'Today, 09:52 AM',
      type: ActivityType.missionCompleted,
    ),
    ProfileActivityEntity(
      title: 'Approved AI detection',
      subtitle: 'Leaf Blight · Block A R14',
      time: 'Today, 09:42 AM',
      type: ActivityType.aiDetection,
    ),
    ProfileActivityEntity(
      title: 'Exported field report',
      subtitle: 'Block A · Jun 23 2026',
      time: 'Today, 10:05 AM',
      type: ActivityType.fieldReport,
    ),
    ProfileActivityEntity(
      title: 'Completed mission',
      subtitle: 'Orchard Rows 7–12',
      time: 'Jun 19, 11:30 AM',
      type: ActivityType.missionCompleted,
    ),
  ];
}
