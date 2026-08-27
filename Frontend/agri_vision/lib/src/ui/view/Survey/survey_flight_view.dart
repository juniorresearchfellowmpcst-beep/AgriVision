import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/survey/survey_cubit.dart';
import 'package:agri_vision/src/ui/widget/capture/mjpeg_view.dart';

/// While the aircraft is over the field.
///
/// The CNN's verdict on the frame under the camera a second ago, the rolling
/// answer over the last couple of minutes, and the one control that matters
/// mid-flight — ending the pass.
///
/// A dropped link says so rather than leaving the last good verdict on screen
/// looking current. That is the failure this screen most has to avoid: an
/// operator reading a frozen "healthy" while the aircraft crosses the worst
/// part of the block.
class SurveyFlightView extends StatelessWidget {
  const SurveyFlightView({required this.state, super.key});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SurveyCubit>();
    final run = state.run!;
    final progress = state.progress;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _RunHeader(run: run, progress: progress),

              // The live picture, when this run is reading an RGB camera.
              if (run.uses(CameraMode.ipCamera) && run.rgbCameraId != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _FeedCard(cameraId: run.rgbCameraId!, progress: progress),
              ],

              const SizedBox(height: AppSpacing.lg),
              _LatestVerdict(progress: progress, run: run),

              if (progress.rollingSummary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _RollingCard(progress: progress),
              ],

              if (run.cameraMode.usesBands) ...[
                const SizedBox(height: AppSpacing.lg),
                _ShotCard(state: state),
              ],

              if (state.warnings.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                for (final warning in state.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _Banner(
                      icon: Icons.info_outline,
                      color: AppColors.themeWarning,
                      text: warning,
                    ),
                  ),
              ],

              // A failed poll is not a failed survey — the aircraft is still
              // flying and the server is still scanning.
              if (state.pollError.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _Banner(
                  icon: Icons.wifi_off,
                  color: AppColors.dark300,
                  text: 'Lost touch with the ground station: ${state.pollError}\n'
                      'The scan keeps running; this screen will catch up.',
                ),
              ],

