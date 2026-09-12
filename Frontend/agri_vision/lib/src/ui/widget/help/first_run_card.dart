import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agri_vision/src/core/constants/strorage_constants.dart';
import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/help_guide.dart';
import 'package:agri_vision/src/ui/view/Help/help_page.dart';

/// The first thing a new operator sees on the home screen.
///
/// A drone app opens on a dashboard full of things that all assume you already
/// know the order to do them in. This says there is an order, and offers to
/// walk through it — once. It is dismissed for good on the first tap of either
/// button, because a permanent banner on the home screen is just clutter for
/// everybody who has flown before.
class FirstRunHelpCard extends StatefulWidget {
  const FirstRunHelpCard({super.key});

  @override
  State<FirstRunHelpCard> createState() => _FirstRunHelpCardState();
}

class _FirstRunHelpCardState extends State<FirstRunHelpCard> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(StorageConstants.helpTourSeen) ?? false;
      if (mounted) setState(() => _show = !seen);
    } catch (_) {
      // No preferences (a fresh test binding, a locked-down device): show
      // nothing rather than show it again on every launch.
    }
  }

  Future<void> _dismiss() async {
    if (mounted) setState(() => _show = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(StorageConstants.helpTourSeen, true);
    } catch (_) {
      // Worst case it comes back next launch, which is not worth an error.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();

    final strings = helpStrings(context.l10n.language);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.primaryFade,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.primary.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    strings.firstTimeTitle,
                    style: AppTextStyle.textMdSemibold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              strings.firstTimeBody,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Wrapped, not a Row: "तरीका दिखाएँ" beside "अभी नहीं" is wider
            // than a narrow phone in Hindi, and a dismissible card that
            // overflows its own screen is a poor first impression.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                TextButton(
                  onPressed: _dismiss,
                  child: Text(
                    strings.notNow,
                    style: AppTextStyle.textSmSemibold.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () {
                    _dismiss();
                    HelpPage.open(context, guideId: 'start-here');
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(strings.showMe),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
