import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Draggable collapsible bottom sheet for the mission planning screen.
/// Snap states: peek (name + quick stats visible) → expanded (all settings).
class MissionBottomSheet extends StatefulWidget {
  const MissionBottomSheet({
    super.key,
    required this.settings,
    required this.waypointCount,
    required this.onSettingsChanged,
    required this.onSave,
    required this.onStartMission,
    required this.missionNameController,
  });

  final MissionSettings settings;
  final int waypointCount;
  final ValueChanged<MissionSettings> onSettingsChanged;
  final VoidCallback onSave;
  final VoidCallback onStartMission;
  final TextEditingController missionNameController;

  @override
  State<MissionBottomSheet> createState() => _MissionBottomSheetState();
}

class _MissionBottomSheetState extends State<MissionBottomSheet> {
  // derived
  double get _areHa => 4.2;
  int get _estMinutes => 18;
  double get _sprayTotal => _areHa * widget.settings.sprayVolume;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.30,
      minChildSize: 0.15,
      maxChildSize: 0.88,
      snap: true,
      snapSizes: const [0.15, 0.30, 0.88],
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.light100,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppRadius.xl + 2),
              topRight: Radius.circular(AppRadius.xl + 2),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.zero,
            children: [
              // ── drag handle ──────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.light700,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),

              // ── section label ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text('Mission Setup', style: AppTextStyle.textXlBold),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── mission name field ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MISSION NAME',
                      style: AppTextStyle.textXsSemibold.copyWith(
                        color: AppColors.dark100,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: widget.missionNameController,
                      style: AppTextStyle.textMdRegular,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.light300,
                        hintText: 'Mission name',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: const BorderSide(
                            color: AppColors.light500,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: const BorderSide(
                            color: AppColors.light500,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── quick stats row ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    MissionStatChip(
                      value: '${widget.waypointCount}',
                      label: 'Waypoints',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    MissionStatChip(
                      value: '${_areHa.toStringAsFixed(1)} ha',
                      label: 'Area',
                      valueColor: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    MissionStatChip(
                      value: '~$_estMinutes min',
                      label: 'Est. Time',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── expandable settings cards ────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    // Altitude
                    MissionSettingsCard(
                      icon: Icons.height_rounded,
                      title: 'Altitude & Speed',
                      summary:
                          '${widget.settings.altitude} m · ${widget.settings.speed.toStringAsFixed(1)} m/s',
                      child: Column(
                        children: [
                          SettingStepperRow(
                            label: 'Flight Altitude',
                            value: widget.settings.altitude,
                            unit: 'm',
                            min: 10,
                            max: 120,
                            onDecrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                altitude: widget.settings.altitude - 5,
                              ),
                            ),
                            onIncrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                altitude: widget.settings.altitude + 5,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SettingStepperRow(
                            label: 'Flight Speed',
                            value: widget.settings.speed,
                            unit: 'm/s',
                            min: 1.0,
                            max: 15.0,
                            onDecrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                speed: widget.settings.speed - 0.5,
                              ),
                            ),
                            onIncrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                speed: widget.settings.speed + 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),

                    // Coverage
                    MissionSettingsCard(
                      icon: Icons.grid_on_rounded,
                      title: 'Coverage Pattern',
                      summary:
                          '${widget.settings.overlap}% overlap · ${widget.settings.lineSpacing.toStringAsFixed(1)} m spacing',
                      child: Column(
                        children: [
                          SettingStepperRow(
                            label: 'Side Overlap',
                            value: widget.settings.overlap,
                            unit: '%',
                            min: 10,
                            max: 90,
                            onDecrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                overlap: widget.settings.overlap - 5,
                              ),
                            ),
                            onIncrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                overlap: widget.settings.overlap + 5,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SettingStepperRow(
                            label: 'Line Spacing',
                            value: widget.settings.lineSpacing,
                            unit: 'm',
                            min: 1.0,
                            max: 12.0,
                            onDecrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                lineSpacing: widget.settings.lineSpacing - 0.5,
                              ),
                            ),
                            onIncrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                lineSpacing: widget.settings.lineSpacing + 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),

                    // Sprayer
                    MissionSettingsCard(
                      icon: Icons.water_drop_outlined,
                      title: 'Sprayer Settings',
                      summary:
                          '${widget.settings.sprayVolume.toStringAsFixed(1)} L/ha · ${_sprayTotal.toStringAsFixed(1)} L total',
                      child: Column(
                        children: [
                          SettingStepperRow(
                            label: 'Spray Rate',
                            value: widget.settings.sprayVolume,
                            unit: 'L/ha',
                            min: 0.5,
                            max: 20.0,
                            onDecrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                sprayVolume: widget.settings.sprayVolume - 0.5,
                              ),
                            ),
                            onIncrement: () => widget.onSettingsChanged(
                              widget.settings.copyWith(
                                sprayVolume: widget.settings.sprayVolume + 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _InfoRow(
                            label: 'Total Spray Volume',
                            value: '${_sprayTotal.toStringAsFixed(1)} L',
                          ),
                          _InfoRow(
                            label: 'Batteries Required',
                            value: '${widget.settings.batteryRequired}×',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),

              // ── action buttons ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AppIconButton(
                        label: 'Save',
                        startIcon: Icons.save_outlined,
                        color: AppColors.light100,
                        pressedColor: AppColors.light300,
                        borderColor: AppColors.light700,
                        pressedBorderColor: AppColors.primary,
                        textColor: AppColors.dark700,
                        pressedTextColor: AppColors.primary,
                        iconColor: AppColors.dark700,
                        pressedIconColor: AppColors.primary,
                        textStyle: AppTextStyle.textMdSemibold,
                        height: 50,
                        borderRadius: AppRadius.lg,
                        mainAxisAlignment: MainAxisAlignment.center,
                        onPressed: widget.onSave,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: AppIconButton(
                        label: 'Start Mission',
                        startIcon: Icons.play_arrow_rounded,
                        color: AppColors.primary,
                        pressedColor: AppColors.primary6,
                        showBorder: false,
                        textColor: AppColors.light100,
                        pressedTextColor: AppColors.light100,
                        iconColor: AppColors.light100,
                        pressedIconColor: AppColors.light100,
                        textStyle: AppTextStyle.textMdSemibold,
                        height: 50,
                        borderRadius: AppRadius.lg,
                        mainAxisAlignment: MainAxisAlignment.center,
                        onPressed: widget.onStartMission,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
          Text(
            value,
            style: AppTextStyle.textSmSemibold.copyWith(
              color: AppColors.dark700,
            ),
          ),
        ],
      ),
    );
  }
}
