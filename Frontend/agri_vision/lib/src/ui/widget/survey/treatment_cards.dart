import 'package:flutter/material.dart';

import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/survey_entity.dart';
import 'package:agri_vision/src/domain/entity/treatment_entity.dart';

/// Colours for how soon something has to happen.
const Map<String, Color> _urgencyColors = {
  'urgent': AppColors.themeError,
  'soon': AppColors.themeWarning,
  'routine': AppColors.dark300,
};

/// One product, as a dealer would need it written down.
///
/// Named by active ingredient and formulation rather than brand, because that
/// is what the label says and what a dealer can match — brand names change
/// district to district.
class ProductTile extends StatelessWidget {
  const ProductTile({required this.product, this.dense = false, super.key});

  final SprayProduct product;
  final bool dense;

  static const Map<String, ({IconData icon, Color color, String label})> _kinds = {
    'fungicide': (icon: Icons.coronavirus_outlined, color: Color(0xFF8E6FD8), label: 'Fungicide'),
    'insecticide': (icon: Icons.bug_report_outlined, color: Color(0xFFE07B39), label: 'Insecticide'),
    'herbicide': (icon: Icons.grass_outlined, color: AppColors.primary, label: 'Herbicide'),
    'bactericide': (icon: Icons.science_outlined, color: Color(0xFF2E86DE), label: 'Bactericide'),
    'biological': (icon: Icons.eco_outlined, color: AppColors.themeSuccess, label: 'Biological'),
    'nutrient': (icon: Icons.water_drop_outlined, color: Color(0xFF2E86DE), label: 'Nutrient'),
  };

  @override
  Widget build(BuildContext context) {
    final kind = _kinds[product.category] ??
        (icon: Icons.science_outlined, color: AppColors.dark300, label: product.category);

    return Container(
      padding: EdgeInsets.all(dense ? AppSpacing.sm + 2 : AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.light300,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(kind.icon, size: 17, color: kind.color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  product.name,
                  style: AppTextStyle.textSmSemibold,
                ),
              ),
              // A seed dressing or a soil drench is not a spray. Flying one
              // would be a wasted tank, so it is labelled, not filtered out.
              if (!product.droneReady)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.themeWarning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    'Not a spray',
                    style: AppTextStyle.textXsSemibold.copyWith(
                      color: AppColors.themeWarning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(Icons.opacity, size: 13, color: AppColors.dark100),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  product.doseLine,
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.dark700,
                  ),
                ),
              ),
            ],
          ),
          if (product.timing.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.schedule, size: 13, color: AppColors.dark100),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    product.timing,
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (product.note.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              product.note,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (product.phiDays != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(
                  Icons.event_busy_outlined,
                  size: 13,
                  color: AppColors.themeWarning,
                ),
                const SizedBox(width: 4),
                Text(
                  'Do not harvest for ${product.phiDays} days after spraying',
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.themeWarning,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// What to treat one detected condition with.
class TreatmentCard extends StatelessWidget {
  const TreatmentCard({
    required this.title,
    required this.treatment,
    this.subtitle,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Treatment treatment;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final urgencyColor =
        _urgencyColors[treatment.urgency] ?? AppColors.dark300;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // The default divider lines make a list of these read as a table.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: 2,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md + 2,
            0,
            AppSpacing.md + 2,
            AppSpacing.md + 2,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(title, style: AppTextStyle.textMdSemibold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: urgencyColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  treatment.urgency,
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: urgencyColor,
                  ),
                ),
              ),
            ],
          ),
          subtitle: subtitle == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
                ),
          children: [
            if (treatment.summary.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  treatment.summary,
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.dark500,
                    height: 1.45,
                  ),
                ),
              ),

            // The distinction the whole card exists to make: a virus, a
            // seed-borne disease and a soil wilt have no spray behind them,
            // and offering one would sell a flight that cannot work.
            if (!treatment.sprayable) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                  color: AppColors.themeWarning.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.block,
                      size: 15,
                      color: AppColors.themeWarning,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'No spray will fix this. Do the steps below instead.',
                        style: AppTextStyle.textXsSemibold.copyWith(
                          color: AppColors.dark500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (treatment.products.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  treatment.sprayable ? 'What to spray' : 'What to apply',
                  style: AppTextStyle.textSmSemibold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final product in treatment.products)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ProductTile(product: product),
                ),
            ],

            if (treatment.cultural.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Also do this',
                  style: AppTextStyle.textSmSemibold,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final step in treatment.cultural)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: AppTextStyle.textSmRegular.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          step,
                          style: AppTextStyle.textSmRegular.copyWith(
                            color: AppColors.dark500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            if (treatment.disclaimer.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                treatment.disclaimer,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark100,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What goes in the tank, grouped into loads.
///
/// The load-bearing idea here is that products from different groups cannot
/// share a tank. A survey that finds a fungal disease, an insect and heavy
/// weeds needs three flights, and the card says so instead of implying one
/// will do.
class TankPlanCard extends StatelessWidget {
  const TankPlanCard({required this.plan, super.key});

  final TankPlan plan;

  @override
  Widget build(BuildContext context) {
    if (plan.passes.isEmpty && plan.notSprayable.isEmpty) {
      return const SizedBox.shrink();
    }

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
                Icons.local_drink_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'What to put in the tank',
                  style: AppTextStyle.textMdSemibold,
                ),
              ),
              if (plan.passCount > 0)
                Text(
                  plan.passCount == 1 ? '1 tank' : '${plan.passCount} tanks',
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          if (plan.note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              plan.note,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
                height: 1.4,
              ),
            ),
          ],

          for (final pass in plan.passes) ...[
            const SizedBox(height: AppSpacing.md),
            _PassBlock(pass: pass, showNumber: plan.passCount > 1),
          ],

          if (plan.notSprayable.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Cannot be sprayed',
              style: AppTextStyle.textSmSemibold.copyWith(
                color: AppColors.themeWarning,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final blocked in plan.notSprayable)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      blocked.condition,
                      style: AppTextStyle.textSmSemibold,
                    ),
                    Text(
                      blocked.why,
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: AppColors.dark300,
                        height: 1.4,
                      ),
                    ),
                    for (final step in blocked.instead)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, left: AppSpacing.sm),
                        child: Text(
                          '• $step',
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],

          if (plan.disclaimer.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              plan.disclaimer,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark100,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PassBlock extends StatelessWidget {
  const _PassBlock({required this.pass, required this.showNumber});

  final TankPass pass;
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (showNumber)
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${pass.pass}',
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.light100,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                pass.tankName.isEmpty ? 'Tank' : pass.tankName,
                style: AppTextStyle.textSmSemibold,
              ),
            ),
          ],
        ),
        if (pass.targets.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              left: showNumber ? 28 : 0,
              top: 2,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              'For: ${pass.targets.join(', ')}',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
        if (pass.load != null)
          Padding(
            padding: EdgeInsets.only(left: showNumber ? 28 : 0),
            child: ProductTile(product: pass.load!),
          ),
        // Alternates are for the *next* spray, to rotate the chemical group.
        // Putting them all in one load is how a tank ends up unsprayable.
        if (pass.alternates.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: showNumber ? 28 : 0, top: AppSpacing.xs),
            child: Text(
              'Rotate to next time: '
              '${pass.alternates.map((a) => a.name).join(', ')}',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark100,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }
}

