import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:agri_vision/src/src.dart';

/// Live mission screen shown after launch:
///  - full-screen map with the flight path and a moving drone marker
///  - "LIVE" top bar with the mission name
///  - telemetry cards (altitude / speed / battery / tank)
///  - Return Home and Emergency Land actions
///
/// Telemetry is simulated locally until real drone MAVLink/GCS data is
/// wired in; the drone flies the waypoint path at the mode's cruise speed.
class LiveMissionPage extends StatefulWidget {
  const LiveMissionPage({
    super.key,
    required this.missionName,
    required this.waypoints,
    required this.settings,
    required this.mode,
    this.activeLayer = MapLayer.satellite,
  });

  final String missionName;
  final List<WaypointModel> waypoints;
  final MissionSettings settings;
  final MissionMode mode;
  final MapLayer activeLayer;

  @override
  State<LiveMissionPage> createState() => _LiveMissionPageState();
}

class _LiveMissionPageState extends State<LiveMissionPage> {
  static const _tick = Duration(milliseconds: 500);
  static const _distance = Distance();

  final MapController _mapController = MapController();

  Timer? _timer;
  double _flownM = 0; // metres travelled along the path
  double _elapsedS = 0;
  double _battery = 100;
  double _tank = 100;

  late final List<LatLng> _path = [
    for (final w in widget.waypoints) w.position,
    // close the loop so the drone returns towards waypoint 1
    if (widget.waypoints.length > 2) widget.waypoints.first.position,
  ];