              const SizedBox(height: 80),
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
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                onPressed: state.isBusy ? null : cubit.finish,
                icon: state.status == SurveyStatus.summarising
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.light100,
                        ),
                      )
                    : const Icon(Icons.flag_outlined),
                label: Text(
                  state.status == SurveyStatus.summarising
                      ? 'Working out the field report…'
                      : 'End pass & get the report',
                  style: AppTextStyle.textLgSemibold.copyWith(
                    color: AppColors.light100,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension on SurveyRun {
  /// Whether this run reads the given camera kind.
  bool uses(CameraMode mode) => mode == CameraMode.ipCamera
      ? cameraMode.usesRgb
      : cameraMode.usesBands;
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({required this.run, required this.progress});

  final SurveyRun run;
  final SurveyProgress progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF245C43), Color(0xFF1A3A28)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pulse(active: progress.running && !progress.signalLost),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  progress.signalLost
                      ? 'Signal lost — reconnecting'
                      : (progress.running ? 'Scanning' : 'Waiting for frames'),
                  style: AppTextStyle.textMdSemibold.copyWith(
                    color: AppColors.light100,
                  ),
                ),
              ),
              Text(
                run.fieldName?.isNotEmpty == true
                    ? run.fieldName!
                    : 'Survey #${run.id}',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.light100.withOpacity(0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _HeaderStat(label: 'Frames scanned', value: '${progress.scanned}'),
              _HeaderStat(
                label: 'Hotspots',
                value: '${progress.hotspots}',
                highlight: progress.hotspots > 0,
              ),
              if (run.cameraMode.usesBands)
                _HeaderStat(label: 'Shots', value: '${progress.shots}')
              else
                _HeaderStat(label: 'Skipped', value: '${progress.skipped}'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${run.cameraMode.label} · ${run.detectionTarget.label}'
            '${run.crop != null ? " · ${run.crop}" : ""}',
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.light100.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyle.textXlBold.copyWith(
              color: highlight ? AppColors.themeWarning : AppColors.light100,
            ),
          ),
          Text(
            label,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.light100.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dot that only pulses while frames are genuinely arriving.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active});

  final bool active;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour =
        widget.active ? AppColors.themeSuccess : AppColors.themeWarning;
    return FadeTransition(
      // Frozen rather than pulsing when the link is down: a steady dot next to
      // "Signal lost" reads as a stopped clock, which is the truth.
      opacity: widget.active
          ? Tween<double>(begin: 0.35, end: 1).animate(_controller)
          : const AlwaysStoppedAnimation(1),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.cameraId, required this.progress});

  final int cameraId;
  final SurveyProgress progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MjpegView(
              // Lower fps than the dedicated feed page: this screen is about
              // the CNN's verdict, and the picture is context for it.
              streamUrl:
                  '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/stream'
                  '?fps=8&width=720',
              fallbackFrameUrl:
                  '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/frame'
                  '?width=720',
              fit: BoxFit.cover,
            ),
            if (progress.signalLost)
              Container(
                color: AppColors.dark900.withOpacity(0.55),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off_outlined,
                      color: AppColors.light100,
                      size: 28,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Signal lost',
                      style: AppTextStyle.textSmSemibold.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the CNN made of the frame under the camera a second ago.
class _LatestVerdict extends StatelessWidget {
  const _LatestVerdict({required this.progress, required this.run});

  final SurveyProgress progress;
  final SurveyRun run;

  static const Map<String, Color> _severityColors = {
    'high': AppColors.themeError,
    'moderate': AppColors.themeWarning,
    'low': Color(0xFFE7B10A),
    'none': AppColors.themeSuccess,
  };

  @override
  Widget build(BuildContext context) {
    // Nothing scanned yet, or a multispectral-only pass which has no feed to
    // scan at all. Two different sentences, because they are two different
    // situations and only one of them will change on its own.
    if (progress.scanned == 0) {
      return _Banner(
        icon: run.cameraMode.usesRgb ? Icons.hourglass_empty : Icons.info_outline,
        color: AppColors.dark300,
        text: run.cameraMode.usesRgb
            ? 'Waiting for the first frame off the camera. This takes a few '
                'seconds after take-off.'
            : 'This is a multispectral-only pass — there is no video feed to '
                'scan. Trigger a shot over each part of the block; the zone '
                'map is built when you end the pass.',
      );
    }

    final severity = progress.latestSeverity ?? 'none';
    final color = _severityColors[severity] ?? AppColors.dark300;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'UNDER THE CAMERA NOW',
            style: AppTextStyle.textXsSemibold.copyWith(
              color: AppColors.dark100,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (run.detectionTarget != DetectionTarget.weed) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress.latestCondition ?? 'No disease detected',
                    style: AppTextStyle.textLgSemibold.copyWith(color: color),
                  ),
                ),
                if (progress.latestConfidence != null)
                  Text(
                    '${(progress.latestConfidence! * 100).round()}%',
                    style: AppTextStyle.textSmSemibold.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Severity: $severity',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ],
          if (run.detectionTarget != DetectionTarget.disease) ...[
            if (run.detectionTarget == DetectionTarget.both)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1, color: AppColors.light500),
              ),
            Row(
              children: [
                const Icon(
                  Icons.grass_outlined,
                  size: 17,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    progress.latestWeedPercent == null
                        ? 'Weed cover: —'
                        : 'Weed cover: ${progress.latestWeedPercent}% of the ground',
                    style: AppTextStyle.textSmMedium,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                progress.hasFix ? Icons.place_outlined : Icons.gps_off,
                size: 14,
                color: progress.hasFix
                    ? AppColors.dark100
                    : AppColors.themeWarning,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  progress.hasFix
                      ? '${progress.lat!.toStringAsFixed(5)}, '
                          '${progress.lon!.toStringAsFixed(5)}'
                      // Without a fix the frames still count towards the health
                      // summary but cannot be put on a map or flown back to.
                      : 'No GPS fix — these frames cannot become spray targets',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: progress.hasFix
                        ? AppColors.dark100
                        : AppColors.themeWarning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RollingCard extends StatelessWidget {
  const _RollingCard({required this.progress});

  final SurveyProgress progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.timeline,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('The last few minutes', style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            progress.rollingSummary,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark500,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// The shutter, for the multispectral half of a run.
class _ShotCard extends StatelessWidget {
  const _ShotCard({required this.state});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Multispectral shot', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Fires every band camera at once, filed under this survey. The '
            'zone map is built from the last shot when you end the pass.',
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: state.isShooting
                  ? null
                  : () => context.read<SurveyCubit>().shoot(),
              icon: state.isShooting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera, size: 18),
              label: Text(
                state.isShooting ? 'Capturing…' : 'Capture now',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
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
