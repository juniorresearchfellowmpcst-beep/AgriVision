import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/survey/survey_cubit.dart';
import 'package:agri_vision/src/ui/widget/survey/crop_health_card.dart';
import 'package:agri_vision/src/ui/widget/survey/spray_authorisation_sheet.dart';
import 'package:agri_vision/src/ui/widget/survey/treatment_cards.dart';
import 'package:agri_vision/src/ui/widget/survey/treatment_map_card.dart';

/// After the pass: what the field is like, and what to do about it.
///
/// Read top to bottom this is one argument: here is how the crop is, here is
/// what is wrong with it, here is what to put in the tank, here is the map of
/// where it goes, now confirm and fly. Each step is allowed to end the
/// argument — a block with nothing sprayable never reaches the spray button,
/// and it says why rather than showing a disabled control.
class SurveySummaryView extends StatelessWidget {
  const SurveySummaryView({required this.state, super.key});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    final summary = state.summary!;
    final map = summary.treatmentMap;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              CropHealthCard(
                health: summary.health,
                fieldName: summary.fieldName,
              ),

              const SizedBox(height: AppSpacing.lg),
              _ScanFacts(state: state),

              if (summary.advisorAvailable) ...[
                const SizedBox(height: AppSpacing.lg),
                _knowMore(summary),
              ],

              if (summary.actionPlan.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                ActionPlanCard(actions: summary.actionPlan),
              ],

              if (summary.treatments.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'What was found, and what treats it',
                    style: AppTextStyle.textMdSemibold,
                  ),
                ),
                for (final found in summary.treatments)
                  TreatmentCard(
                    title: found.condition,
                    subtitle: 'In ${found.sharePercent}% of frames · '
                        'worst severity ${found.worstSeverity}',
                    treatment: found.treatment,
                    // Open the worst one: it is what the operator came for.
                    initiallyExpanded: found == summary.treatments.first,
                  ),
              ],

              if (summary.tankPlan.passes.isNotEmpty ||
                  summary.tankPlan.notSprayable.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                TankPlanCard(plan: summary.tankPlan),
              ],

              if (map != null) ...[
                const SizedBox(height: AppSpacing.lg),
                TreatmentMapCard(
                  map: map,
                  selectedOption: state.effectiveOption,
                  onSelectOption: context.read<SurveyCubit>().selectOption,
                ),
              ],

              if (summary.notes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _NotesCard(notes: summary.notes),
              ],

              if (summary.disclaimer.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  summary.disclaimer,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark100,
                    height: 1.45,
                  ),
                ),
              ],

              const SizedBox(height: 90),
            ],
          ),
        ),
        _SprayBar(state: state),
      ],
    );
  }
}

/// The numbers behind the health score.
class _ScanFacts extends StatelessWidget {
  const _ScanFacts({required this.state});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    final summary = state.summary!;
    final scan = summary.scan;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('The pass', style: AppTextStyle.textMdSemibold),
              ),
              Text(
                '${summary.cameraMode.label} · ${summary.detectionTarget.label}',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (scan == null)
            Text(
              'No frames were scanned on this pass.',
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark300,
              ),
            )
          else ...[
            IntrinsicHeight(
              child: Row(
                children: [
                  _Fact(label: 'Frames', value: '${scan.frames}'),
                  _Fact(
                    label: 'Affected',
                    value: '${scan.diseasedFrames}/${scan.frames}',
                    highlight: scan.diseaseIncidence >= 0.4,
                  ),
                  _Fact(
                    label: 'Weed cover',
                    value: '${scan.weedPercent}%',
                    highlight: scan.weedLevel == 'high',
                  ),
                  _Fact(
                    label: 'Hotspots',
                    value: '${scan.hotspots.length}',
                    highlight: scan.hotspots.isNotEmpty,
                  ),
                ],
              ),
            ),
            if (scan.summary.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                scan.summary,
                style: AppTextStyle.textSmRegular.copyWith(
                  color: AppColors.dark500,
                  height: 1.45,
                ),
              ),
            ],
            if (scan.conditions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final condition in scan.conditions.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          condition.name,
                          style: AppTextStyle.textSmRegular,
                        ),
                      ),
                      Text(
                        '${(condition.frameShare * 100).round()}% of frames',
                        style: AppTextStyle.textXsSemibold.copyWith(
                          color: AppColors.dark300,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
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
            style: AppTextStyle.textLgSemibold.copyWith(
              color: highlight ? AppColors.themeWarning : AppColors.dark900,
            ),
          ),
          Text(
            label,
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark100),
          ),
        ],
      ),
    );
  }
}

