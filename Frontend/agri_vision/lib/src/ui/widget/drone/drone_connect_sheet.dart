import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/mavlink/mavlink_cubit.dart';

/// The one place in the app where a drone gets connected.
///
/// Connecting is two separate things and the sheet keeps them separate,
/// because either can be the reason the screens show no numbers:
///
///  1. **Aircraft** — pair the unit to this account by serial number. A serial
///     the server hasn't seen registers that aircraft, so a new drone can be
///     added straight from the field.
///  2. **Telemetry link** — open the MAVLink connection that actually carries
///     battery / GPS / position. Until this is live the app has no readings to
///     show, and it shows none.
class DroneConnectSheet extends StatefulWidget {
  const DroneConnectSheet({super.key});

  /// Opens the sheet, carrying the app-scoped cubits across the modal route.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<DroneCubit>()),
          BlocProvider.value(value: context.read<MavlinkCubit>()),
        ],
        child: const DroneConnectSheet(),
      ),
    );
  }

  @override
  State<DroneConnectSheet> createState() => _DroneConnectSheetState();
}

class _DroneConnectSheetState extends State<DroneConnectSheet> {
  final TextEditingController _serialCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();

  /// The endpoints people actually use, so nobody has to remember pymavlink's
  /// connection-string syntax on a phone keyboard.
  ///
  /// SITL exposes three MAVLink TCP ports (5760, 5762, 5763) and Mission
  /// Planner takes 5760 when it launches the simulation — so the first preset
  /// works *alongside* it with nothing to configure on the Mission Planner
  /// side. `udpin:` is only right when the simulator is on another machine and
  /// forwarding here; on this machine Mission Planner already holds 14550 and
  /// the bind would fail.
  static const _presets = <String, String>{
    'SITL beside Mission Planner': 'tcp:127.0.0.1:5762',
    'SITL alone (no Mission Planner)': 'tcp:127.0.0.1:5760',
    'Simulator on another PC': 'udpin:0.0.0.0:14550',
    'Telemetry radio': 'COM5',
  };

  @override
  void initState() {
    super.initState();
    // Both halves are re-read on open: the sheet should never be the thing
    // telling the operator something is connected when it isn't.
    context.read<DroneCubit>().load(refresh: true);
    context.read<MavlinkCubit>().refresh();
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final serial = _serialCtrl.text.trim();
    if (serial.isEmpty) {
      _snack('Enter the drone serial number.');
      return;
    }
    await context.read<DroneCubit>().pair(serial, name: _nameCtrl.text);
    if (!mounted) return;

    final state = context.read<DroneCubit>().state;
    _snack(
      state.status == DroneStatus.failure
          ? 'Pairing failed: ${state.errorMessage}'
          : 'Paired with ${state.drone?.unitName ?? serial}',
    );
  }

  Future<void> _unpair() async {
    await context.read<DroneCubit>().unpair();
    if (!mounted) return;
    _serialCtrl.clear();
    _nameCtrl.clear();
    final state = context.read<DroneCubit>().state;
    _snack(
      state.status == DroneStatus.failure
          ? 'Could not unpair: ${state.errorMessage}'
          : 'Drone unpaired.',
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.lg),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A28),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.flight_takeoff_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Connect Drone',
                      style: AppTextStyle.textLgBold.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.light100.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              const _StepLabel('1', 'AIRCRAFT'),
              const SizedBox(height: AppSpacing.sm),
              _pairSection(),

              const SizedBox(height: AppSpacing.xl),
              const _StepLabel('2', 'TELEMETRY LINK'),
              const SizedBox(height: AppSpacing.sm),
              _linkSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1: the aircraft ────────────────────────────────────────────────

