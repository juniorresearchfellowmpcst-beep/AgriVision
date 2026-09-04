import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/ui/cubit/language/language_cubit.dart';

/// The language picker.
///
/// Each option leads with its own script — somebody looking for Hindi is
/// looking for "हिन्दी", not for the word "Hindi" — with the English name
/// underneath so an operator setting a device up for a farmer can also find it.
///
/// The note at the bottom is the honest part: this changes the crop-scanning
/// screens and the language the advisor answers in, and leaves the flight
/// screens in English. Saying so beats letting somebody switch to Hindi and
/// then wonder why the mission planner did not follow.
class LanguageSheet extends StatelessWidget {
  const LanguageSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: context.read<LanguageCubit>(),
        child: const LanguageSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.light700,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              Text(l10n.chooseLanguage, style: AppTextStyle.textXlBold),
              const SizedBox(height: AppSpacing.lg),

              BlocBuilder<LanguageCubit, LanguageState>(
                builder: (context, state) {
                  return Column(
                    children: [
                      for (final language in AppLanguage.values)
                        _LanguageRow(
                          language: language,
                          selected: state.language == language,
                          onTap: () {
                            context.read<LanguageCubit>().select(language);
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.languageNote,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surface,
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
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language.nativeName,
                        style: AppTextStyle.textLgSemibold,
                      ),
                      Text(
                        language.englishName,
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: AppColors.dark300,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