/// The survey's "Know More", using the shared card with its own framing.
///
/// A survey report is about a whole block rather than one leaf, so the hint
/// differs — but the button, the language handling and the way the diagnosis
/// is packaged are the same ones every other screen uses.
Widget _knowMore(SurveySummary summary) {
  final dominant = summary.treatments.isEmpty ? null : summary.treatments.first;

  return KnowMoreCard(
    // No photo: a survey's evidence is hundreds of frames, not one picture.
    // The run id lets the server attach what it found instead.
    runId: summary.runId,
    subject: dominant?.condition ?? summary.fieldName ?? '',
    hint: dominant == null
        ? 'Ask the crop advisor about this block — what to watch for, whether '
              'to spray, what the weather is likely to do to it.'
        : 'Ask the crop advisor about ${dominant.condition} — how serious it '
              'is at this stage, whether it is safe to spray now, how to stop '
              'it spreading.',
    diagnosis: {
      'crop_name': summary.cropName,
      'field_name': summary.fieldName,
      if (dominant != null)
        'disease': {'name': dominant.condition, 'source': 'survey'},
      if (summary.scan != null)
        'weeds': {
          'pressure': {
            'level': summary.scan!.weedLevel,
            'percent': summary.scan!.weedPercent,
          },
        },
      if (summary.scan != null)
        'conditions': [
          for (final condition in summary.scan!.conditions)
            {'name': condition.name, 'frame_share': condition.frameShare},
        ],
    },
  );
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.light300,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Worth knowing about this report',
            style: AppTextStyle.textSmSemibold.copyWith(
              color: AppColors.dark500,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      note,
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: AppColors.dark300,
                        height: 1.45,
                      ),
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

/// The bar that turns a report into a spray, or explains why it cannot.
class _SprayBar extends StatelessWidget {
  const _SprayBar({required this.state});

  final SurveyState state;

  @override
  Widget build(BuildContext context) {
    final summary = state.summary!;
    final run = state.run;

    // Already sent to the aircraft. Nothing left to confirm.
    if (run != null && (run.isSpraying || run.sprayAuthorised)) {
      return _BottomBar(
        child: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.themeSuccess),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    run.isSpraying
                        ? 'Spraying — the drone is flying the map'
                        : 'Spray mission loaded onto the drone',
                    style: AppTextStyle.textSmSemibold,
                  ),
                  if (run.authorisedBy != null)
                    Text(
                      'Authorised by ${run.authorisedBy}'
                      '${run.tankLitres != null ? " · ${run.tankLitres!.toStringAsFixed(0)} L" : ""}',
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: AppColors.dark300,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // The three separate reasons a spray is not on offer. Each is worth its
    // own sentence: they call for completely different next steps.
    if (!summary.tankPlan.hasSomethingToSpray) {
      return _BottomBar(
        child: _Reason(
          icon: Icons.eco_outlined,
          color: AppColors.themeSuccess,
          text: summary.tankPlan.notSprayable.isEmpty
              ? 'Nothing here is worth loading a tank for. Re-fly in 7–10 days.'
              : 'What was found cannot be treated by spraying. The steps above '
                  'are the ones that will help.',
        ),
      );
    }
    if (summary.treatmentMap == null || !summary.treatmentMap!.isFlyable) {
      return _BottomBar(
        child: _Reason(
          icon: Icons.wrong_location_outlined,
          color: AppColors.themeWarning,
          text: 'There is something to spray, but no map to spray it on. '
              'Connect the flight link before the survey so frames are '
              'geotagged, then fly the block again.',
        ),
      );
    }

    final option = summary.treatmentMap!.targetedOptions.firstWhere(
      (o) => o.id == state.effectiveOption,
      orElse: () =>
          summary.treatmentMap!.recommendedOption ??
          summary.treatmentMap!.targetedOptions.first,
    );

    return _BottomBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Treats ${option.treatedPercent}% of the block · saves '
                  '${option.savingPercent}% of the chemical',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              onPressed: state.status == SurveyStatus.authorising
                  ? null
                  : () => _authorise(context, summary, option),
              icon: state.status == SurveyStatus.authorising
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.light100,
                      ),
                    )
                  : const Icon(Icons.water_drop_outlined),
              label: Text(
                'Fill the tank & spray',
                style: AppTextStyle.textLgSemibold.copyWith(
                  color: AppColors.light100,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _authorise(
    BuildContext context,
    SurveySummary summary,
    SprayOption option,
  ) async {
    final cubit = context.read<SurveyCubit>();
    final result = await SprayAuthorisationSheet.show(
      context,
      summary: summary,
      option: option,
    );
    if (result == null) return; // backed out — nothing recorded

    cubit
      ..selectOption(option.id)
      ..confirmTank(litres: result.litres, product: result.product);
    await cubit.authoriseSpray(
      authorisedBy: result.authorisedBy,
      start: result.startNow,
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.light500)),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark900.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark500,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
