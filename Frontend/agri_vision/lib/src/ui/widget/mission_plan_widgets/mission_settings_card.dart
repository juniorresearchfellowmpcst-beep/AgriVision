import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Expandable settings card with a leading icon, title, value summary,
/// and collapsible detail content — used for Altitude, Speed,
/// Spray Volume, etc. in the bottom sheet.
class MissionSettingsCard extends StatefulWidget {
  const MissionSettingsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.child,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final String summary;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<MissionSettingsCard> createState() => _MissionSettingsCardState();
}

class _MissionSettingsCardState extends State<MissionSettingsCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (_expanded) _ctrl.value = 1;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark900.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // header row
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryFade,
                      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: AppTextStyle.textSmSemibold),
                        Text(
                          widget.summary,
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5).animate(_expandAnim),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.dark300,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // expandable content
          SizeTransition(
            sizeFactor: _expandAnim,
            child: Column(
              children: [
                const Divider(
                  height: 1,
                  color: AppColors.light500,
                  indent: AppSpacing.lg,
                  endIndent: AppSpacing.lg,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: widget.child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stepper row widget (used inside MissionSettingsCard content) ────────────

class SettingStepperRow extends StatelessWidget {
  const SettingStepperRow({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.onDecrement,
    required this.onIncrement,
    this.min,
    this.max,
  });

  final String label;
  final num value;
  final String unit;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final num? min;
  final num? max;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
              Row(
                children: [
                  Text(
                    value is double ? value.toStringAsFixed(1) : '$value',
                    style: AppTextStyle.textLgBold.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    unit,
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove,
              onTap: (min == null || value > min!) ? onDecrement : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            _StepButton(
              icon: Icons.add,
              onTap: (max == null || value < max!) ? onIncrement : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: onTap != null ? AppColors.primaryFade : AppColors.light500,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: onTap != null
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.light700,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.primary : AppColors.dark100,
        ),
      ),
    );
  }
}
