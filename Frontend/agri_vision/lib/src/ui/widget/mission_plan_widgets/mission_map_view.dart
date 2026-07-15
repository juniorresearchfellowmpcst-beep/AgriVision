import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agri_vision/src/src.dart';

/// Real map for mission planning, built on flutter_map:
///  - Tile layers per [MapLayer] (Esri World Imagery, OpenTopoMap, hybrid)
///  - Tap anywhere on the map to drop a waypoint at that coordinate
///  - Tap a marker to select it, drag it to move it
///  - Survey block polygon + dashed flight path drawn from the waypoints
class MissionMapView extends StatefulWidget {
  const MissionMapView({
    super.key,
    required this.waypoints,
    required this.activeLayer,
    required this.onWaypointMoved,
    required this.onWaypointDragStart,
    required this.onWaypointSelected,
    required this.onMapTapped,
    this.selectedWaypointId,
    this.mapController,
  });

  final List<WaypointModel> waypoints;
  final MapLayer activeLayer;
  final void Function(int id, LatLng newPosition) onWaypointMoved;
  final void Function(int id) onWaypointDragStart;
  final void Function(int id) onWaypointSelected;
  final void Function(LatLng position) onMapTapped;
  final int? selectedWaypointId;
  final MapController? mapController;

  @override
  State<MissionMapView> createState() => _MissionMapViewState();
}

class _MissionMapViewState extends State<MissionMapView> {
  int? _draggingId;

  static const _userAgent = 'in.mpcst.agrivision';

  TileLayer get _baseTiles => switch (widget.activeLayer) {
    MapLayer.terrain => TileLayer(
      urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
      userAgentPackageName: _userAgent,
      maxNativeZoom: 17,
    ),
    // Satellite imagery is the standard basemap for agri mission planning;
    // NDVI uses the same imagery until a real NDVI tile service is wired in.
    _ => TileLayer(
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/'
          'World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: _userAgent,
      maxNativeZoom: 19,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final points = widget.waypoints.map((w) => w.position).toList();

    return FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: points.isNotEmpty
            ? _centroid(points)
            : const LatLng(23.1913, 77.4213),
        initialZoom: 17,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onTap: (_, latLng) => widget.onMapTapped(latLng),
      ),
      children: [
        _baseTiles,

        // Place labels on top of imagery for the hybrid layer.
        if (widget.activeLayer == MapLayer.hybrid)
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/'
                'Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: _userAgent,
            maxNativeZoom: 19,
          ),

        // Placeholder vegetation wash for the NDVI layer.
        if (widget.activeLayer == MapLayer.ndvi)
          IgnorePointer(
            child: Container(color: AppColors.primary.withOpacity(0.18)),
          ),

        // ── Survey block (coverage area) ──────────────────────────────
        if (points.length >= 3)
          PolygonLayer(
            polygons: [
              Polygon(
                points: points,
                color: AppColors.primary.withOpacity(0.15),
                borderColor: AppColors.primary.withOpacity(0.75),
                borderStrokeWidth: 2,
              ),
            ],
          ),

        // ── Dashed flight path ────────────────────────────────────────
        if (points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: const Color(0xFFE7B10A),
                strokeWidth: 2.5,
                pattern: StrokePattern.dashed(segments: const [10, 6]),
              ),
            ],
          ),

        // ── Waypoint markers ──────────────────────────────────────────
        MarkerLayer(
          markers: [
            for (final wp in widget.waypoints)
              Marker(
                point: wp.position,
                width: 36,
                height: 36,
                child: Builder(
                  builder: (markerContext) => GestureDetector(
                    onTap: () => widget.onWaypointSelected(wp.id),
                    onPanStart: (_) {
                      widget.onWaypointDragStart(wp.id);
                      setState(() => _draggingId = wp.id);
                    },
                    onPanUpdate: (d) =>
                        _dragWaypoint(markerContext, wp, d.delta),
                    onPanEnd: (_) => setState(() => _draggingId = null),
                    onPanCancel: () => setState(() => _draggingId = null),
                    child: _WaypointMarker(
                      id: wp.id,
                      isSelected: widget.selectedWaypointId == wp.id,
                      isDragging: _draggingId == wp.id,
                    ),
                  ),
                ),
              ),
          ],
        ),

        // ── Tile attribution (required by Esri / OpenTopoMap terms) ───
        const SimpleAttributionWidget(
          source: Text('Esri, OpenTopoMap', style: TextStyle(fontSize: 10)),
          backgroundColor: Colors.black38,
        ),
      ],
    );
  }

  /// Converts a marker's screen-space drag delta back to a coordinate.
  void _dragWaypoint(BuildContext markerContext, WaypointModel wp, Offset delta) {
    final camera = MapCamera.of(markerContext);
    final screen = camera.latLngToScreenOffset(wp.position);
    final moved = camera.screenOffsetToLatLng(screen + delta);
    widget.onWaypointMoved(wp.id, moved);
  }

  LatLng _centroid(List<LatLng> points) {
    var lat = 0.0, lng = 0.0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }
}

// ── Waypoint marker ────────────────────────────────────────────────────────

class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({
    required this.id,
    required this.isSelected,
    required this.isDragging,
  });

  final int id;
  final bool isSelected;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.light100,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.primary : const Color(0xFFE7B10A),
          width: isDragging ? 2.5 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDragging ? 0.35 : 0.20),
            blurRadius: isDragging ? 12 : 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$id',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isSelected ? AppColors.light100 : AppColors.dark900,
        ),
      ),
    );
  }
}
