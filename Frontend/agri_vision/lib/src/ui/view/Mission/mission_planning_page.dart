import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/mavlink/mavlink_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';

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
  /// Starts empty. A canned demo block used to be seeded here, which meant a
  /// pilot who had just signed up opened the app onto someone else's field
  /// hundreds of kilometres away and had to delete it before starting.
  List<WaypointModel> _waypoints = <WaypointModel>[];
  final List<List<WaypointModel>> _history = [];
  final List<List<WaypointModel>> _future = [];

  MissionSettings _settings = const MissionSettings();
  MapLayer _activeLayer = MapLayer.satellite;
  int? _selectedWaypointId;

  /// Where the operator is standing, once they've pressed the locate button.
  /// Stays null until then, so the map never shows a pin it didn't measure.
  LatLng? _myLocation;
  double? _myAccuracyM;
  bool _locating = false;

  /// The map opens on the pilot's own ground, but only asks once per session —
  /// re-prompting on every visit to the tab would be nagging.
  bool _autoLocateDone = false;

  /// Whether the "how to draw a block" card is still owed to this pilot.
  /// It is a first-run introduction, not a permanent empty-state banner: once
  /// shown it stays down through every later refresh and launch.
  bool _showEmptyHint = false;

  /// View mode by default so stray taps don't drop waypoints;
  /// the pencil FAB switches the editing tools on.
  bool _editMode = false;

  final MapController _mapController = MapController();

  late final TextEditingController _nameCtrl;

  /// Resolved once — dispose() runs while the element is being torn down, so
  /// it must not look the cubit up through the tree at that point.
  late final MavlinkCubit _mavlink = context.read<MavlinkCubit>();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _settings.name);
    _history.add(List.from(_waypoints));
    context.read<DroneCubit>().load();
    // Poll while this screen is open rather than reading the link once on
    // entry. A one-shot read goes stale the moment the backend restarts or the
    // vehicle stops reporting, and then the chip claims a link that is gone —
    // which is indistinguishable from a working one until Start does nothing.
    // Two seconds is plenty here; this screen only needs live-or-not.
    _mavlink.startPolling(interval: const Duration(seconds: 2));
    _claimFirstRunHint();
  }

  /// Shows the drawing hint to a pilot who has never seen it, and marks it
  /// spent in the same breath. Claiming it on first display rather than on
  /// dismissal is deliberate: this is an introduction to where the tools are,
  /// and an operator who already knows should not meet it again on every
  /// refresh, tab switch or launch.
  Future<void> _claimFirstRunHint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(StorageConstants.missionHintSeen) ?? false) return;
      await prefs.setBool(StorageConstants.missionHintSeen, true);
      if (!mounted) return;
      setState(() => _showEmptyHint = true);
    } catch (_) {
      // Storage unavailable — skip the hint rather than fail the screen.
    }
  }

  @override
  void dispose() {
    _mavlink.stopPolling();
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

  /// Lets the user pick a .kml file and replaces the current waypoints.
  ///
  /// The KML is first sent to the backend mission planner, which turns the
  /// field boundary into a full lawnmower survey path (using the current
  /// altitude/line-spacing settings). If the backend is unreachable we fall
  /// back to parsing the KML locally so the flow still works offline.
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

    final kmlText = utf8.decode(bytes, allowMalformed: true);

    // Preferred path: backend survey planner.
    try {
      final planned = await context.read<MissionsCubit>().planFromKml(
        kmlText: kmlText,
        settings: _settings,
      );
      if (!mounted) return;
      if (planned.isNotEmpty) {
        _pushHistory();
        setState(() {
          _waypoints = planned;
          _selectedWaypointId = null;
        });
        _fitToField();
        _showSnack(
          'Survey path planned: ${planned.length} waypoints from "${file.name}".',
        );
        return;
      }
    } catch (_) {
      // fall through to local parsing below
    }
    if (!mounted) return;

    final points = KmlParser.parse(kmlText);
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
          : 'Imported ${points.length} waypoints from "${file.name}" '
                '(offline — boundary only).',
    );
  }

  // ── Locate me ─────────────────────────────────────────────────────────────

  /// Drops a pin where the device is and centres the map on it.
  ///
  /// A second press re-reads the GPS rather than doing nothing, because the
  /// operator walking the field boundary is exactly who presses this twice.
  ///
  /// [announce] is off for the automatic fix taken when the screen opens: a
  /// snackbar nobody asked for, over a map they have just arrived at, is
  /// noise — and a refusal there is a choice, not an error to report.
  Future<void> _locateMe({bool announce = true}) async {
    if (_locating) return;
    setState(() => _locating = true);

    final result = await DeviceLocation.current();
    if (!mounted) return;
    setState(() => _locating = false);

    if (!result.isSuccess) {
      if (!announce) return;
      _showSnack(
        result.error ?? 'Could not determine your location.',
        action: result.canOpenSettings
            ? SnackBarAction(
                label: 'Settings',
                textColor: AppColors.primary3,
                onPressed: () => DeviceLocation.openSettings(
                  // "Services off" is the only case the location screen fixes;
                  // a denied permission lives in the app's own settings.
                  servicesOff: result.servicesDisabled,
                ),
              )
            : null,
      );
      return;
    }

    setState(() {
      _myLocation = result.position;
      _myAccuracyM = result.accuracyMetres;
    });

    // Zoom in only when arriving from further out — an operator already at
    // field zoom does not want the camera yanked in on every press.
    final zoom = math.max(_mapController.camera.zoom, 17.0);
    _mapController.move(result.position!, zoom);

    if (!announce) return;
    final accuracy = result.accuracyMetres;
    _showSnack(
      accuracy == null
          ? 'Your location pinned.'
          : 'Your location pinned (±${accuracy.round()} m).',
    );
  }

  /// Runs once the map is laid out (moving the camera before that throws).
  ///
  /// Only with an empty plan: someone who already has a block drawn wants to
  /// come back to it, not to be pulled to wherever they are standing.
  void _handleMapReady() {
    if (_autoLocateDone || _waypoints.isNotEmpty) return;
    _autoLocateDone = true;
    _locateMe(announce: false);
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
            // Rebuilt on every telemetry poll so the aircraft is visible on
            // the planning map too — an operator laying out a block wants to
            // see where the drone actually is relative to it, not only once
            // the mission is already running.
            Positioned.fill(
              child: BlocBuilder<MavlinkCubit, MavlinkState>(
                buildWhen: (before, after) =>
                    before.telemetry.position != after.telemetry.position ||
                    before.telemetry.headingDeg != after.telemetry.headingDeg ||
                    before.isLive != after.isLive,
                builder: (context, mavlink) => MissionMapView(
                  waypoints: _waypoints,
                  activeLayer: _activeLayer,
                  editable: _editMode,
                  selectedWaypointId: _selectedWaypointId,
                  mapController: _mapController,
                  dronePosition: mavlink.telemetry.position,
                  droneHeadingDeg: mavlink.telemetry.headingDeg,
                  // Position without heartbeats is a last-known fix, and the
                  // marker says so rather than implying the drone is hovering.
                  droneIsStale: !mavlink.isLive,
                  userLocation: _myLocation,
                  userAccuracyM: _myAccuracyM,
                  onMapReady: _handleMapReady,
                  onWaypointMoved: _moveWaypoint,
                  onWaypointDragStart: _handleWaypointDragStart,
                  onWaypointSelected: _selectWaypoint,
                  onMapTapped: _handleMapTap,
                ),
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
                onGpsLocate: _locateMe,
                gpsBusy: _locating,
                gpsActive: _myLocation != null,
                onImport: _importKml,
              ),
            ),

            // ── First-run drawing hint ─────────────────────────────────
            // A blank map with no polygon gives no clue where to start, and
            // the drawing tools are behind the pencil FAB. Shown once, to a
            // pilot who has not drawn anything yet.
            if (_showEmptyHint && _waypoints.isEmpty)
              Positioned(
                left: AppSpacing.xl,
                // Clear of the FAB column on the right (40px button + margin),
                // which the hint would otherwise sit on top of.
                right: 40 + AppSpacing.md * 2,
                bottom:
                    MediaQuery.of(context).size.height * 0.32 + AppSpacing.xxxl,
                child: _EmptyPlanHint(editMode: _editMode),
              ),

            // ── Compass widget (top-right) ─────────────────────────────
            Positioned(top: 64, right: AppSpacing.lg, child: _CompassWidget()),

            // ── Live drone status + flight-controller link ─────────────
            Positioned(
              top: 56,
              left: AppSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_DroneStatusStrip(), const MavlinkLinkChip()],
              ),
            ),

            // ── Collapsible bottom sheet ────────────────────────────────
            MissionBottomSheet(
              settings: _settings,
              waypointCount: _waypoints.length,
              areaHa: _areaHa,
              missionNameController: _nameCtrl,
              onSettingsChanged: (s) => setState(() => _settings = s),
              onSave: _saveMission,
              onStartMission: _startMission,
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.light100,
            ),
          ),
          action: action,
          backgroundColor: AppColors.dark700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      );
  }

  /// Persist the current plan to the backend so it shows up in mission
  /// history (Home + Reports) without flying it.
  Future<void> _saveMission() async {
    if (_waypoints.isEmpty) {
      _showSnack('Add waypoints before saving the mission.');
      return;
    }
    try {
      await context.read<MissionsCubit>().saveMission(
        name: _nameCtrl.text,
        waypoints: _waypoints,
        settings: _settings,
        areaHa: _areaHa,
      );
      if (mounted) _showSnack('Mission "${_nameCtrl.text}" saved');
    } catch (e) {
      if (mounted) {
        _showSnack(
          'Could not save mission: '
          '${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }

  /// Push the plan to the flight controller and start it.
  ///
  /// Returns true when the aircraft is actually flying the mission; false
  /// means "no link, or the vehicle refused" and the live screen falls back to
  /// its simulation. Refusals are surfaced rather than swallowed — a failed
  /// pre-arm check is exactly what the operator needs to read.
  Future<bool> _uploadAndLaunch(MissionMode mode, int? missionId) async {
    final mavlink = context.read<MavlinkCubit>();
    if (!mavlink.state.isLive) {
      // Never fall through to a simulation without saying so: an operator who
      // asked to fly and got an animation has no way to tell the difference
      // from the screen alone.
      _showSnack(
        'Vehicle stopped reporting before launch — running as a simulation.',
      );
      return false;
    }

    try {
      final items = await mavlink.uploadMission(
        waypoints: _waypoints,
        settings: _settings,
        name: _nameCtrl.text,
        missionId: missionId,
        speedMs: mode.speed,
      );
      await mavlink.startMission(missionId: missionId);
      if (mounted) {
        _showSnack('Vehicle launched — flying $items mission items.');
      }
      return true;
    } catch (e) {
      if (mounted) {
        _showSnack(
          'Vehicle did not launch: '
          '${e.toString().replaceFirst('Exception: ', '')} — '
          'continuing in simulation.',
        );
      }
      return false;
    }
  }

  /// Start flow: pick a flight mode, then open the live mission screen.
  ///
  /// With no vehicle reporting there is nothing to fly and nothing to show, so
  /// the operator is asked outright rather than dropped into a simulation that
  /// looks like a flight.
  Future<void> _startMission() async {
    if (_waypoints.length < 3) {
      _showSnack('Add at least 3 waypoints to define the survey block first.');
      return;
    }

    // Ask the server before deciding. Whether a vehicle is reporting is the
    // one fact this whole screen turns on, and it is worth a round trip rather
    // than trusting a snapshot that may predate a backend restart.
    await _mavlink.refresh();
    if (!mounted) return;

    if (!_mavlink.state.isLive) {
      final choice = await _askWithoutVehicle();
      if (!mounted || choice == null) return;
      if (choice == _NoVehicleChoice.connect) {
        await DroneConnectSheet.show(context);
        return;
      }
    }

    if (!mounted) return;
    MissionModeSheet.show(context, onSelect: _launchMission);
  }

  /// "Connect a drone" or "run it as a simulation" — never both silently.
  Future<_NoVehicleChoice?> _askWithoutVehicle() {
    return showDialog<_NoVehicleChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.light100,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text('No drone connected', style: AppTextStyle.textLgSemibold),
        content: Text(
          'No vehicle is reporting telemetry, so this mission cannot be flown '
          'or monitored for real. Connect a drone, or run it as a simulation '
          '— clearly marked SIM, with no live readings.',
          style: AppTextStyle.textMdRegular.copyWith(color: AppColors.dark500),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _NoVehicleChoice.simulate),
            child: Text(
              'Run Simulation',
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.light100,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, _NoVehicleChoice.connect),
            child: Text(
              'Connect Drone',
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchMission(MissionMode mode) async {
    // Record the flight server-side (planned → in_progress). A backend
    // failure must not ground the flight, so fall back to a local-only run.
    int? missionId;
    try {
      missionId = await context.read<MissionsCubit>().startMission(
        name: _nameCtrl.text,
        waypoints: _waypoints,
        settings: _settings,
        areaHa: _areaHa,
        mode: mode,
      );
    } catch (_) {
      missionId = null;
    }
    if (!mounted) return;

    // With a vehicle on the link, fly it for real: write the waypoints to the
    // flight controller and launch. Without one, the live screen simulates the
    // flight exactly as before.
    final flownByVehicle = await _uploadAndLaunch(mode, missionId);
    if (!mounted) return;

    final startedAt = DateTime.now();
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LiveMissionPage(
          missionName: _nameCtrl.text,
          waypoints: _waypoints,
          settings: _settings,
          mode: mode,
          activeLayer: _activeLayer,
          missionId: missionId,
          liveVehicle: flownByVehicle,
        ),
      ),
    );

    // Close the mission out with the actual time spent on the live screen.
    if (missionId != null) {
      final minutes =
          DateTime.now().difference(startedAt).inSeconds / 60.0;
      try {
        await context.read<MissionsCubit>().completeMission(
          missionId: missionId,
          status: result == null ? 'partial' : 'done',
          durationMin: double.parse(minutes.toStringAsFixed(1)),
        );
      } catch (_) {
        // history sync failed; the flight itself already happened
      }
    }
    if (result != null && mounted) _showSnack(result);
  }
}

/// What to do when Start is pressed with no vehicle on the link.
enum _NoVehicleChoice { connect, simulate }

// ── Empty-plan hint ────────────────────────────────────────────────────────

/// Shown over the map while no survey block exists, telling the operator which
/// control turns a blank map into one. The wording follows the edit toggle, so
/// it stops repeating a step already taken.
class _EmptyPlanHint extends StatelessWidget {
  const _EmptyPlanHint({required this.editMode});

  final bool editMode;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A28).withOpacity(0.9),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              editMode ? Icons.touch_app_outlined : Icons.polyline_outlined,
              size: 22,
              color: AppColors.primary3,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No survey block yet',
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              editMode
                  ? 'Tap the map to drop waypoints around your field, '
                        'or import a .kml boundary.'
                  : 'Tap the pencil to start drawing, or import a .kml '
                        'boundary of your field.',
              textAlign: TextAlign.center,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.light100.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
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
    return BlocBuilder<DroneCubit, DroneState>(
      builder: (context, state) {
        final drone = state.drone;
        final connected = drone?.isConnected ?? false;

        return GestureDetector(
          // Tapping the strip is how you fix what it is reporting.
          onTap: () => DroneConnectSheet.show(context),
          child: Container(
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
                _StatusDot(
                  color: connected
                      ? AppColors.themeSuccess
                      : AppColors.themeError,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  drone == null ? 'No drone  ' : '${drone.shortId}  ',
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.light100,
                  ),
                ),
                // Gauges only while something is feeding them; otherwise the
                // strip says what to do about it instead of showing numbers.
                if (!connected)
                  Text(
                    'Tap to connect',
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.primary3,
                    ),
                  )
                else ...[
                  _StatusItem(
                    icon: Icons.battery_5_bar,
                    value: drone!.batteryLabel,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusItem(
                    icon: Icons.water_drop_outlined,
                    value: drone.tankLabel,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusItem(icon: Icons.wifi, value: drone.signalLabel),
                ],
              ],
            ),
          ),
        );
      },
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
