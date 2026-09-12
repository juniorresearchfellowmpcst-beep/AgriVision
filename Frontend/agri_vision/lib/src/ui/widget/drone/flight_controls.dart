import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/mavlink/mavlink_cubit.dart';

/// The endpoints people actually connect to, roughly in the order a field
/// needs them. Shared by both connect sheets, so a preset added for real
/// hardware turns up in whichever one the operator happens to open.
class MavlinkEndpoint {
  const MavlinkEndpoint(this.label, this.url, {this.baud});

  final String label;
  final String url;

  /// Serial links only — the speed of the radio on the other end.
  final int? baud;
}

const mavlinkPresets = <MavlinkEndpoint>[
  MavlinkEndpoint('Telemetry radio · Windows', 'COM5', baud: 57600),
  MavlinkEndpoint('Telemetry radio · Linux', '/dev/ttyUSB0', baud: 57600),
  MavlinkEndpoint('USB cable to the flight controller', 'COM3', baud: 115200),
  MavlinkEndpoint('Wi-Fi / network link (UDP 14550)', 'udpin:0.0.0.0:14550'),
  MavlinkEndpoint('SITL beside Mission Planner', 'tcp:127.0.0.1:5762'),
  MavlinkEndpoint('SITL alone', 'tcp:127.0.0.1:5760'),
];

/// The speeds a ground radio is actually set to. 57600 is the SiK default and
/// what most telemetry kits ship at; a USB cable to the flight controller
/// ignores the number entirely.
const mavlinkBauds = <int>[57600, 115200, 921600];

/// A COM port or /dev/tty… — the only kind of address where speed matters.
bool isSerialAddress(String address) {
  final value = address.trim().toUpperCase();
  return value.startsWith('COM') || value.startsWith('/DEV/');
}

/// Flight modes in which the aircraft is stopped and waiting for the operator.
bool isHoldingMode(String? mode) => const {
  'BRAKE',
  'LOITER',
  'HOLD',
  'POSHOLD',
  'GUIDED',
}.contains(mode?.toUpperCase());

/// Close the telemetry link, asking first when the drone is flying.
///
/// Disconnecting is how the operator tidies up after a flight, and it is also
/// how they accidentally take away their own Return Home button: the aircraft
/// carries on with its mission either way, and only the transmitter can stop
/// it once the link is gone. The backend refuses a disconnect under an armed
/// drone; this is the operator overruling it, having been told what it costs.
Future<void> confirmAndDisconnectLink(BuildContext context) async {
  final cubit = context.read<MavlinkCubit>();
  final flying = cubit.state.isLive && cubit.state.telemetry.armed;

  if (flying) {
    final goAhead = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text('The drone is armed', style: AppTextStyle.textLgSemibold),
        content: Text(
          'Closing the link stops the live readings and the Return Home and '
          'Land buttons. The drone keeps flying its mission, and only the '
          'transmitter can stop it.',
          style: AppTextStyle.textMdRegular.copyWith(color: AppColors.dark500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Keep the link',
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.themeError,
              foregroundColor: AppColors.light100,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Disconnect anyway',
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
          ),
        ],
      ),
    );
    if (goAhead != true) return;
  }

  await cubit.disconnect(force: flying);
}

/// What the operator needs while an aircraft of theirs is in the air.
///
/// It lives in one widget because three screens can have started that flight —
/// the live mission map, the spray prescription page and the survey summary —
/// and a drone in the sky does not care which one is open. Every button
/// confirms first and then reports the vehicle's own words back: a refusal
/// ("PreArm: GPS not healthy", "Mode change failed: requires position") is the
/// useful half of the answer.
class FlightControls extends StatefulWidget {
  const FlightControls({
    super.key,
    this.onStopSpray,
    this.spraying = false,
    this.missionId,
    this.poll = true,
  });

  /// Whether to watch the link itself. False where the host screen already
  /// polls — the live mission map moves a marker and wants a faster rate than
  /// these buttons need, and two pollers would fight over it.
  final bool poll;

  /// Given when this flight is a spray run: shown first, and in red.
  final Future<void> Function()? onStopSpray;

  /// Whether the valve is (or may be) open right now.
  final bool spraying;

  /// Mission-history row to close out when the flight ends.
  final int? missionId;

  @override
  State<FlightControls> createState() => _FlightControlsState();
}

