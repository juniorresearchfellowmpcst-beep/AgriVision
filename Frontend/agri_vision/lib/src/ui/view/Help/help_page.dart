import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/domain/entity/help_guide.dart';
import 'package:agri_vision/src/ui/handler/navigation_handler.dart';

/// "How do I use this?" — the screen that answers it.
///
/// Each guide opens to a numbered list of what to press, and ends with a
/// button that goes there. Reading about a screen without being taken to it
/// is one more thing for somebody to get lost in, and the people this is for
/// are standing in a field holding a phone in one hand.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key, this.openGuideId});

  /// Opens with one guide already expanded — used by the first-run card, which
  /// points at "start here".
  final String? openGuideId;

  static Future<void> open(BuildContext context, {String? guideId}) {
    return Navigator.of(
      context,
    ).pushNamed(AppRouterNames.help, arguments: guideId);
  }

  @override
  Widget build(BuildContext context) {
    // Follows the app's language the way every other screen does: the strings
    // come from the Localizations above this page, so switching to Hindi
    // rebuilds this with everything else.
    return Builder(
      builder: (context) {
        final language = context.l10n.language;
        final strings = helpStrings(language);
        final guides = helpGuides(language);

        return Scaffold(
          backgroundColor: AppColors.tertiary,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: AppColors.light100,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.title,
                  style: AppTextStyle.textLgSemibold.copyWith(
                    color: AppColors.light100,
                  ),
                ),
                Text(
                  strings.subtitle,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.light100.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          body: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: guides.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final guide = guides[index];
              return _GuideCard(
                guide: guide,
                strings: strings,
                // The first guide is the one somebody opening Help for the
                // first time wants; anything else they came looking for.
                startsOpen: openGuideId == null
                    ? index == 0
                    : guide.id == openGuideId,
              );
            },
          ),
        );
      },
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.guide,
    required this.strings,
    required this.startsOpen,
  });

  final HelpGuide guide;
  final HelpStrings strings;
  final bool startsOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // The default divider lines cut the card in two on either side of the
        // header, which reads as two cards.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: startsOpen,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          leading: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryFade,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(guide.icon, size: 20, color: AppColors.primary),
          ),
          title: Text(guide.title, style: AppTextStyle.textMdSemibold),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              guide.summary,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
          children: [
            if (guide.needsDrone) ...[
              _NeedsDrone(label: strings.needsDroneLabel),
              const SizedBox(height: AppSpacing.sm),
            ],
            for (var i = 0; i < guide.steps.length; i++)
              _StepRow(number: i + 1, step: guide.steps[i]),
            if (guide.target != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () => _go(context, guide.target!),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(guide.openLabel ?? strings.openDefault),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Take them there.
  ///
  /// Two of these are not pages: the map and the drone link are a tab of the
  /// home shell and a sheet, so "open" means something different for each.
  void _go(BuildContext context, HelpTarget target) {
    switch (target) {
      case HelpTarget.cropScan:
        Navigator.of(context).pushNamed(AppRouterNames.cropScan);
      case HelpTarget.survey:
        Navigator.of(context).pushNamed(AppRouterNames.survey);
      case HelpTarget.spray:
        Navigator.of(context).pushNamed(AppRouterNames.spray);
      case HelpTarget.capture:
        Navigator.of(context).pushNamed(AppRouterNames.capture);
      case HelpTarget.droneLink:
        DroneConnectSheet.show(context);
      case HelpTarget.missionMap:
        // Read the cubit before popping: after popUntil this context is on its
        // way out, and looking anything up through it is a race.
        final navigation = context.read<BottomNavBarCubit>();
        Navigator.of(context).popUntil((route) => route.isFirst);
        navigation.selectMenu(Menu.maps);
    }
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.step});

  final int number;
  final HelpStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.text,
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.dark700,
                    height: 1.45,
                  ),
                ),
                if (step.note != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: AppColors.themeWarning,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          step.note!,
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark300,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedsDrone extends StatelessWidget {
  const _NeedsDrone({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: AppColors.themeWarning.withOpacity(0.14),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flight_outlined,
              size: 13,
              color: AppColors.themeWarning,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.dark500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
