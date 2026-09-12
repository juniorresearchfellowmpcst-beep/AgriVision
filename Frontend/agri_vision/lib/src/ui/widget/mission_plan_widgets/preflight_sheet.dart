import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/mavlink/mavlink_cubit.dart';

/// The last screen before the motors spin.
///
/// Until this existed, choosing a flight profile armed the aircraft and took
/// off — one tap, from a sheet that was only meant to pick a speed. On a
/// simulator that is a convenience; on a drone standing in a field with people
/// around it, it is the wrong default.
///
/// Two halves, because two different things can be wrong:
///
///  * what the **aircraft** says about itself — GPS fix, battery, link,
///    autopilot — read from the backend's own pre-flight check, the same one
///    the launch is about to run, so nothing here can disagree with it;
///  * what only the **person standing in the field** can answer, asked as
///    three plain confirmations. The app cannot see who is downwind.
class PreflightSheet extends StatefulWidget {
  const PreflightSheet({
    super.key,
    required this.missionName,
    required this.waypoints,
    required this.altitudeM,
    required this.speedMs,
    this.spray = false,
  });

  final String missionName;
  final int waypoints;
  final int altitudeM;
  final double speedMs;

  /// A spray run opens a valve as well as flying, and says so.
  final bool spray;

  /// True when the operator confirmed and the aircraft may be launched.
  static Future<bool> show(
    BuildContext context, {
    required String missionName,
    required int waypoints,
    required int altitudeM,
    required double speedMs,
    bool spray = false,
  }) async {
    final launched = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<MavlinkCubit>(),
        child: PreflightSheet(
          missionName: missionName,
          waypoints: waypoints,
          altitudeM: altitudeM,
          speedMs: speedMs,
          spray: spray,
        ),
      ),
    );
    return launched ?? false;
  }

  @override
  State<PreflightSheet> createState() => _PreflightSheetState();
}

class _PreflightSheetState extends State<PreflightSheet> {
  late final MavlinkCubit _mavlink = context.read<MavlinkCubit>();

  Timer? _recheck;
  PreflightReport? _report;
  String _error = '';
  bool _fieldClear = false;
  bool _transmitter = false;
  bool _aircraftReady = false;

  @override
  void initState() {
    super.initState();
    _check();
    // A GPS fix arrives while the operator is reading this, so the answer is
    // re-asked rather than frozen at the moment the sheet opened.
    _recheck = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final report = await _mavlink.preflight();
      if (!mounted) return;
      setState(() {
        _report = report;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  bool get _confirmed => _fieldClear && _transmitter && _aircraftReady;
  bool get _vehicleReady => _report?.ready == true;

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final telemetry = report?.link.telemetry;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.light700,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text('Before take-off', style: AppTextStyle.textXlBold),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.spray
                        ? 'The aircraft will take off by itself, fly the plan '
                              'and open the spray valve over the marked zones.'
                        : 'The aircraft will take off by itself and fly the '
                              'plan to the end, then return home.',
                    style: AppTextStyle.textSmRegular.copyWith(
                      color: AppColors.dark300,
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),
                  _Panel(
                    title: 'The flight',
                    child: Column(
                      children: [
                        _Line(
                          label: 'Mission',
                          value: widget.missionName.isEmpty
                              ? 'Untitled'
                              : widget.missionName,
                        ),
                        _Line(
                          label: 'Waypoints',
                          value: '${widget.waypoints}',
                        ),
                        _Line(label: 'Altitude', value: '${widget.altitudeM} m'),
                        _Line(
                          label: 'Speed',
                          value: '${widget.speedMs.toStringAsFixed(1)} m/s',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),
                  _Panel(
                    title: 'What the aircraft reports',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (report == null && _error.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (_error.isNotEmpty)
                          _Check(ok: false, text: _error),
                        if (report != null) ...[
                          _Check(
                            ok: report.link.alive,
                            text: report.link.alive
                                ? 'Telemetry is flowing'
                                : 'No telemetry from the vehicle',
                          ),
                          _Check(
                            ok: (telemetry?.gpsFix ?? 0) >= 3,
                            text: telemetry?.gpsFix == null
                                ? 'No GPS reading yet'
                                : '3-D GPS fix'
                                      '${telemetry?.satellites != null ? ' · ${telemetry!.satellites} satellites' : ''}',
                          ),
                          _Check(
                            ok: (telemetry?.batteryPercent ?? 100) >= 30,
                            text: telemetry?.batteryPercent == null
                                ? 'Battery level not reported'
                                : 'Battery ${telemetry!.batteryPercent}%',
                          ),
                          _Check(
                            ok: report.link.flightControlSupported,
                            text: report.link.autopilot == null
                                ? 'Autopilot unknown'
                                : 'Autopilot: ${report.link.autopilot}'
                                      '${report.link.vehicleType != null ? ' · ${report.link.vehicleType}' : ''}',
                          ),
                          for (final problem in report.problems)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.xs),
                              child: Text(
                                problem,
                                style: AppTextStyle.textXsRegular.copyWith(
                                  color: AppColors.themeError,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),
                  _Panel(
                    title: 'What only you can check',
                    child: Column(
                      children: [
                        _Confirm(
                          value: _fieldClear,
                          onChanged: (v) => setState(() => _fieldClear = v),
                          text: widget.spray
                              ? 'The field is clear of people and animals, and '
                                    'nobody is downwind of it'
                              : 'The field is clear of people and animals',
                        ),
                        _Confirm(
                          value: _transmitter,
                          onChanged: (v) => setState(() => _transmitter = v),
                          text:
                              'The transmitter is switched on and within reach, '
                              'so a pilot can take over',
                        ),
                        _Confirm(
                          value: _aircraftReady,
                          onChanged: (v) => setState(() => _aircraftReady = v),
                          text:
                              'Propellers, battery and payload are secure, and '
                              'the take-off area is clear',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Not yet'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _vehicleReady && _confirmed
                            ? () => Navigator.of(context).pop(true)
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.themeError,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        icon: const Icon(Icons.flight_takeoff, size: 18),
                        label: const Text('Arm & take off'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyle.textSmSemibold),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyle.textSmSemibold.copyWith(
                color: AppColors.dark700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 16,
            color: ok ? AppColors.themeSuccess : AppColors.themeError,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.value,
    required this.onChanged,
    required this.text,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String text;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppColors.primary,
      dense: true,
      title: Text(text, style: AppTextStyle.textSmMedium),
    );
  }
}
