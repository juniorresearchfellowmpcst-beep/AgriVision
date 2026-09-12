import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// Live telemetry from the flight controller, as relayed by the backend's
/// MAVLink link (`GET /api/mavlink/status`).
///
/// Every field is nullable on purpose: a vehicle that has just booted reports
/// a mode and battery long before it has a GPS fix, and the live screen shows
/// "—" rather than a made-up number for anything that hasn't arrived yet.
class TelemetryEntity extends Equatable {
  const TelemetryEntity({
    this.armed = false,
    this.mode,
    this.systemStatus,
    this.latitude,
    this.longitude,
    this.relativeAltitudeM,
    this.altitudeMslM,
    this.headingDeg,
    this.groundspeedMs,
    this.airspeedMs,
    this.climbMs,
    this.throttlePct,
    this.batteryPercent,
    this.voltageV,
    this.currentA,
    this.gpsFix,
    this.satellites,
    this.currentWaypoint,
    this.missionItems,
  });

  final bool armed;
  final String? mode; // GUIDED / AUTO / RTL / LAND …
  final String? systemStatus; // standby / active / critical …
  final double? latitude;
  final double? longitude;
  final double? relativeAltitudeM; // above the launch point
  final double? altitudeMslM;
  final double? headingDeg;
  final double? groundspeedMs;
  final double? airspeedMs;
  final double? climbMs;
  final int? throttlePct;
  final int? batteryPercent;
  final double? voltageV;
  final double? currentA;
  final int? gpsFix; // 0 none, 2 2-D, 3 3-D, 4+ RTK
  final int? satellites;
  final int? currentWaypoint;
  final int? missionItems;

  /// Vehicle position, or null until the first GPS fix.
  LatLng? get position => (latitude != null && longitude != null)
      ? LatLng(latitude!, longitude!)
      : null;

  bool get hasGpsFix => (gpsFix ?? 0) >= 2 && position != null;

  /// Rough progress through the uploaded mission (0–1), for the live screen.
  double? get missionProgress {
    final total = missionItems;
    final current = currentWaypoint;
    if (total == null || current == null || total <= 1) return null;
    return (current / (total - 1)).clamp(0.0, 1.0);
  }

