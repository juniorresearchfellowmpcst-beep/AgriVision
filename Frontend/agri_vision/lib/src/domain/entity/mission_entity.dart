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
