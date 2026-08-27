import 'package:flutter/material.dart';

import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/survey_entity.dart';

/// Which cameras the aircraft flies with.
///
/// Rendered as three full-width rows rather than a segmented control, because
/// this is not a preference — it decides what the flight can find out. A row
/// carries what the mode actually does, and an unavailable one stays visible
/// with the reason it cannot be flown: "no RGB camera is registered" tells the
/// operator what to fix, and a missing option tells them nothing.
class CameraModeSelector extends StatelessWidget {
  const CameraModeSelector({
    required this.capabilities,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final SurveyCapabilities capabilities;
  final CameraMode selected;
  final ValueChanged<CameraMode> onSelect;

  static const Map<CameraMode, IconData> _icons = {
    CameraMode.multispectral: Icons.grain,
    CameraMode.ipCamera: Icons.videocam_outlined,
    CameraMode.both: Icons.auto_awesome_motion_outlined,
  };

  @override
  Widget build(BuildContext context) {
    if (capabilities.cameraModes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in capabilities.cameraModes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _ModeRow(
              option: option,
              icon: _icons[option.mode] ?? Icons.camera_alt_outlined,
              selected: option.mode == selected,
              onTap: option.available ? () => onSelect(option.mode) : null,
            ),
          ),
        if (!capabilities.hasAnyMode)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.themeWarning.withOpacity(0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppColors.themeWarning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'No camera is registered on this drone yet. Add one on the '
                    'Drone Capture screen before flying a survey.',
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.dark500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.option,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final CameraModeOption option;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final radius = BorderRadius.circular(AppRadius.lg);

    return Material(
      color: selected
          ? AppColors.primary.withOpacity(0.08)
          : (enabled ? AppColors.light100 : AppColors.light300),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.light500,
              width: selected ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (selected ? AppColors.primary : AppColors.dark100)
                      .withOpacity(enabled ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: enabled
                      ? (selected ? AppColors.primary : AppColors.dark300)
                      : AppColors.light900,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.name,
                            style: AppTextStyle.textMdSemibold.copyWith(
                              color: enabled
                                  ? AppColors.dark900
                                  : AppColors.dark100,
                            ),
                          ),
                        ),
                        if (enabled && option.cameraCount > 0)
                          Text(
                            option.cameraCount == 1
                                ? '1 camera'
                                : '${option.cameraCount} cameras',
                            style: AppTextStyle.textXsRegular.copyWith(
                              color: AppColors.dark100,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.detail,
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: enabled ? AppColors.dark300 : AppColors.dark100,
                      ),
                    ),
                    // The reason a mode cannot be flown is the actionable part
                    // of this screen, so it is shown, not hidden behind the
                    // control being greyed out.
                    if (!enabled && option.reason.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 13,
                            color: AppColors.themeWarning,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              option.reason,
                              style: AppTextStyle.textXsRegular.copyWith(
                                color: AppColors.themeWarning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(
                    Icons.check_circle,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the CNN is asked to look for on this pass.
///
/// "Weeds only" is the drone's weed-detection mode. It is not a filter on the
/// display: the disease CNN is genuinely skipped, which roughly halves the
/// per-frame cost — the difference between a readout that describes where the
/// aircraft *is* and one that describes where it was.
class DetectionTargetSelector extends StatelessWidget {
  const DetectionTargetSelector({
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final DetectionTarget selected;
  final ValueChanged<DetectionTarget> onSelect;

  static const Map<DetectionTarget, ({IconData icon, String hint})> _meta = {
    DetectionTarget.disease: (
      icon: Icons.coronavirus_outlined,
      hint: 'Crop-disease CNN only',
    ),
    DetectionTarget.weed: (
      icon: Icons.grass_outlined,
      hint: 'Weed detection only — about twice as fast per frame',
    ),
    DetectionTarget.both: (
      icon: Icons.done_all,
      hint: 'Both detectors on every sampled frame',
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final target in DetectionTarget.values)
              ChoiceChip(
                avatar: Icon(
                  _meta[target]!.icon,
                  size: 16,
                  color: target == selected
                      ? AppColors.light100
                      : AppColors.dark300,
                ),
                label: Text(target.label),
                selected: target == selected,
                selectedColor: AppColors.primary,
                labelStyle: AppTextStyle.textSmMedium.copyWith(
                  color: target == selected
                      ? AppColors.light100
                      : AppColors.dark500,
                ),
                onSelected: (_) => onSelect(target),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _meta[selected]!.hint,
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
        ),
      ],
    );
  }
}
