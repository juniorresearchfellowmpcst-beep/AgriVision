import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/widget/survey/treatment_cards.dart';

/// What the phone found, and what to do about it.
///
/// Reads as one answer: here is what it is, here is how to treat it, and if
/// that is not enough — Know More, which sends this exact photo and this exact
/// diagnosis to the crop advisor so the farmer can keep asking.
///
/// No weed section. A close-up of one plant cannot honestly say what share of
/// a field is weedy; that is the drone's job.
class CropScanResultPage extends StatelessWidget {
  const CropScanResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<CropCubit, CropState>(
      builder: (context, state) {
        final result = state.result;
        if (result == null) {
          return Scaffold(
            backgroundColor: AppColors.tertiary,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final scan = result.scan;

        return Scaffold(
          backgroundColor: AppColors.tertiary,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: AppColors.light100,
            elevation: 0,
            title: Text(
              l10n.scanResult,
              style: AppTextStyle.textLgSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
            actions: [
              IconButton(
                tooltip: l10n.scanAgain,
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
            child: Center(
              child: ConstrainedBox(
                // Caps the column on tablets and landscape phones, where a
                // full-width line of body text is close to unreadable.
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (state.image != null) _Photo(bytes: state.image!.bytes),

                    const SizedBox(height: AppSpacing.lg),
                    _Verdict(result: result),

                    // Know More sits directly under the verdict, before the
                    // treatment detail: a farmer who does not recognise the
                    // name needs the way to ask about it before they need the
                    // dose table.
                    if (result.advisorAvailable) ...[
                      const SizedBox(height: AppSpacing.lg),
                      KnowMoreCard(
                        // The photo itself, so the advisor looks at the same
                        // plant the CNN did.
                        image: state.image,
                        scanId: scan.scanId,
                        subject: scan.isHealthy
                            ? (scan.cropName ?? '')
                            : scan.disease.name,
                        diagnosis: {
                          'crop': scan.crop,
                          'crop_name': scan.cropName,
                          'disease': {
                            'name': scan.disease.name,
                            'confidence': scan.disease.confidence,
                            'source': scan.disease.source,
                          },
                          'severity': {'level': scan.severityLevel},
                        },
                      ),
                    ],

                    if (result.treatment.disease != null &&
                        !result.treatment.disease!.isEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      TreatmentCard(
                        title: scan.disease.name,
                        subtitle: l10n.treatment,
                        treatment: result.treatment.disease!,
                        initiallyExpanded: true,
                      ),
                    ],

                    if (scan.actions.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ActionsCard(actions: scan.actions),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      scan.disclaimer.isEmpty
                          ? l10n.disclaimerShort
                          : scan.disclaimer,
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: AppColors.dark100,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
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
  const _Verdict({required this.result});

  final CropScanResult result;

  static Map<String, Color> _severityColors = {
    'high': AppColors.themeError,
    'moderate': AppColors.themeWarning,
    'low': Color(0xFFE7B10A),
    'none': AppColors.themeSuccess,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scan = result.scan;
    final healthy = scan.isHealthy;
    final color = healthy
        ? AppColors.themeSuccess
        : (_severityColors[scan.severityLevel] ?? AppColors.themeWarning);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.35)),
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  healthy
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      healthy ? l10n.healthyCrop : scan.disease.name,
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
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Chip(
                label: l10n.severity,
                value: l10n.severityLevel(scan.severityLevel),
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              _Chip(
                label: l10n.confidence,
                value: '${(scan.disease.confidence * 100).round()}%',
                color: AppColors.dark300,
              ),
              const SizedBox(width: AppSpacing.sm),
              // Whether a trained model or the on-device rules answered is not
              // trivia: the two are not equally trustworthy.
              _Chip(
                label: l10n.engine,
                value: scan.disease.source == 'model'
                    ? l10n.cnnModel
                    : l10n.onDeviceRules,
                color: scan.disease.source == 'model'
                    ? AppColors.primary
                    : AppColors.dark300,
              ),
            ],
          ),
          if (scan.disease.symptoms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l10n.whatToLookFor, style: AppTextStyle.textSmSemibold),
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
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            // Long values ("On-device rules", "फोन के नियम") would otherwise
            // wrap into three lines and misalign the row of chips.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: AppTextStyle.textXsSemibold.copyWith(color: color),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark100,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.whatToDo, style: AppTextStyle.textMdSemibold),
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
