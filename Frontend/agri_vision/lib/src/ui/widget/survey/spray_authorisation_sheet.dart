import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/spray_prescription.dart';
import 'package:agri_vision/src/domain/entity/survey_entity.dart';
import 'package:agri_vision/src/domain/entity/treatment_entity.dart';

/// What the farmer confirms before a valve opens over their field.
///
/// This sheet is deliberately the slowest screen in the app. Everything before
/// it is analysis and can be re-run; this is where it becomes chemical on a
/// crop, and the three things it asks for are three different mistakes:
///
///   1. **The tank is filled** — a statement about the aircraft. Without it
///      the drone flies the entire prescription pumping air, and the operator
///      finds out afterwards.
///   2. **Spraying is authorised, by a named person** — a statement by the
///      farmer. It is recorded with the run, because a chemical application is
///      a record somebody may need later.
///   3. **Launch now** — the field being clear is not something the app can
///      check, so the last switch is left to the person who can see it.
class SprayAuthorisationSheet extends StatefulWidget {
  const SprayAuthorisationSheet({
    required this.summary,
    required this.option,
    super.key,
  });

  final SurveySummary summary;
  final SprayOption option;

  /// Returns null if the farmer backs out.
  static Future<SprayAuthorisation?> show(
    BuildContext context, {
    required SurveySummary summary,
    required SprayOption option,
  }) {
    return showModalBottomSheet<SprayAuthorisation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SprayAuthorisationSheet(summary: summary, option: option),
    );
  }

  @override
  State<SprayAuthorisationSheet> createState() =>
      _SprayAuthorisationSheetState();
}

/// What the farmer agreed to.
class SprayAuthorisation {
  const SprayAuthorisation({
    required this.litres,
    required this.product,
    required this.authorisedBy,
    required this.startNow,
  });

  final double? litres;
  final String? product;
  final String authorisedBy;
  final bool startNow;
}

class _SprayAuthorisationSheetState extends State<SprayAuthorisationSheet> {
  final _litresController = TextEditingController();
  final _nameController = TextEditingController();

  bool _tankFilled = false;
  bool _understood = false;
  bool _startNow = true;

  TankPass? get _firstPass =>
      widget.summary.tankPlan.passes.isEmpty
          ? null
          : widget.summary.tankPlan.passes.first;

  @override
  void dispose() {
    _litresController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _canAuthorise =>
      _tankFilled && _understood && _nameController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final plan = widget.summary.tankPlan;
    final load = _firstPass?.load;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.tertiary,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.light700,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(
                      'Before the drone sprays',
                      style: AppTextStyle.textXlBold,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'The aircraft will fly the map and open the valve over '
                      '${widget.option.treatedPercent}% of the block. Nothing '
                      'below is optional.',
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.dark300,
                        height: 1.45,
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    _StepCard(
                      step: 1,
                      title: 'Fill the tank',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (load != null) ...[
                            _MixLine(
                              label: 'Product',
                              value: load.name,
                            ),
                            _MixLine(
                              label: 'Dose',
                              value: load.doseLine,
                            ),
                            if (load.phiDays != null)
                              _MixLine(
                                label: 'Do not harvest for',
                                value: '${load.phiDays} days after spraying',
                                warning: true,
                              ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          // Several tanks means several flights. Saying it here
                          // stops the farmer mixing everything into one load
                          // because the app implied one trip would do.
                          if (plan.needsSeparatePasses)
                            Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                              padding: const EdgeInsets.all(AppSpacing.sm + 2),
                              decoration: BoxDecoration(
                                color: AppColors.themeWarning.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                'This survey needs ${plan.passCount} separate '
                                'tanks. Do not mix them — fly this one first, '
                                'then refill.',
                                style: AppTextStyle.textXsSemibold.copyWith(
                                  color: AppColors.dark500,
                                ),
                              ),
                            ),
                          TextField(
                            controller: _litresController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Litres in the tank (optional)',
                              hintText: widget.option.chemicalL != null
                                  ? 'This run needs about '
                                      '${widget.option.chemicalL!.toStringAsFixed(1)} L'
                                  : null,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          CheckboxListTile(
                            value: _tankFilled,
                            onChanged: (value) =>
                                setState(() => _tankFilled = value ?? false),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.primary,
                            title: Text(
                              'The tank is filled and the nozzles are clear',
                              style: AppTextStyle.textSmMedium,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),
                    _StepCard(
                      step: 2,
                      title: 'Give permission',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Authorised by',
                              hintText: 'Who is approving this spray',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Recorded with the flight. A chemical application '
                            'is a record somebody may need later.',
                            style: AppTextStyle.textXsRegular.copyWith(
                              color: AppColors.dark300,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          CheckboxListTile(
                            value: _understood,
                            onChanged: (value) =>
                                setState(() => _understood = value ?? false),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.primary,
                            title: Text(
                              'I have checked the diagnosis on the ground and '
                              'read the product label',
                              style: AppTextStyle.textSmMedium,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),
                    _StepCard(
                      step: 3,
                      title: 'Launch',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            value: _startNow,
                            onChanged: (value) =>
                                setState(() => _startNow = value),
                            contentPadding: EdgeInsets.zero,
                            activeColor: AppColors.primary,
                            title: Text(
                              'Start spraying now',
                              style: AppTextStyle.textSmMedium,
                            ),
                            subtitle: Text(
                              _startNow
                                  ? 'The aircraft takes off as soon as the '
                                      'mission is uploaded.'
                                  : 'The mission is loaded onto the aircraft '
                                      'and waits. Launch it from the live '
                                      'screen when the field is clear.',
                              style: AppTextStyle.textXsRegular.copyWith(
                                color: AppColors.dark300,
                              ),
                            ),
                          ),
                          if (_startNow)
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.sm + 2),
                              decoration: BoxDecoration(
                                color: AppColors.themeError.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: AppColors.themeError,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      'Check that nobody is in the field or '
                                      'downwind of it. The app cannot see that '
                                      'for you.',
                                      style: AppTextStyle.textXsSemibold.copyWith(
                                        color: AppColors.dark500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xxl),
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
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: const Text('Not yet'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _canAuthorise ? _submit : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _startNow
                                ? AppColors.themeError
                                : AppColors.primary,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          icon: Icon(
                            _startNow ? Icons.flight_takeoff : Icons.upload,
                            size: 18,
                          ),
                          label: Text(
                            _startNow ? 'Authorise & spray' : 'Load onto drone',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      SprayAuthorisation(
        litres: double.tryParse(_litresController.text.trim()),
        product: _firstPass?.load?.name,
        authorisedBy: _nameController.text.trim(),
        startNow: _startNow,
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.child,
  });

  final int step;
  final String title;
  final Widget child;

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
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$step',
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.light100,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _MixLine extends StatelessWidget {
  const _MixLine({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark100,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyle.textSmSemibold.copyWith(
                color: warning ? AppColors.themeWarning : AppColors.dark700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
