import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/mavlink/mavlink_cubit.dart';

/// Floating chip showing the MAVLink link to the aircraft, on the mission
/// screens. Tapping it opens [MavlinkConnectSheet].
///
/// Colour is the whole point: green = telemetry flowing (safe to launch),
/// amber = socket open but the vehicle went quiet, grey = no link, so the
/// mission runs as an on-screen simulation only.
class MavlinkLinkChip extends StatelessWidget {
  const MavlinkLinkChip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MavlinkCubit, MavlinkState>(
      builder: (context, state) {
        final color = switch (state.status) {
          MavlinkPhase.connected => AppColors.themeSuccess,
          MavlinkPhase.stale => const Color(0xFFF59E0B),
          MavlinkPhase.failure => AppColors.themeError,
          _ => AppColors.light100.withOpacity(0.45),
        };

        return GestureDetector(
          onTap: onTap ?? () => MavlinkConnectSheet.show(context),
          child: Container(
            margin: const EdgeInsets.only(top: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A28).withOpacity(0.88),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: color.withOpacity(0.55), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.isBusy)
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  )
                else
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.settings_input_antenna, size: 11, color: color),
                const SizedBox(width: 3),
                Text(
                  state.label,
                  style: AppTextStyle.textXsSemibold.copyWith(color: color),
                ),
                if (state.isLive && state.telemetry.armed) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'ARMED',
                    style: AppTextStyle.textXsBold.copyWith(
                      color: AppColors.themeError,
                      fontSize: 9,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet for opening / closing the link to the flight controller.
///
/// Leaving the address blank uses the backend's `MAVLINK_URL`, which points
/// at the simulator by default — so a test flight is one tap from here.
class MavlinkConnectSheet extends StatefulWidget {
  const MavlinkConnectSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<MavlinkCubit>(),
        child: const MavlinkConnectSheet(),
      ),
    );
  }

  @override
  State<MavlinkConnectSheet> createState() => _MavlinkConnectSheetState();
}

class _MavlinkConnectSheetState extends State<MavlinkConnectSheet> {
  final TextEditingController _urlCtrl = TextEditingController();

  /// The endpoints people actually use, so nobody has to remember pymavlink's
  /// connection-string syntax on a phone keyboard.
  ///
  /// Labels spell out the *direction*, because that is the thing that goes
  /// wrong: `udpin:` means the backend listens for a stream sent to it (works
  /// for a simulator anywhere on the network), while `tcp:` means the backend
  /// dials out to that exact host (only works on the backend's own machine).
  /// Picking the second for a simulator on another laptop just gets a refused
  /// connection.
  static const _presets = <String, String>{
    'Simulator — any machine on the network': 'udpin:0.0.0.0:14550',
    'ArduPilot SITL on the server itself': 'tcp:127.0.0.1:5760',
    'Telemetry radio (USB)': 'COM5',
  };

  @override
  void initState() {
    super.initState();
    context.read<MavlinkCubit>().refresh();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MavlinkCubit, MavlinkState>(
      builder: (context, state) {
        final telemetry = state.telemetry;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A28),
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.settings_input_antenna,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Flight Controller Link',
                        style: AppTextStyle.textLgBold.copyWith(
                          color: AppColors.light100,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  state.isConnected
                      ? 'Connected on ${state.link.url}'
                      : 'Not connected — missions run as an on-screen '
                            'simulation until a vehicle is linked.',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.light100.withOpacity(0.65),
                  ),
                ),

                // ── live vehicle readout ─────────────────────────────────
                if (state.isConnected) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _Fact('Mode', telemetry.mode ?? '—'),
                      _Fact('Armed', telemetry.armed ? 'yes' : 'no'),
                      _Fact(
                        'GPS',
                        telemetry.satellites == null
                            ? '—'
                            : '${telemetry.satellites} sats',
                      ),
                      _Fact(
                        'Battery',
                        telemetry.batteryPercent == null
                            ? '—'
                            : '${telemetry.batteryPercent}%',
                      ),
                      _Fact(
                        'Alt',
                        telemetry.relativeAltitudeM == null
                            ? '—'
                            : '${telemetry.relativeAltitudeM!.toStringAsFixed(1)} m',
                      ),
                    ],
                  ),
                ],

                // ── error / autopilot messages ───────────────────────────
                if (state.errorMessage.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    state.errorMessage,
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.themeError,
                    ),
                  ),
                ],
                if (state.link.messages.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  for (final m in state.link.messages.reversed.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        m.text,
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: m.isWarning
                              ? const Color(0xFFF59E0B)
                              : AppColors.light100.withOpacity(0.55),
                        ),
                      ),
                    ),
                ],

                // ── address ──────────────────────────────────────────────
                if (!state.isConnected) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'ADDRESS',
                    style: AppTextStyle.textXsSemibold.copyWith(
                      color: AppColors.light100.withOpacity(0.55),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: _urlCtrl,
                    style: AppTextStyle.textSmRegular.copyWith(
                      color: AppColors.light100,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.light100.withOpacity(0.07),
                      hintText: 'Leave blank for the server default',
                      hintStyle: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.light100.withOpacity(0.35),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm + 2,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final entry in _presets.entries)
                        GestureDetector(
                          onTap: () => _urlCtrl.text = entry.value,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              entry.key,
                              style: AppTextStyle.textXsRegular.copyWith(
                                color: AppColors.primary3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    if (state.isConnected)
                      Expanded(
                        child: _SheetButton(
                          label: 'Disconnect',
                          icon: Icons.link_off_rounded,
                          color: AppColors.themeError,
                          onTap: () =>
                              context.read<MavlinkCubit>().disconnect(),
                        ),
                      )
                    else
                      Expanded(
                        child: _SheetButton(
                          label: state.isBusy ? 'Connecting…' : 'Connect',
                          icon: Icons.link_rounded,
                          color: AppColors.primary,
                          onTap: state.isBusy
                              ? null
                              : () => context.read<MavlinkCubit>().connect(
                                  url: _urlCtrl.text.trim().isEmpty
                                      ? null
                                      : _urlCtrl.text.trim(),
                                ),
                        ),
                      ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _SheetButton(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        color: AppColors.light100.withOpacity(0.15),
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.light100.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text.rich(
        TextSpan(
          text: '$label  ',
          style: AppTextStyle.textXsRegular.copyWith(
            color: AppColors.light100.withOpacity(0.5),
          ),
          children: [
            TextSpan(
              text: value,
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppColors.light100),
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
      ),
    );
  }
}
