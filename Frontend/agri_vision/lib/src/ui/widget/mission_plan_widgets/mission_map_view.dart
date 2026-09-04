import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agri_vision/src/src.dart';

/// Real map for mission planning, built on flutter_map:
///  - Tile layers per [MapLayer] (Esri World Imagery, OpenTopoMap, hybrid)
///  - Tap anywhere on the map to drop a waypoint at that coordinate
///  - Tap a marker to select it, drag it to move it (edit mode only)
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
    this.editable = true,
    this.selectedWaypointId,
    this.mapController,
    this.dronePosition,
    this.droneHeadingDeg,
    this.droneIsStale = false,
    this.userLocation,
    this.userAccuracyM,
    this.onMapReady,
  });

  final List<WaypointModel> waypoints;
  final MapLayer activeLayer;

  /// Edit mode: the map is pinned (no panning) and gestures design the
  /// polygon — tap to add a vertex, drag a marker to move it.
  /// View mode: markers are fixed and the whole map pans freely.
  final bool editable;
  final void Function(int id, LatLng newPosition) onWaypointMoved;
  final void Function(int id) onWaypointDragStart;
  final void Function(int id) onWaypointSelected;
  final void Function(LatLng position) onMapTapped;
  final int? selectedWaypointId;
  final MapController? mapController;

  /// Live drone location; when set, a drone marker is drawn on top.
  final LatLng? dronePosition;

  /// Compass heading in degrees (0 = north). Null leaves the marker
  /// unrotated — see [_DroneMarker] for why it does not guess.
  final double? droneHeadingDeg;

  /// True when the position is the last known rather than a current one.
  final bool droneIsStale;

  /// Where the operator is standing, once they've asked to be located.
  /// Null until then — the map never guesses at a position it wasn't given.
  final LatLng? userLocation;

  /// Reported horizontal accuracy of [userLocation] in metres, drawn as a
  /// translucent circle so a 40 m fix doesn't read as a 1 m one.
  final double? userAccuracyM;

  /// Fired once the map is laid out. Moving the camera before this point
  /// throws, so anything that wants to reposition the view waits for it.
  final VoidCallback? onMapReady;

  @override
  State<MissionMapView> createState() => _MissionMapViewState();
}

class _MissionMapViewState extends State<MissionMapView> {
  int? _draggingId;

  /// Movement accumulated since pointer-down, so a drag only starts past
  /// [kTouchSlop] — small jitters still register as a tap (select).
  Offset _pendingDrag = Offset.zero;

  static const _userAgent = 'in.mpcst.agrivision';

  void _handlePointerMove(
    BuildContext markerContext,
    WaypointModel wp,
    Offset delta,
  ) {
    if (_draggingId != wp.id) {
      _pendingDrag += delta;
      if (_pendingDrag.distance < kTouchSlop) return;
      widget.onWaypointDragStart(wp.id);
      setState(() => _draggingId = wp.id);
      _dragWaypoint(markerContext, wp, _pendingDrag);
      return;
    }
    _dragWaypoint(markerContext, wp, delta);
  }