  late final double _totalM = _pathLength(_path);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, _onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToPath());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Simulation ────────────────────────────────────────────────────────────

  void _onTick(Timer _) {
    if (!mounted) return;
    setState(() {
      _elapsedS += _tick.inMilliseconds / 1000;
      if (_totalM > 0) {
        _flownM = (_flownM + widget.mode.speed * _tick.inMilliseconds / 1000) %
            _totalM;
      }
      _battery = (_battery - 0.02).clamp(0, 100);
      _tank = (_tank - 0.03).clamp(0, 100);
    });
  }

  double _pathLength(List<LatLng> path) {
    var total = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      total += _distance.as(LengthUnit.Meter, path[i], path[i + 1]);
    }
    return total;
  }

  /// Current drone location: [_flownM] metres along the waypoint path.
  LatLng? get _dronePosition {
    if (_path.isEmpty) return null;
    if (_path.length == 1 || _totalM == 0) return _path.first;

    var remaining = _flownM;
    for (var i = 0; i < _path.length - 1; i++) {
      final seg = _distance.as(LengthUnit.Meter, _path[i], _path[i + 1]);
      if (remaining <= seg && seg > 0) {
        final t = remaining / seg;
        return LatLng(
          _path[i].latitude + (_path[i + 1].latitude - _path[i].latitude) * t,
          _path[i].longitude +
              (_path[i + 1].longitude - _path[i].longitude) * t,
        );
      }
      remaining -= seg;
    }
    return _path.last;
  }

  /// Small oscillation so the live numbers feel alive.
  double get _altitude =>
      widget.settings.altitude + math.sin(_elapsedS / 3) * 1.5;

  double get _speed =>
      math.max(0, widget.mode.speed + math.sin(_elapsedS / 2) * 0.4);

  void _fitToPath() {
    if (_path.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(_path);
    if (bounds.southWest == bounds.northEast) {
      _mapController.move(_path.first, 17);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _path,
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 280),
        maxZoom: 19,
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _confirmAndExit({
    required String title,
    required String message,
    required String action,
    required Color actionColor,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.light100,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(title, style: AppTextStyle.textLgSemibold),
        content: Text(
          message,
          style: AppTextStyle.textMdRegular.copyWith(color: AppColors.dark500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: actionColor,
              foregroundColor: AppColors.light100,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              action,
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _timer?.cancel();
    Navigator.of(context).pop('$action initiated');
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A3A28),
      body: SafeArea(
        child: Stack(
          children: [
            // ── Map with path + drone ───────────────────────────────────
            Positioned.fill(
              child: MissionMapView(
                waypoints: widget.waypoints,
                activeLayer: widget.activeLayer,
                editable: false,
                mapController: _mapController,
                dronePosition: _dronePosition,
                onWaypointMoved: (_, __) {},
                onWaypointDragStart: (_) {},
                onWaypointSelected: (_) {},
                onMapTapped: (_) {},
              ),
            ),

            // ── LIVE top bar ────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _LiveTopBar(
                missionName: widget.missionName,
                onBack: () => _confirmAndExit(
                  title: 'Abort Mission?',
                  message:
                      'The drone will stop the survey and hover in place.',
                  action: 'Abort',
                  actionColor: AppColors.themeError,
                ),
              ),
            ),

            // ── Telemetry + actions panel ───────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _LiveBottomPanel(
                altitude: _altitude,
                speed: _speed,
                battery: _battery,
                tank: _tank,
                onReturnHome: () => _confirmAndExit(
                  title: 'Return Home?',
                  message:
                      'The drone will pause the mission and fly back to the '
                      'launch point.',
                  action: 'Return Home',
                  actionColor: const Color(0xFFF59E0B),
                ),
                onEmergencyLand: () => _confirmAndExit(
                  title: 'Emergency Land?',
                  message:
                      'The drone will descend and land immediately at its '
                      'current position.',
                  action: 'Emergency Land',
                  actionColor: AppColors.themeError,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top bar ────────────────────────────────────────────────────────────────

class _LiveTopBar extends StatelessWidget {
  const _LiveTopBar({required this.missionName, required this.onBack});

  final String missionName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A28).withOpacity(0.92),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: AppColors.light100,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // LIVE pill with mission name
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A28).withOpacity(0.92),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const _BlinkingDot(),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'LIVE',
                    style: AppTextStyle.textXsBold.copyWith(
                      color: AppColors.light100,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      missionName,
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.light100.withOpacity(0.85),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // recording indicator
          Container(
            width: 44,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A28).withOpacity(0.92),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.radio_button_checked,
              size: 18,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFE53935),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Bottom panel ───────────────────────────────────────────────────────────

class _LiveBottomPanel extends StatelessWidget {
  const _LiveBottomPanel({
    required this.altitude,
    required this.speed,
    required this.battery,
    required this.tank,
    required this.onReturnHome,
    required this.onEmergencyLand,
  });

  final double altitude;
  final double speed;
  final double battery;
  final double tank;
  final VoidCallback onReturnHome;
  final VoidCallback onEmergencyLand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _TelemetryCard(
                  icon: Icons.height_rounded,
                  value: altitude.toStringAsFixed(0),
                  unit: 'm',
                  label: 'Altitude',
                ),
                const SizedBox(width: AppSpacing.sm),
                _TelemetryCard(
                  icon: Icons.speed_rounded,
                  value: speed.toStringAsFixed(1),
                  unit: 'm/s',
                  label: 'Speed',
                ),
                const SizedBox(width: AppSpacing.sm),
                _TelemetryCard(
                  icon: Icons.battery_5_bar_rounded,
                  value: battery.toStringAsFixed(0),
                  unit: '%',
                  label: 'Battery',
                ),
                const SizedBox(width: AppSpacing.sm),
                _TelemetryCard(
                  icon: Icons.water_drop_outlined,
                  value: tank.toStringAsFixed(0),
                  unit: '%',
                  label: 'Tank',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Return Home',
                  icon: Icons.refresh_rounded,
                  color: const Color(0xFFF59E0B),
                  onTap: onReturnHome,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ActionButton(
                  label: 'Emergency Land',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.themeError,
                  onTap: onEmergencyLand,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A28),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: AppColors.primary3),
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            TextSpan(
              text: value,
              style: AppTextStyle.textMdBold.copyWith(
                color: AppColors.light100,
              ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.light100.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.light100.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.light100),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: AppTextStyle.textSmSemibold.copyWith(
                  color: AppColors.light100,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