class _FlightControlsState extends State<FlightControls> {
  /// Resolved once: dispose() runs while the element is being torn down, so
  /// it must not look the cubit up through the tree at that point.
  late final MavlinkCubit _mavlink = context.read<MavlinkCubit>();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // These numbers decide what the operator does next, so watch the link for
    // as long as the controls are on screen.
    if (widget.poll) {
      _mavlink.startPolling(interval: const Duration(seconds: 1));
    }
  }

  @override
  void dispose() {
    if (widget.poll) _mavlink.stopPolling();
    super.dispose();
  }

  Future<void> _confirm({
    required String title,
    required String message,
    required String action,
    required Color colour,
    required Future<void> Function() run,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppTextStyle.textMdSemibold.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colour,
              foregroundColor: AppColors.light100,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
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

    setState(() => _busy = true);
    try {
      await run();
      if (mounted) _say('$action sent.');
    } catch (e) {
      if (mounted) {
        _say(e.toString().replaceFirst('Exception: ', ''), problem: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message, {bool problem = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: problem ? AppColors.themeError : null,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MavlinkCubit, MavlinkState>(
      builder: (context, state) {
        final live = state.isLive;
        final holding = isHoldingMode(state.telemetry.mode);
        final enabled = live && !_busy;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LinkLine(state: state),
            if (state.link.latestWarning != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _VehicleWarning(text: state.link.latestWarning!.text),
            ],
            const SizedBox(height: AppSpacing.md),

            if (widget.onStopSpray != null && widget.spraying) ...[
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.themeError,
                  ),
                  onPressed: _busy
                      ? null
                      : () => _confirm(
                          title: 'Stop spraying?',
                          message:
                              'The valve closes and the drone stops where it '
                              'is. It stays in the air.',
                          action: 'Stop spray',
                          colour: AppColors.themeError,
                          run: widget.onStopSpray!,
                        ),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop spray & hold'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !enabled
                        ? null
                        : () => holding
                              ? _confirm(
                                  title: 'Resume the mission?',
                                  message:
                                      'The drone carries on with the plan from '
                                      'where it stopped.',
                                  action: 'Resume',
                                  colour: AppColors.primary,
                                  run: () => _mavlink.command(
                                    'auto',
                                    missionId: widget.missionId,
                                  ),
                                )
                              : _confirm(
                                  title: 'Hold position?',
                                  message:
                                      'The drone stops where it is and hovers, '
                                      'with the spray valve closed. The mission '
                                      'can be resumed afterwards.',
                                  action: 'Hold',
                                  colour: AppColors.primary,
                                  run: () => _mavlink.command(
                                    'hold',
                                    missionId: widget.missionId,
                                  ),
                                ),
                    icon: Icon(
                      holding ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 18,
                    ),
                    label: Text(holding ? 'Resume' : 'Hold'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                    ),
                    onPressed: !enabled
                        ? null
                        : () => _confirm(
                            title: 'Return home?',
                            message:
                                'The valve closes, then the drone climbs to its '
                                'return height and flies back to the launch '
                                'point by itself.',
                            action: 'Return home',
                            colour: const Color(0xFFF59E0B),
                            run: () => _mavlink.command(
                              'rtl',
                              missionId: widget.missionId,
                            ),
                          ),
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('Return home'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.themeError,
                side: BorderSide(color: AppColors.themeError.withOpacity(0.5)),
              ),
              onPressed: !enabled
                  ? null
                  : () => _confirm(
                      title: 'Land here?',
                      message:
                          'The valve closes and the drone comes straight down '
                          'where it is now — not at the launch point. Check '
                          'what is underneath it.',
                      action: 'Land',
                      colour: AppColors.themeError,
                      run: () =>
                          _mavlink.command('land', missionId: widget.missionId),
                    ),
              icon: const Icon(Icons.flight_land_rounded, size: 18),
              label: const Text('Land here'),
            ),
          ],
        );
      },
    );
  }
}

/// One line of the readings that matter while something is in the air.
class _LinkLine extends StatelessWidget {
  const _LinkLine({required this.state});

  final MavlinkState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isLive) {
      return Row(
        children: [
          Icon(Icons.signal_wifi_off_rounded, size: 15, color: AppColors.themeError),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              state.isConnected
                  ? 'The vehicle has gone quiet — no readings, and these '
                        'buttons cannot reach it.'
                  : 'No telemetry link.',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.themeError,
              ),
            ),
          ),
        ],
      );
    }

    final telemetry = state.telemetry;
    final parts = <String>[
      telemetry.mode ?? 'linked',
      if (telemetry.relativeAltitudeM != null)
        '${telemetry.relativeAltitudeM!.toStringAsFixed(0)} m',
      if (telemetry.groundspeedMs != null)
        '${telemetry.groundspeedMs!.toStringAsFixed(1)} m/s',
      if (telemetry.batteryPercent != null) '${telemetry.batteryPercent}%',
      if (telemetry.satellites != null) '${telemetry.satellites} sats',
    ];

    return Row(
      children: [
        Icon(
          Icons.settings_input_antenna,
          size: 15,
          color: AppColors.themeSuccess,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            parts.join('  ·  '),
            style: AppTextStyle.textXsSemibold.copyWith(color: AppColors.dark500),
          ),
        ),
        if (telemetry.armed)
          Text(
            'ARMED',
            style: AppTextStyle.textXsBold.copyWith(color: AppColors.themeError),
          ),
      ],
    );
  }
}

/// The autopilot's own words, when it has just complained about something.
class _VehicleWarning extends StatelessWidget {
  const _VehicleWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.themeWarning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: AppColors.themeWarning,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.dark500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