/// The action plan: what to do, worst first.
///
/// Rows carrying a product are the step that used to be missing between "you
/// have rust" and a flight — the app used to stop at agronomy advice.
class ActionPlanCard extends StatelessWidget {
  const ActionPlanCard({required this.actions, super.key});

  final List<SurveyAction> actions;

  static const Map<String, ({IconData icon, Color color})> _categories = {
    'spray': (icon: Icons.water_drop_outlined, color: Color(0xFF2E86DE)),
    'no_spray': (icon: Icons.block, color: AppColors.themeWarning),
    'disease': (icon: Icons.coronavirus_outlined, color: Color(0xFF8E6FD8)),
    'weed': (icon: Icons.grass_outlined, color: AppColors.primary),
    'monitoring': (icon: Icons.visibility_outlined, color: AppColors.dark300),
    'context': (icon: Icons.info_outline, color: AppColors.dark300),
  };

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

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
                Icons.checklist_rtl,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Action plan', style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < actions.length; i++) ...[
            _ActionRow(
              action: actions[i],
              meta: _categories[actions[i].category] ??
                  (icon: Icons.chevron_right, color: AppColors.dark300),
            ),
            if (i < actions.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1, color: AppColors.light500),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.meta});

  final SurveyAction action;
  final ({IconData icon, Color color}) meta;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: meta.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(meta.icon, size: 15, color: meta.color),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(action.title, style: AppTextStyle.textSmSemibold),
              if (action.detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  action.detail,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                    height: 1.4,
                  ),
                ),
              ],
              for (final step in action.instead)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '• $step',
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.dark500,
                    ),
                  ),
                ),
              if (action.product != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ProductTile(product: action.product!, dense: true),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
