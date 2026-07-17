import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agri_vision/src/src.dart';

/// Mission Planning screen.
///
/// Architecture:
///   - Full-screen [MissionMapView]     → map + flight path painter + draggable markers
///   - [MissionTopBar]                  → field info + layer picker (floating on map)
///   - [MissionFabCluster]             → add/undo/redo/delete/GPS/center/import FABs
///   - [MissionBottomSheet]            → draggable sheet with name, stats, settings, CTAs
///   - [LayerSelectorSheet]            → modal bottom sheet for switching map layers
///
/// All state is kept locally here. In production wire to a MissionBloc
/// following the same pattern used in HomeCubit / AlertsCubit.
class MissionPlanningPage extends StatefulWidget {
  const MissionPlanningPage({super.key});

  @override
  State<MissionPlanningPage> createState() => _MissionPlanningPageState();
}

class _MissionPlanningPageState extends State<MissionPlanningPage> {
  List<WaypointModel> _waypoints = WaypointModel.defaultWaypoints();
  final List<List<WaypointModel>> _history = [];
  final List<List<WaypointModel>> _future = [];

  MissionSettings _settings = const MissionSettings();
  MapLayer _activeLayer = MapLayer.satellite;
  int? _selectedWaypointId;

  /// View mode by default so stray taps don't drop waypoints;
  /// the pencil FAB switches the editing tools on.
  bool _editMode = false;

