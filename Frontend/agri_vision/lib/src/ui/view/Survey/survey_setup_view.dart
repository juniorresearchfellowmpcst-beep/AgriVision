import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/fieldscan/field_scan_cubit.dart';
import 'package:agri_vision/src/ui/cubit/survey/survey_cubit.dart';
import 'package:agri_vision/src/ui/widget/survey/camera_mode_selector.dart';

/// Before the flight: which cameras, which crop, what to look for.
///
/// The order is the order the decisions actually depend on each other in. The
/// camera mode comes first because it decides what the flight *can* find out —
/// a multispectral-only pass will never name a disease, and an operator who
/// picks it expecting one has wasted a battery.
class SurveySetupView extends StatelessWidget {
  const SurveySetupView({required this.state, super.key});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SurveyCubit>();

    return RefreshIndicator(
      onRefresh: () => cubit.load(refresh: true),
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // What this survey will actually produce, said before it starts.
          //
          // The camera and the aircraft are separate requirements and the
          // operator has no way to know that: detection runs on whatever the
          // camera sends, so a bench camera with the flight controller
          // unplugged still gives a real diagnosis. The drone adds position,
          // and position is what turns detections into a hotspot map and a
          // spray mission. Someone who cannot connect the aircraft today
          // should be told they can still scan, rather than assuming the
          // whole screen is unusable.
          _FlightLinkNote(link: state.capabilities.flightLink),
          const SizedBox(height: AppSpacing.lg),

          const _SectionLabel(
            'DRONE CAMERA',
            hint: 'This decides what the flight can find out.',
          ),
          CameraModeSelector(
            capabilities: state.capabilities,
            selected: state.cameraMode,
            onSelect: cubit.selectCameraMode,
          ),

          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel(
            'WHAT TO LOOK FOR',
            hint: 'The CNN runs on the video feed as the aircraft flies.',
          ),
          _Card(
            child: DetectionTargetSelector(
              selected: state.target,
              onSelect: cubit.selectTarget,
            ),
          ),
          // A multispectral-only pass has no video feed for the CNN to read,
          // so this choice does nothing on that mode. Say it, rather than
          // leaving the operator to notice an empty readout at altitude.
          if (!state.cameraMode.usesRgb) ...[
            const SizedBox(height: AppSpacing.sm),
            _InlineNote(
              icon: Icons.info_outline,
              color: AppColors.themeWarning,
              text: 'A multispectral-only survey has no video feed to scan, so '
                  'there is no live disease or weed readout. The bands map '
                  'where the field is stressed; they cannot say why.',
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel(
            'CROP',
            hint: 'Part of the diagnosis: the same yellowing is yellow rust in '
                'wheat and yellow mosaic in soybean.',
          ),
          _Card(child: _CropPicker(state: state)),

          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('BLOCK'),
          _Card(
            child: TextFormField(
              initialValue: state.fieldName,
              textCapitalization: TextCapitalization.words,
              onChanged: cubit.setFieldName,
              decoration: InputDecoration(
                labelText: 'Which block is this? (optional)',
                hintText: 'e.g. Block A — north',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),

          if (state.errorMessage.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _InlineNote(
              icon: Icons.error_outline,
              color: AppColors.themeError,
              text: state.errorMessage,
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              onPressed: (state.isBusy || !state.capabilities.hasAnyMode)
                  ? null
                  : cubit.start,
              icon: state.status == SurveyStatus.starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.light100,
                      ),
                    )
                  : const Icon(Icons.flight_takeoff),
              label: Text(
                'Start survey',
                style: AppTextStyle.textLgSemibold.copyWith(
                  color: AppColors.light100,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Fly the block as usual. The scan runs on the ground station, so '
            'you can close this screen and come back to it.',
            textAlign: TextAlign.center,
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),

          if (state.history.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            const _SectionLabel('PAST SURVEYS'),
            for (final run in state.history.take(6))
              _HistoryRow(
                run: run,
                onTap: run.isFinished
                    ? () => cubit.openSummary(run.id)
                    : null,
              ),
          ],

          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

/// The crop list, shared with the field-scan screen so there is one catalogue.
class _CropPicker extends StatelessWidget {
  const _CropPicker({required this.state});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FieldScanCubit, FieldScanState>(
      buildWhen: (a, b) => a.crops != b.crops,
      builder: (context, scanState) {
        if (scanState.crops.isEmpty) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final crop in scanState.crops)
              ChoiceChip(
                label: Text(crop.name),
                selected: state.crop == crop.id,
                selectedColor: AppColors.primary,
                labelStyle: AppTextStyle.textSmMedium.copyWith(
                  color: state.crop == crop.id
                      ? AppColors.light100
                      : AppColors.dark500,
                ),
                onSelected: (selected) => context
                    .read<SurveyCubit>()
                    .selectCrop(selected ? crop.id : null),
              ),
          ],
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.run, required this.onTap});

  final SurveyRun run;
  final VoidCallback? onTap;

  static const Map<String, Color> _statusColors = {
    'analysed': AppColors.themeSuccess,
    'authorised': AppColors.themeWarning,
    'spraying': Color(0xFF2E86DE),
    'completed': AppColors.themeSuccess,
    'cancelled': AppColors.dark100,
    'flying': AppColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[run.status] ?? AppColors.dark100;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.light500),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        dense: true,
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            run.healthScore?.toString() ?? '—',
            style: AppTextStyle.textSmSemibold.copyWith(color: color),
          ),
        ),
        title: Text(
          run.fieldName?.isNotEmpty == true ? run.fieldName! : 'Survey #${run.id}',
          style: AppTextStyle.textSmSemibold,
        ),
        subtitle: Text(
          [
            run.cameraMode.label,
            if (run.crop != null) run.crop!,
            '${run.framesScanned} frames',
            run.status,
          ].join(' · '),
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
        ),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right, color: AppColors.dark100),
      ),
    );
  }
}

// ── small shared pieces ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: AppTextStyle.textXsSemibold.copyWith(
              color: AppColors.dark100,
              letterSpacing: 0.8,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: child,
    );
  }
}

/// What this survey can produce right now, given the flight link.
///
/// Three states, because there are genuinely three, and collapsing them
/// misleads in one direction or the other:
///
///   * linked with a fix — diagnosis *and* a map, so a spray plan is coming;
///   * linked, no fix yet — scan now, the map is waiting on position;
///   * no link — a real diagnosis from the camera alone, and no spray plan.
///
/// Deliberately not an error. The third state is a normal way to use the app,
/// not a fault to be cleared, so it is drawn in the app's own colours rather
/// than in red.
class _FlightLinkNote extends StatelessWidget {
  const _FlightLinkNote({required this.link});

  final FlightLink link;

  @override
  Widget build(BuildContext context) {
    final ready = link.canMap;
    final colour = ready
        ? AppColors.themeSuccess
        : link.connected
        ? AppColors.themeWarning
        : AppColors.dark300;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colour.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready
                ? Icons.satellite_alt
                : link.connected
                ? Icons.gps_not_fixed
                : Icons.photo_camera_outlined,
            size: 18,
            color: colour,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready
                      ? 'Drone linked — full survey'
                      : link.connected
                      ? 'Drone linked — waiting for GPS'
                      : 'Camera only — detection still works',
                  style: AppTextStyle.textSmSemibold.copyWith(color: colour),
                ),
                const SizedBox(height: 2),
                Text(
                  link.detail.isNotEmpty
                      ? link.detail
                      : 'Detection runs on the camera feed. The drone adds '
                            'position, which is what builds the spray map.',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
