import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/view/Advisor/advisor_page.dart';
import 'package:agri_vision/src/ui/widget/survey/treatment_cards.dart';

/// What the phone found, and what to do about it.
///
/// This screen deliberately ends differently from the survey report. A survey
/// finishes with "fill the tank and spray"; a phone photo cannot, because one
/// plant says nothing about where in the block the problem is. So the last
/// thing here is a route to the drone flow, not a spray button — and it says
/// why rather than showing a disabled control.
class CropScanResultPage extends StatelessWidget {
  const CropScanResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CropCubit, CropState>(
      builder: (context, state) {
        final result = state.result;
        if (result == null) {
          return const Scaffold(
            backgroundColor: AppColors.tertiary,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final scan = result.scan;
        final isHealthy = scan.isHealthy && !scan.weeds.needsAction;

        return Scaffold(
          backgroundColor: AppColors.tertiary,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: AppColors.light100,
            elevation: 0,
            title: Text(
              'Scan Result',
              style: AppTextStyle.textLgSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Scan again',
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  context.read<CropCubit>().clearResult();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (state.image != null) _Photo(bytes: state.image!.bytes),

                const SizedBox(height: AppSpacing.lg),
                _Verdict(result: result, isHealthy: isHealthy),

                if (result.mode != ScanMode.disease) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _WeedCard(result: result),
                ],

                if (scan.overlayUrl != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _Overlay(url: scan.overlayUrl!),
                ],

                if (result.advisorAvailable) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _AdvisorPrompt(state: state, result: result),
                ],

                if (result.treatment.disease != null &&
                    !result.treatment.disease!.isEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  TreatmentCard(
                    title: scan.disease.name,
                    subtitle: 'Treatment',
                    treatment: result.treatment.disease!,
                    initiallyExpanded: true,
                  ),
                ],

                if (result.treatment.weeds != null &&
                    !result.treatment.weeds!.isEmpty)
                  TreatmentCard(
                    title: 'Weeds',
                    subtitle: 'Herbicide options',
                    treatment: result.treatment.weeds!,
                    initiallyExpanded: result.mode == ScanMode.weed,
                  ),

                if (result.treatment.tankPlan.passes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TankPlanCard(plan: result.treatment.tankPlan),
                ],

                if (scan.actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ActionsCard(actions: scan.actions),
                ],

                const SizedBox(height: AppSpacing.lg),
                _DroneRoute(sprayNote: result.sprayNote),

                const SizedBox(height: AppSpacing.lg),
                Text(
                  scan.disclaimer,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark100,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.memory(bytes, fit: BoxFit.cover),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.result, required this.isHealthy});

  final CropScanResult result;
  final bool isHealthy;

  static const Map<String, Color> _severityColors = {
    'high': AppColors.themeError,
    'moderate': AppColors.themeWarning,
    'low': Color(0xFFE7B10A),
    'none': AppColors.themeSuccess,
  };

  @override
  Widget build(BuildContext context) {
    final scan = result.scan;
    final color = isHealthy
        ? AppColors.themeSuccess
        : (_severityColors[scan.severityLevel] ?? AppColors.themeWarning);

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
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  isHealthy ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // A weed-only scan never ran the disease CNN, so naming
                      // a disease here would be reporting a detector that did
                      // not run.
                      result.mode == ScanMode.weed
                          ? 'Weed check'
                          : scan.disease.name,
                      style: AppTextStyle.textLgSemibold.copyWith(color: color),
                    ),
                    if (scan.cropName != null)
                      Text(
                        scan.cropName!,
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: AppColors.dark300,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (result.mode != ScanMode.weed) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _Chip(
                  label: 'Severity',
                  value: scan.severityLevel,
                  color: color,
                ),
                const SizedBox(width: AppSpacing.sm),
                _Chip(
                  label: 'Confidence',
                  value: '${(scan.disease.confidence * 100).round()}%',
                  color: AppColors.dark300,
                ),
                const SizedBox(width: AppSpacing.sm),
                // Whether a trained model or the on-device rules answered is
                // not trivia: the two are not equally trustworthy.
                _Chip(
                  label: 'Engine',
                  value: scan.disease.source == 'model'
                      ? 'CNN model'
                      : 'On-device rules',
                  color: scan.disease.source == 'model'
                      ? AppColors.primary
                      : AppColors.dark300,
                ),
              ],
            ),
            if (scan.disease.symptoms.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('What to look for', style: AppTextStyle.textSmSemibold),
              const SizedBox(height: AppSpacing.xs),
              for (final symptom in scan.disease.symptoms.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• $symptom',
                    style: AppTextStyle.textSmRegular.copyWith(
                      color: AppColors.dark500,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
            if (scan.disease.note.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                scan.disease.note,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.themeWarning,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              style: AppTextStyle.textXsSemibold.copyWith(color: color),
            ),
            Text(
              label,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark100,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeedCard extends StatelessWidget {
  const _WeedCard({required this.result});

  final CropScanResult result;

  @override
  Widget build(BuildContext context) {
    final weeds = result.scan.weeds;

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
                Icons.grass_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Weeds', style: AppTextStyle.textMdSemibold),
              ),
              Text(
                '${weeds.percent}% of the ground',
                style: AppTextStyle.textSmSemibold.copyWith(
                  color: weeds.needsAction
                      ? AppColors.themeWarning
                      : AppColors.themeSuccess,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            weeds.advice,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // How the weeds were told apart from the crop is what the number's
          // reliability rests on, so it is shown rather than hidden.
          Text(
            switch (weeds.method) {
              'inter-row' => 'Told apart by the crop rows — the most reliable '
                  'method, and it needs a sown crop in lines.',
              'appearance' => 'Told apart by colour and texture, because no row '
                  'structure was found. Less certain than row geometry.',
              'not_requested' => 'Weed detection was switched off for this scan.',
              _ => 'The weeds could not be reliably told apart from the crop in '
                  'this photo.',
            },
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
              height: 1.4,
            ),
          ),
          if (weeds.likelyWeeds.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Likely species here', style: AppTextStyle.textSmSemibold),
            const SizedBox(height: AppSpacing.xs),
            for (final weed in weeds.likelyWeeds.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${weed.name}'
                  '${weed.localName.isNotEmpty ? " (${weed.localName})" : ""}',
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.dark500,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weed overlay', style: AppTextStyle.textSmSemibold),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                height: 90,
                color: AppColors.light300,
                alignment: Alignment.center,
                child: Text(
                  'Overlay unavailable',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Green = crop, red = weed.',
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvisorPrompt extends StatelessWidget {
  const _AdvisorPrompt({required this.state, required this.result});

  final CropState state;
  final CropScanResult result;

  @override
  Widget build(BuildContext context) {
    final scan = result.scan;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF8E6FD8),
        ),
        onPressed: () => AdvisorPage.open(
          context,
          // The photo goes up with the first question so the advisor is
          // looking at the same plant the CNN was.
          image: state.image,
          scanId: scan.scanId,
          subject: result.mode == ScanMode.weed
              ? 'the weeds in this photo'
              : scan.disease.name,
          context_: {
            'crop': scan.crop,
            'crop_name': scan.cropName,
            'disease': {
              'name': scan.disease.name,
              'confidence': scan.disease.confidence,
              'source': scan.disease.source,
            },
            'severity': {'level': scan.severityLevel},
            'weeds': {
              'pressure': {
                'level': scan.weeds.level,
                'percent': scan.weeds.percent,
              },
            },
          },
        ),
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('More information'),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.actions});

  final List<ScanAction> actions;

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
          Text('What to do', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.md),
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.title, style: AppTextStyle.textSmSemibold),
                  if (action.detail.isNotEmpty)
                    Text(
                      action.detail,
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: AppColors.dark300,
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

/// Where a phone scan stops, and what picks it up.
class _DroneRoute extends StatelessWidget {
  const _DroneRoute({required this.sprayNote});

  final String sprayNote;

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
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 17,
                color: AppColors.dark300,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  sprayNote.isEmpty
                      ? 'A phone photo diagnoses a plant; it cannot say where '
                          'in the block the problem is.'
                      : sprayNote,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context)
                  .pushNamed(AppRouterNames.survey),
              icon: const Icon(Icons.flight_takeoff, size: 18),
              label: const Text('Fly a survey of this block'),
            ),
          ),
        ],
      ),
    );
  }
}
