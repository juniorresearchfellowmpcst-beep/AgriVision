import 'package:flutter/material.dart';
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

  void _addWaypointAtCenter() {
    _pushHistory();
    final newId = _waypoints.isEmpty
        ? 1
        : _waypoints.map((w) => w.id).reduce((a, b) => a > b ? a : b) + 1;
    setState(() {
      _waypoints = [
        ..._waypoints,
        WaypointModel(id: newId, position: const Offset(0.5, 0.45)),
      ];
    });
  }

  void _moveWaypoint(int id, Offset newFraction) {
    setState(() {
      _waypoints = _waypoints
          .map((w) => w.id == id ? w.copyWith(position: newFraction) : w)
          .toList();
    });
  }

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
                selectedWaypointId: _selectedWaypointId,
                onWaypointMoved: _moveWaypoint,
                onWaypointSelected: _selectWaypoint,
                onMapTapped: (_) {
                  // deselect on tap outside markers
                  if (_selectedWaypointId != null) {
                    setState(() => _selectedWaypointId = null);
                  }
                },
              ),
            ),

            // ── Floating top bar ────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MissionTopBar(
                fieldName: 'Block A',
                areHa: 4.2,
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
                canUndo: _history.length > 1,
                canRedo: _future.isNotEmpty,
                canDelete: _selectedWaypointId != null,
                onAddWaypoint: _addWaypointAtCenter,
                onUndo: _undo,
                onRedo: _redo,
                onDelete: _deleteSelected,
                onCenter: () {
                  // TODO: animate map camera to field bounds
                },
                onGpsLocate: () {
                  // TODO: center on device GPS position
                },
                onImport: () {
                  // TODO: open file picker for KML/GeoJSON
                  _showImportSnackBar(context);
                },
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
              onSave: () => _showSaveSnackBar(context),
              onStartMission: () => _showStartDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSaveSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Mission "${_nameCtrl.text}" saved',
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

  void _showImportSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Import KML / GeoJSON — connect file picker',
          style: AppTextStyle.textSmRegular.copyWith(color: AppColors.light100),
        ),
        backgroundColor: AppColors.dark700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showStartDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.light100,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text('Start Mission?', style: AppTextStyle.textLgSemibold),
        content: Text(
          'Launch "${_nameCtrl.text}" with ${_waypoints.length} waypoints over '
          '4.2 ha at ${_settings.altitude} m altitude?',
          style: AppTextStyle.textMdRegular.copyWith(color: AppColors.dark500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
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
            onPressed: () {
              Navigator.pop(context);
              // TODO: dispatch MissionBloc.StartMission event
            },
            child: Text(
              'Launch',
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
          ),
        ],
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
