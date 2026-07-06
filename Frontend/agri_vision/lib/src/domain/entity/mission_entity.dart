import 'package:flutter/material.dart';

// ── Waypoint ───────────────────────────────────────────────────────────────

class WaypointModel {
  const WaypointModel({
    required this.id,
    required this.position, // fractional (0–1) x,y on map canvas
    this.isSelected = false,
  });

  final int id;
  final Offset position;
  final bool isSelected;

  WaypointModel copyWith({Offset? position, bool? isSelected}) => WaypointModel(
    id: id,
    position: position ?? this.position,
    isSelected: isSelected ?? this.isSelected,
  );

  static List<WaypointModel> defaultWaypoints() => [
    const WaypointModel(id: 1, position: Offset(0.08, 0.18)),
    const WaypointModel(id: 2, position: Offset(0.28, 0.10)),
    const WaypointModel(id: 3, position: Offset(0.72, 0.10)),
    const WaypointModel(id: 4, position: Offset(0.92, 0.18)),
    const WaypointModel(id: 5, position: Offset(0.92, 0.40)),
    const WaypointModel(id: 6, position: Offset(0.72, 0.48)),
    const WaypointModel(id: 7, position: Offset(0.80, 0.62)),
    const WaypointModel(id: 8, position: Offset(0.32, 0.62)),
    const WaypointModel(id: 9, position: Offset(0.08, 0.50)),
    const WaypointModel(id: 10, position: Offset(0.08, 0.35)),
  ];
}

// ── Mission layer enum ─────────────────────────────────────────────────────

enum MapLayer { satellite, terrain, ndvi, hybrid }

extension MapLayerX on MapLayer {
  String get label => switch (this) {
    MapLayer.satellite => 'Satellite',
    MapLayer.terrain => 'Terrain',
    MapLayer.ndvi => 'NDVI',
    MapLayer.hybrid => 'Hybrid',
  };

  IconData get icon => switch (this) {
    MapLayer.satellite => Icons.satellite_alt,
    MapLayer.terrain => Icons.landscape_outlined,
    MapLayer.ndvi => Icons.grass_outlined,
    MapLayer.hybrid => Icons.layers_outlined,
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