  static double? _toDouble(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  static int? _toInt(dynamic v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

  factory TelemetryEntity.fromJson(Map<String, dynamic> json) {
    return TelemetryEntity(
      armed: json['armed'] == true,
      mode: json['mode'] as String?,
      systemStatus: json['system_status'] as String?,
      latitude: _toDouble(json['lat']),
      longitude: _toDouble(json['lon']),
      relativeAltitudeM: _toDouble(json['relative_alt_m']),
      altitudeMslM: _toDouble(json['alt_msl_m']),
      headingDeg: _toDouble(json['heading_deg']),
      groundspeedMs: _toDouble(json['groundspeed_ms']),
      airspeedMs: _toDouble(json['airspeed_ms']),
      climbMs: _toDouble(json['climb_ms']),
      throttlePct: _toInt(json['throttle_pct']),
      batteryPercent: _toInt(json['battery_percent']),
      voltageV: _toDouble(json['voltage_v']),
      currentA: _toDouble(json['current_a']),
      gpsFix: _toInt(json['gps_fix']),
      satellites: _toInt(json['satellites']),
      currentWaypoint: _toInt(json['current_wp']),
      missionItems: _toInt(json['mission_items']),
    );
  }

  @override
  List<Object?> get props => [
    armed,
    mode,
    systemStatus,
    latitude,
    longitude,
    relativeAltitudeM,
    altitudeMslM,
    headingDeg,
    groundspeedMs,
    airspeedMs,
    climbMs,
    throttlePct,
    batteryPercent,
    voltageV,
    currentA,
    gpsFix,
    satellites,
    currentWaypoint,
    missionItems,
  ];
}

/// A status message the autopilot sent (pre-arm warnings, mode changes…).
class VehicleMessage extends Equatable {
  const VehicleMessage({
    required this.severity,
    required this.text,
    this.ageS,
  });

  final int severity; // MAV_SEVERITY: 0 emergency … 6 info, 7 debug
  final String text;

  /// Seconds since the vehicle said it, measured by the backend. A timestamp
  /// would be no use here: the phone's clock is not the server's.
  final double? ageS;

  bool get isWarning => severity <= 4;

  /// Worth putting in front of the operator mid-flight: a warning, and new.
  bool get isLiveWarning => isWarning && (ageS ?? double.infinity) <= 30;

  factory VehicleMessage.fromJson(Map<String, dynamic> json) => VehicleMessage(
    severity: json['severity'] is num ? (json['severity'] as num).toInt() : 6,
    text: (json['text'] ?? '').toString(),
    ageS: json['age_s'] is num ? (json['age_s'] as num).toDouble() : null,
  );

  @override
  List<Object?> get props => [severity, text, ageS];
}

/// Answer to `GET /api/mavlink/preflight`: what would stop a launch now.
class PreflightReport extends Equatable {
  const PreflightReport({
    required this.ready,
    this.problems = const [],
    this.link = const MavlinkStatusEntity(),
  });

  /// True when nothing the backend can see stands in the way. The autopilot
  /// still runs its own pre-arm checks and has the last word.
  final bool ready;

  /// Plain sentences, each naming something the operator can fix.
  final List<String> problems;

  final MavlinkStatusEntity link;

  factory PreflightReport.fromJson(Map<String, dynamic> json) => PreflightReport(
    ready: json['ready'] == true,
    problems: [
      for (final problem in (json['problems'] as List? ?? const []))
        problem.toString(),
    ],
    link: MavlinkStatusEntity.fromJson(json),
  );

  @override
  List<Object?> get props => [ready, problems, link];
}

/// Full `GET /api/mavlink/status` payload: link health + telemetry.
class MavlinkStatusEntity extends Equatable {
  const MavlinkStatusEntity({
    this.available = false,
    this.connected = false,
    this.alive = false,
    this.url,
    this.heartbeatAgeS,
    this.telemetry = const TelemetryEntity(),
    this.messages = const [],
    this.autopilot,
    this.vehicleType,
    this.flightControlSupported = false,
    this.missionKind,
  });

  /// Whether the backend has pymavlink installed at all.
  final bool available;

  /// A link is open (the socket exists).
  final bool connected;

  /// Connected *and* heartbeats are still arriving — the flight-worthy state.
  final bool alive;

  final String? url;
  final double? heartbeatAgeS;
  final TelemetryEntity telemetry;
  final List<VehicleMessage> messages;

  /// What the aircraft says it is: 'ardupilot', 'px4', 'other'.
  final String? autopilot;

  /// 'quadrotor', 'hexarotor', 'fixed_wing', …
  final String? vehicleType;

  /// Whether the app will fly this vehicle at all. Missions, the launch
  /// sequence and the spray commands are written for ArduPilot; anything else
  /// still gets telemetry, and says so instead of failing strangely.
  final bool flightControlSupported;

  /// What was last written to the vehicle: 'survey' or 'spray'.
  final String? missionKind;

  /// A warning the vehicle has just given — worth showing over a live map.
  VehicleMessage? get latestWarning {
    for (final message in messages.reversed) {
      if (message.isLiveWarning) return message;
    }
    return null;
  }

  factory MavlinkStatusEntity.fromJson(Map<String, dynamic> json) {
    return MavlinkStatusEntity(
      available: json['available'] == true,
      connected: json['connected'] == true,
      alive: json['alive'] == true,
      url: json['url'] as String?,
      autopilot: json['autopilot'] as String?,
      vehicleType: json['vehicle_type'] as String?,
      flightControlSupported: json['flight_control_supported'] == true,
      missionKind: json['mission_kind'] as String?,
      heartbeatAgeS: json['heartbeat_age_s'] is num
          ? (json['heartbeat_age_s'] as num).toDouble()
          : null,
      telemetry: json['telemetry'] is Map
          ? TelemetryEntity.fromJson(
              Map<String, dynamic>.from(json['telemetry'] as Map),
            )
          : const TelemetryEntity(),
      messages: [
        for (final m in (json['messages'] as List? ?? const []))
          if (m is Map) VehicleMessage.fromJson(Map<String, dynamic>.from(m)),
      ],
    );
  }

  @override
  List<Object?> get props => [
    available,
    connected,
    alive,
    url,
    heartbeatAgeS,
    telemetry,
    messages,
    autopilot,
    vehicleType,
    flightControlSupported,
    missionKind,
  ];
}