  void _endDrag() {
    _pendingDrag = Offset.zero;
    if (_draggingId != null) setState(() => _draggingId = null);
  }

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
        // With no plan yet the camera has nothing to frame; it opens on a
        // neutral centre and [onMapReady] moves it to the pilot's own ground
        // as soon as a fix comes in.
        initialCenter: points.isNotEmpty
            ? _centroid(points)
            : const LatLng(23.1913, 77.4213),
        initialZoom: points.isNotEmpty ? 17 : 15,
        onMapReady: widget.onMapReady,
        // Edit mode locks the map in place so every gesture goes to the
        // polygon: tap adds a vertex, drag moves a marker (pinch/double-tap
        // zoom stay on for precision). View mode pans and zooms freely.
        interactionOptions: InteractionOptions(
          flags: widget.editable
              ? InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
              : InteractiveFlag.all & ~InteractiveFlag.rotate,
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

        // ── GPS accuracy halo around the operator ─────────────────────
        // Drawn under everything else so it never obscures the plan.
        if (widget.userLocation != null && (widget.userAccuracyM ?? 0) > 1)
          CircleLayer(
            circles: [
              CircleMarker(
                point: widget.userLocation!,
                radius: widget.userAccuracyM!,
                useRadiusInMeter: true,
                color: const Color(0xFF2E86DE).withOpacity(0.12),
                borderColor: const Color(0xFF2E86DE).withOpacity(0.45),
                borderStrokeWidth: 1,
              ),
            ],
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
                width: 44,
                height: 44,
                child: Builder(
                  // Raw pointer events instead of a pan GestureDetector:
                  // flutter_map's own recognizers win the gesture arena and
                  // swallow pans, but Listener bypasses the arena entirely,
                  // so marker drags always land.
                  builder: (markerContext) => Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: !widget.editable
                        ? null
                        : (_) => _pendingDrag = Offset.zero,
                    onPointerMove: !widget.editable
                        ? null
                        : (e) => _handlePointerMove(markerContext, wp, e.delta),
                    onPointerUp: !widget.editable
                        ? null
                        : (_) => _endDrag(),
                    onPointerCancel: !widget.editable
                        ? null
                        : (_) => _endDrag(),
                    child: GestureDetector(
                      onTap: () => widget.onWaypointSelected(wp.id),
                      child: Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: _WaypointMarker(
                            id: wp.id,
                            isSelected: widget.selectedWaypointId == wp.id,
                            isDragging: _draggingId == wp.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),

        // ── Live drone marker ─────────────────────────────────────────
        if (widget.dronePosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.dronePosition!,
                // Roomy enough for the pulse halo at full expansion.
                width: 60,
                height: 60,
                child: _DroneMarker(
                  headingDeg: widget.droneHeadingDeg,
                  isStale: widget.droneIsStale,
                ),
              ),
            ],
          ),

        // ── "You are here" pin ────────────────────────────────────────
        if (widget.userLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.userLocation!,
                width: 48,
                height: 50,
                // Sits above the point so the pin's tip lands on the fix
                // rather than its middle.
                alignment: Alignment.topCenter,
                child: const _UserLocationPin(),
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

// ── Drone marker ───────────────────────────────────────────────────────────

/// The aircraft's live position on the map.
///
/// Two deliberate choices:
///
///  * It only points somewhere when the vehicle actually reported a heading.
///    With no heading it falls back to a plain drone glyph rather than an
///    arrow aimed at north, because an arrow is read as "this is the way it is
///    facing" and being wrong about that is worse than not saying.
///  * The halo pulses only while telemetry is arriving. A frozen marker is
///    then visibly frozen, instead of looking like a hovering aircraft.
class _DroneMarker extends StatefulWidget {
  const _DroneMarker({this.headingDeg, this.isStale = false});

  /// Compass heading in degrees (0 = north), or null if unknown.
  final double? headingDeg;

  /// True when heartbeats have stopped — the position shown is the last known.
  final bool isStale;

  @override
  State<_DroneMarker> createState() => _DroneMarkerState();
}

class _DroneMarkerState extends State<_DroneMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void didUpdateWidget(covariant _DroneMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStale && _pulse.isAnimating) {
      _pulse.stop();
    } else if (!widget.isStale && !_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isStale
        ? AppColors.light100.withOpacity(0.55)
        : const Color(0xFFE7B10A);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Expanding halo — the "it is alive and here" cue on a busy map.
        if (!widget.isStale)
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              return Container(
                width: 22 + 34 * t,
                height: 22 + 34 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFE7B10A).withOpacity(1 - t),
                    width: 2,
                  ),
                ),
              );
            },
          ),

        // Body
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A28),
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isStale
                  ? AppColors.light100.withOpacity(0.5)
                  : AppColors.light100,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.headingDeg == null
              // No heading reported — say "drone", not "this way".
              ? DroneIcon(size: 17, color: accent)
              : Transform.rotate(
                  // MAVLink heading is degrees clockwise from north, which is
                  // exactly what Transform.rotate wants once converted, and
                  // the navigation glyph already points north at rest.
                  angle: widget.headingDeg! * math.pi / 180.0,
                  child: Icon(
                    Icons.navigation_rounded,
                    size: 19,
                    color: accent,
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Operator location pin ──────────────────────────────────────────────────

/// "You are here" — deliberately a different shape and colour from both the
/// numbered waypoints and the aircraft, so a glance never confuses the person
/// holding the phone with the drone in the air.
class _UserLocationPin extends StatelessWidget {
  const _UserLocationPin();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // White body behind the blue one: on satellite imagery a bare blue pin
        // disappears into shadow and water.
        Icon(
          Icons.location_on,
          size: 46,
          color: Colors.white,
          shadows: [
            Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        Icon(Icons.location_on, size: 36, color: Color(0xFF2E86DE)),
      ],
    );
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
        color: isSelected ? AppColors.primary : AppColors.surface,
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
