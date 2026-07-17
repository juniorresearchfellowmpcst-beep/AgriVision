import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// ── Waypoint ───────────────────────────────────────────────────────────────

class WaypointModel {
  const WaypointModel({
    required this.id,
    required this.position, // geographic coordinate (WGS 84)
    this.isSelected = false,
  });

  final int id;
  final LatLng position;
  final bool isSelected;

  WaypointModel copyWith({LatLng? position, bool? isSelected}) => WaypointModel(
    id: id,
    position: position ?? this.position,
    isSelected: isSelected ?? this.isSelected,
  );

  /// Demo survey block over farmland near Bhopal, MP (~4 ha).
  static List<WaypointModel> defaultWaypoints() => [
    const WaypointModel(id: 1, position: LatLng(23.19180, 77.42020)),
    const WaypointModel(id: 2, position: LatLng(23.19200, 77.42074)),
    const WaypointModel(id: 3, position: LatLng(23.19200, 77.42193)),
    const WaypointModel(id: 4, position: LatLng(23.19180, 77.42247)),
    const WaypointModel(id: 5, position: LatLng(23.19125, 77.42247)),
    const WaypointModel(id: 6, position: LatLng(23.19105, 77.42193)),
    const WaypointModel(id: 7, position: LatLng(23.19070, 77.42215)),
    const WaypointModel(id: 8, position: LatLng(23.19070, 77.42085)),
    const WaypointModel(id: 9, position: LatLng(23.19100, 77.42020)),
    const WaypointModel(id: 10, position: LatLng(23.19137, 77.42020)),
  ];
}

// ── Mission layer enum ─────────────────────────────────────────────────────

/// Only layers with a real tile source belong here — the selector sheet
/// renders every value, so a layer without authentic data must not exist.
enum MapLayer { satellite, terrain, hybrid }

extension MapLayerX on MapLayer {
  String get label => switch (this) {
    MapLayer.satellite => 'Satellite',
    MapLayer.terrain => 'Terrain',
    MapLayer.hybrid => 'Hybrid',
  };

  IconData get icon => switch (this) {
    MapLayer.satellite => Icons.satellite_alt,
    MapLayer.terrain => Icons.landscape_outlined,
    MapLayer.hybrid => Icons.layers_outlined,
  };
}

// ── Mission mode ───────────────────────────────────────────────────────────

/// Flight profile chosen when launching a mission.
enum MissionMode { multispectral, scouting }

extension MissionModeX on MissionMode {
  String get label => switch (this) {
    MissionMode.multispectral => 'High-Speed Survey',
    MissionMode.scouting => 'Low-Pace Scouting',
  };

  String get description => switch (this) {
    MissionMode.multispectral =>
      'Fast pass for multispectral assessment — crop health indices over the whole block',
    MissionMode.scouting =>
      'Slow, detailed pass for weed, pest and disease detection in the field',
  };

  IconData get icon => switch (this) {
    MissionMode.multispectral => Icons.speed_rounded,
    MissionMode.scouting => Icons.pest_control_outlined,
  };

  /// Cruise speed for the profile (m/s).
  double get speed => switch (this) {
    MissionMode.multispectral => 12.0,
    MissionMode.scouting => 4.0,
  };
}

// ── Mission settings ───────────────────────────────────────────────────────

class MissionSettings {
  const MissionSettings({
    this.name = 'Block A – Morning Run',
    this.altitude = 30,
    this.speed = 7.0,
    this.overlap = 75,
    this.lineSpacing = 4.0,
    this.sprayVolume = 3.5,
    this.batteryRequired = 2,
  });

  final String name;
  final int altitude; // metres
  final double speed; // m/s
  final int overlap; // %
  final double lineSpacing; // metres
  final double sprayVolume; // L/ha
  final int batteryRequired;

  MissionSettings copyWith({
    String? name,
    int? altitude,
    double? speed,
    int? overlap,
    double? lineSpacing,
    double? sprayVolume,
    int? batteryRequired,
  }) => MissionSettings(
    name: name ?? this.name,
    altitude: altitude ?? this.altitude,
    speed: speed ?? this.speed,
    overlap: overlap ?? this.overlap,
    lineSpacing: lineSpacing ?? this.lineSpacing,
    sprayVolume: sprayVolume ?? this.sprayVolume,
    batteryRequired: batteryRequired ?? this.batteryRequired,
  );
}