  final MapController _mapController = MapController();

  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _settings.name);
    _history.add(List.from(_waypoints));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── History management ────────────────────────────────────────────────────

  void _pushHistory() {
    _history.add(List.from(_waypoints));
    _future.clear();
  }

  void _undo() {
    if (_history.length <= 1) return;
    setState(() {
      _future.add(List.from(_waypoints));
      _waypoints = List.from(_history.removeLast());
    });
  }

  void _redo() {
    if (_future.isEmpty) return;
    setState(() {
      _history.add(List.from(_waypoints));
      _waypoints = List.from(_future.removeLast());
    });
  }

  // ── Waypoint actions ──────────────────────────────────────────────────────

  void _addWaypointAt(LatLng position) {
    _pushHistory();
    final newId = _waypoints.isEmpty
        ? 1
        : _waypoints.map((w) => w.id).reduce((a, b) => a > b ? a : b) + 1;
    setState(() {
      _waypoints = [..._waypoints, WaypointModel(id: newId, position: position)];
    });
  }

  /// Tap on empty map: deselect if a waypoint is selected, otherwise
  /// (in edit mode) drop a new waypoint at the tapped coordinate.
  void _handleMapTap(LatLng position) {
    if (_selectedWaypointId != null) {
      setState(() => _selectedWaypointId = null);
      return;
    }
    if (!_editMode) return;
    _addWaypointAt(position);
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
      _selectedWaypointId = null;
    });
    _showSnack(
      _editMode
          ? 'Edit mode: map locked — tap to add points, drag markers to adjust'
          : 'Editing finished — map unlocked',
    );
  }

  // ── KML import ────────────────────────────────────────────────────────────

  /// Lets the user pick a .kml file and replaces the current waypoints with
  /// its coordinates (undoable). Bytes are requested up-front so the flow
  /// also works on web, mirroring [MediaPicker].
  Future<void> _importKml() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (!mounted) return;
    if (bytes == null) {
      _showSnack('Could not read "${file.name}".');
      return;
    }

    final points = KmlParser.parse(utf8.decode(bytes, allowMalformed: true));
    if (points.isEmpty) {
      _showSnack(
        'No coordinates found in "${file.name}". '
        'Export an uncompressed .kml (not .kmz).',
      );
      return;
    }

    _pushHistory();
    setState(() {
      _waypoints = [
        for (var i = 0; i < points.length; i++)
          WaypointModel(id: i + 1, position: points[i]),
      ];
      _selectedWaypointId = null;
    });
    _fitToField();
    _showSnack(
      points.length < 3
          ? 'Imported ${points.length} point(s) from "${file.name}" — '
                'tap the map to add more (a polygon needs at least 3)'
          : 'Imported ${points.length} waypoints from "${file.name}".',
    );
  }

  void _moveWaypoint(int id, LatLng newPosition) {
    setState(() {
      _waypoints = _waypoints
          .map((w) => w.id == id ? w.copyWith(position: newPosition) : w)
          .toList();
    });
  }

  /// One history entry per drag gesture, captured before the first move.
  void _handleWaypointDragStart(int id) => _pushHistory();

  void _deleteSelected() {
    if (_selectedWaypointId == null) return;
    _pushHistory();
    setState(() {
      _waypoints = _waypoints
          .where((w) => w.id != _selectedWaypointId)
          .toList();
      _selectedWaypointId = null;
    });
  }

  void _selectWaypoint(int id) {
    setState(() {
      _selectedWaypointId = _selectedWaypointId == id ? null : id;
    });
  }

  // ── Derived values ────────────────────────────────────────────────────────

  /// Survey block area in hectares (shoelace formula on an
  /// equirectangular projection — accurate at field scale).
  double get _areaHa {
    if (_waypoints.length < 3) return 0;
    const earthRadius = 6378137.0;
    final points = _waypoints.map((w) => w.position).toList();
    final latRef = points.first.latitudeInRad;

    double sum = 0;
    for (int i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final ax = a.longitudeInRad * earthRadius * math.cos(latRef);
      final ay = a.latitudeInRad * earthRadius;
      final bx = b.longitudeInRad * earthRadius * math.cos(latRef);
      final by = b.latitudeInRad * earthRadius;
      sum += ax * by - bx * ay;
    }
    return sum.abs() / 2 / 10000;
  }

  void _fitToField() {
    if (_waypoints.isEmpty) return;
    final coords = _waypoints.map((w) => w.position).toList();

    // Zero-area bounds (a single point, or identical points) would make
    // fitCamera compute an infinite zoom and assert — center instead.
    final bounds = LatLngBounds.fromPoints(coords);
    if (bounds.southWest == bounds.northEast) {
      _mapController.move(coords.first, 17);
      return;
    }

    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: coords,
        padding: const EdgeInsets.fromLTRB(48, 140, 48, 300),
        // Tiny fields would otherwise fit past the imagery's native zoom.
        maxZoom: 19,
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A3A28),
      // no default AppBar — we use a floating top bar
      body: SafeArea(
        child: Stack(
          children: [
            // ── Full-screen map ─────────────────────────────────────────
            Positioned.fill(
              child: MissionMapView(
                waypoints: _waypoints,
                activeLayer: _activeLayer,
                editable: _editMode,
                selectedWaypointId: _selectedWaypointId,
                mapController: _mapController,
                onWaypointMoved: _moveWaypoint,
                onWaypointDragStart: _handleWaypointDragStart,
                onWaypointSelected: _selectWaypoint,
                onMapTapped: _handleMapTap,
              ),
            ),

            // ── Floating top bar ────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MissionTopBar(
                fieldName: 'Block A',
                areHa: double.parse(_areaHa.toStringAsFixed(1)),
                waypointCount: _waypoints.length,
                activeLayer: _activeLayer,
                onBack: () => Navigator.of(context).maybePop(),
                onLayerTap: () => LayerSelectorSheet.show(
                  context,
                  activeLayer: _activeLayer,
                  onSelect: (l) => setState(() => _activeLayer = l),
                ),
              ),
            ),

            // ── FAB cluster (right side) ────────────────────────────────
            Positioned(
              right: AppSpacing.md,
              bottom: MediaQuery.of(context).size.height * 0.32 + AppSpacing.xl,
              child: MissionFabCluster(
                editMode: _editMode,
                canUndo: _history.length > 1,
                canRedo: _future.isNotEmpty,
                canDelete: _selectedWaypointId != null,
                onToggleEdit: _toggleEditMode,
                onAddWaypoint: () =>
                    _addWaypointAt(_mapController.camera.center),
                onUndo: _undo,
                onRedo: _redo,
                onDelete: _deleteSelected,
                onCenter: _fitToField,
                onGpsLocate: () {
                  // TODO: center on device GPS position (needs geolocator)
                },
                onImport: _importKml,
              ),
            ),

            // ── Compass widget (top-right) ─────────────────────────────
            Positioned(top: 64, right: AppSpacing.lg, child: _CompassWidget()),

            // ── Live drone status strip (below top bar) ────────────────
            Positioned(
              top: 56,
              left: AppSpacing.lg,
              child: _DroneStatusStrip(),
            ),

            // ── Collapsible bottom sheet ────────────────────────────────
            MissionBottomSheet(
              settings: _settings,
              waypointCount: _waypoints.length,
              missionNameController: _nameCtrl,
              onSettingsChanged: (s) => setState(() => _settings = s),
              onSave: () => _showSnack('Mission "${_nameCtrl.text}" saved'),
              onStartMission: _startMission,
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyle.textSmRegular.copyWith(color: AppColors.light100),
        ),
        backgroundColor: AppColors.dark700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  /// Start flow: pick a flight mode, then open the live mission screen.
  void _startMission() {
    if (_waypoints.length < 3) {
      _showSnack('Add at least 3 waypoints to define the survey block first.');
      return;
    }
    MissionModeSheet.show(context, onSelect: _launchMission);
  }

  Future<void> _launchMission(MissionMode mode) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LiveMissionPage(
          missionName: _nameCtrl.text,
          waypoints: _waypoints,
          settings: _settings,
          mode: mode,
          activeLayer: _activeLayer,
        ),
      ),
    );
    if (result != null && mounted) _showSnack(result);
  }
}

// ── Compass widget ─────────────────────────────────────────────────────────

class _CompassWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A28).withOpacity(0.88),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.navigation_rounded, size: 14, color: AppColors.themeError),
          Text(
            'N',
            style: AppTextStyle.textXsBold.copyWith(
              color: AppColors.light100,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drone status strip ────────────────────────────────────────────────────

class _DroneStatusStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A28).withOpacity(0.88),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: AppColors.themeSuccess),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'GCS-04  ',
            style: AppTextStyle.textXsSemibold.copyWith(
              color: AppColors.light100,
            ),
          ),
          _StatusItem(icon: Icons.battery_5_bar, value: '84%'),
          const SizedBox(width: AppSpacing.sm),
          _StatusItem(icon: Icons.water_drop_outlined, value: '63%'),
          const SizedBox(width: AppSpacing.sm),
          _StatusItem(icon: Icons.wifi, value: '−68 dBm'),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.primary3),
        const SizedBox(width: 2),
        Text(
          value,
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.primary3),
        ),
      ],
    );
  }
}
