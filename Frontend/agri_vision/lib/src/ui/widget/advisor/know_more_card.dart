import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/media_file.dart';
import 'package:agri_vision/src/ui/cubit/language/language_cubit.dart';
import 'package:agri_vision/src/ui/view/Advisor/advisor_page.dart';

/// "Know More" — hand this photo and this diagnosis to the crop advisor.
///
/// One widget rather than a copy per screen. Four screens now offer this
/// (phone crop scan, plant disease, weed & disease scan, survey report) and
/// the parts that must not drift between them are exactly the parts that are
/// easy to get subtly wrong in a copy:
///
///   * the photo travels with the request, so the advisor is looking at the
///     same plant the CNN was;
///   * the app's own diagnosis travels too, so the advisor builds on it rather
///     than quietly naming a different disease;
///   * the farmer's chosen language is read here, so no call site has to
///     remember to pass it.
///
/// Render it only when the server says the advisor is configured. A button
/// that answers 503 when tapped is worse than one that is absent — on a ground
/// station with no internet, which is the normal case for every other feature
/// in this app, absent is the honest state.
class KnowMoreCard extends StatelessWidget {
  const KnowMoreCard({
    required this.subject,
    this.image,
    this.diagnosis,
    this.frameId,
    this.scanId,
    this.diseaseScanId,
    this.runId,
    this.hint,
    super.key,
  });

  /// What the conversation is about — the disease name, or the block.
  final String subject;

  /// The photo the phone holds. Sent with the first question.
  ///
  /// Leave null and pass [frameId] instead for a picture the server already
  /// has: re-uploading it would push it back over the slowest link in the
  /// chain to reach something already at the other end of it.
  final MediaFile? image;

  /// The app's own verdict, sent with every question.
  final Map<String, dynamic>? diagnosis;

  /// Ids naming a stored frame or scan, so the server can attach what it
  /// already holds rather than having it re-described in the request.
  final int? frameId;
  final int? scanId;
  final int? diseaseScanId;
  final int? runId;

  /// Overrides the default one-liner where a screen needs different framing —
  /// a survey report is about a block, not about one leaf.
  final String? hint;

  /// The advisor's accent, distinct from the app's green: this is the one
  /// action that leaves the ground station, and it should not look like the
  /// local ones.
  static const Color accent = Color(0xFF8E6FD8);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = context.watch<LanguageCubit>().state.language;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(l10n.knowMore, style: AppTextStyle.textMdSemibold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint ?? l10n.knowMoreHint,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: () => AdvisorPage.open(
                context,
                image: image,
                frameId: frameId,
                scanId: scanId,
                diseaseScanId: diseaseScanId,
                runId: runId,
                subject: subject,
                language: language,
                context_: diagnosis,
              ),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: Text(
                l10n.knowMore,
                style: AppTextStyle.textMdSemibold.copyWith(
                  color: AppColors.light100,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
