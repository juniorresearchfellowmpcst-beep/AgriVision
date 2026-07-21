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

  static PilotProfileEntity getDummyData() => const PilotProfileEntity(
    initials: 'RP',
    name: 'Raj Patel',
    role: 'Operator',
    organisation: 'Patel Agro Farms Ltd.',
    email: 'raj.patel@agridrone.in',
    phone: '+91 98200 34712',
    location: 'Nashik, Maharashtra',
    missionsFlown: 47,
    areaFlownHa: 183,
    airTimeHours: 62,
  );
}

class PilotCredentialEntity {
  const PilotCredentialEntity({
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
  });

  final IconData icon;
  final String label;
  final String value;
  final CredentialStatus status;

  static List<PilotCredentialEntity> getDummyData() => const [
    PilotCredentialEntity(
      icon: Icons.badge_outlined,
      label: 'DRONE PILOT LICENCE',
      value: 'DGCA RPA-2024-MH-04871',
      status: CredentialStatus.valid,
    ),
    PilotCredentialEntity(
      icon: Icons.shield_outlined,
      label: 'PESTICIDE OPERATOR CERT.',
      value: 'IAPMC-OP-2023-7712',
      status: CredentialStatus.valid,
    ),
    PilotCredentialEntity(
      icon: Icons.check_circle_outline,
      label: 'FLIGHT ZONE CLEARANCE',
      value: 'Zone A, B · Active',
      status: CredentialStatus.valid,
    ),
    PilotCredentialEntity(
      icon: Icons.warning_amber_rounded,
      label: 'INSURANCE POLICY',
      value: 'Expires Sep 2026',
      status: CredentialStatus.expiring,
    ),
  ];
}

class AssignedDroneEntity {
  const AssignedDroneEntity({
    required this.unitName,
    required this.serialNumber,
    required this.frequency,
    required this.isConnected,
    required this.signalDbm,
    required this.batteryPercent,
    required this.tankPercent,
    required this.totalFlights,
    this.gpsSatellites = 0,
    this.status = 'available',
  });

  final String unitName;
  final String serialNumber;
  final String frequency;
  final bool isConnected;
  final String signalDbm;
  final int batteryPercent;
  final int tankPercent;
  final int totalFlights;
  final int gpsSatellites;
  final String status;

  /// Builds from the backend drone dict (GET /api/drones/status).
  factory AssignedDroneEntity.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.round() : 0;
    final signal = json['signal_dbm'];

    return AssignedDroneEntity(
      unitName: json['name']?.toString() ?? 'Drone',
      serialNumber: json['serial_number']?.toString() ?? '—',
      frequency: json['frequency']?.toString() ?? '—',
      isConnected: json['is_connected'] == true,
      signalDbm: signal is num ? '${signal.round()} dBm' : '—',
      batteryPercent: asInt(json['battery_percent']),
      tankPercent: asInt(json['tank_percent']),
      totalFlights: asInt(json['total_flights']),
      gpsSatellites: asInt(json['gps_satellites']),
      status: json['status']?.toString() ?? 'available',
    );
  }

  static AssignedDroneEntity getDummyData() => const AssignedDroneEntity(
    unitName: 'AgriDrone Unit GCS-04',
    serialNumber: 'ADU-2024-04-7832',
    frequency: '2.4 GHz',
    isConnected: true,
    signalDbm: '−68 dBm',
    batteryPercent: 84,
    tankPercent: 63,
    totalFlights: 312,
  );
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