  Widget _pairSection() {
    return BlocBuilder<DroneCubit, DroneState>(
      builder: (context, state) {
        final drone = state.drone;

        if (drone != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Panel(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            drone.unitName,
                            style: AppTextStyle.textMdSemibold.copyWith(
                              color: AppColors.light100,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SN: ${drone.serialNumber}',
                            style: AppTextStyle.textXsRegular.copyWith(
                              color: AppColors.light100.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: state.isLoading ? null : _unpair,
                      child: Text(
                        'Unpair',
                        style: AppTextStyle.textSmSemibold.copyWith(
                          color: AppColors.themeError,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.status == DroneStatus.failure &&
                  state.errorMessage.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _ErrorText(state.errorMessage),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No drone paired to this account.',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.light100.withOpacity(0.65),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SheetField(
              controller: _serialCtrl,
              hint: 'Serial number (e.g. ADU-2024-04-7832)',
            ),
            const SizedBox(height: AppSpacing.sm),
            _SheetField(
              controller: _nameCtrl,
              hint: 'Name (optional, e.g. AgriDrone GCS-04)',
            ),
            if (state.status == DroneStatus.failure &&
                state.errorMessage.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _ErrorText(state.errorMessage),
            ],
            const SizedBox(height: AppSpacing.md),
            _SheetButton(
              label: state.isLoading ? 'Pairing…' : 'Pair Drone',
              icon: Icons.link_rounded,
              color: AppColors.primary,
              onTap: state.isLoading ? null : _pair,
            ),
          ],
        );
      },
    );
  }

  // ── Step 2: the MAVLink link ────────────────────────────────────────────

  Widget _linkSection() {
    return BlocBuilder<MavlinkCubit, MavlinkState>(
      builder: (context, state) {
        final telemetry = state.telemetry;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.isLive
                  ? 'Telemetry flowing on ${state.link.url ?? 'the server link'}.'
                  : state.isConnected
                        ? 'Link open on ${state.link.url ?? '—'}, but the '
                              'vehicle has gone quiet.'
                        : 'Not connected — no live readings until a vehicle '
                              'is on the link.',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.light100.withOpacity(0.65),
              ),
            ),

            if (state.isLive) ...[
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
                ],
              ),
            ],

            if (state.errorMessage.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _ErrorText(state.errorMessage),
            ],

            if (!state.isConnected) ...[
              const SizedBox(height: AppSpacing.md),
              _SheetField(
                controller: _urlCtrl,
                hint: 'Address — blank uses the server default',
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
                          borderRadius: BorderRadius.circular(AppRadius.full),
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

            const SizedBox(height: AppSpacing.md),
            if (state.isConnected)
              _SheetButton(
                label: 'Disconnect Link',
                icon: Icons.link_off_rounded,
                color: AppColors.themeError,
                onTap: () => context.read<MavlinkCubit>().disconnect(),
              )
            else
              _SheetButton(
                label: state.isBusy ? 'Connecting…' : 'Connect Link',
                icon: Icons.settings_input_antenna,
                color: AppColors.primary,
                onTap: state.isBusy
                    ? null
                    : () async {
                        await context.read<MavlinkCubit>().connect(
                          url: _urlCtrl.text.trim().isEmpty
                              ? null
                              : _urlCtrl.text.trim(),
                        );
                        // The paired unit's gauges come from this link, so
                        // refresh it the moment the link changes.
                        if (mounted) {
                          await context.read<DroneCubit>().load(refresh: true);
                        }
                      },
              ),
          ],
        );
      },
    );
  }
}

// ── Small building blocks ──────────────────────────────────────────────────

class _StepLabel extends StatelessWidget {
  const _StepLabel(this.step, this.label);

  final String step;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: AppTextStyle.textXsBold.copyWith(color: AppColors.primary3),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: AppTextStyle.textXsSemibold.copyWith(
            color: AppColors.light100.withOpacity(0.55),
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.light100.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: child,
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: AppTextStyle.textSmRegular.copyWith(color: AppColors.light100),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.light100.withOpacity(0.07),
        hintText: hint,
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
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: AppTextStyle.textXsRegular.copyWith(color: AppColors.themeError),
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
          width: double.infinity,
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
