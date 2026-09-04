import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/spray/spray_cubit.dart';

/// The pesticide-saving decision screen.
///
/// A multispectral capture is clustered with K-means into severe / moderate /
/// healthy zones, and the operator is shown what each spray choice would cost
/// against a blanket pass over the same block. Nothing reaches the aircraft
/// until they pick one and confirm — and the confirmation says plainly that
/// what follows opens a valve over a field.
class SprayPrescriptionPage extends StatefulWidget {
  const SprayPrescriptionPage({this.shotId, super.key});

  /// The capture to prescribe from. Null re-opens whatever is already loaded.
  final String? shotId;

  @override
  State<SprayPrescriptionPage> createState() => _SprayPrescriptionPageState();
}

class _SprayPrescriptionPageState extends State<SprayPrescriptionPage> {
  @override
  void initState() {
    super.initState();
    final cubit = context.read<SprayCubit>();
    cubit.loadHistory();
    if (widget.shotId != null && widget.shotId!.isNotEmpty) {
      cubit.prescribe(shotId: widget.shotId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.light100,
        elevation: 0,
        title: Text(
          'Targeted Spray',
          style: AppTextStyle.textLgSemibold.copyWith(color: AppColors.light100),
        ),
      ),
      body: SafeArea(
        top: false,
        child: BlocConsumer<SprayCubit, SprayState>(
          listenWhen: (a, b) => a.message != b.message && b.message.isNotEmpty,
          listener: (context, state) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          },
          builder: (context, state) {
            if (state.status == SprayStatus.prescribing) {
              return const _Busy(text: 'Clustering the capture…');
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (state.errorMessage.isNotEmpty) ...[
                  _ErrorBanner(message: state.errorMessage),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (!state.hasPrescription)
                  const _EmptyState()
                else ...[
                  _PrescriptionCard(prescription: state.prescription!),
                  const SizedBox(height: AppSpacing.lg),
                  _ZoneCard(prescription: state.prescription!),
                  const SizedBox(height: AppSpacing.lg),
                  _OptionsCard(state: state),
                  if (state.hasPlan) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _PlanCard(state: state),
                  ],
                ],
                if (state.history.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _HistoryCard(history: state.history),
                ],
                const SizedBox(height: 60),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Prescription summary ─────────────────────────────────────────────────────

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.prescription});

  final SprayPrescription prescription;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.scatter_plot_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  prescription.fieldName?.isNotEmpty == true
                      ? prescription.fieldName!
                      : 'Spray prescription',
                  style: AppTextStyle.textMdSemibold,
                ),
              ),
              _Pill(
                text: '${prescription.k}-means · ${prescription.indexName}',
                color: AppColors.primary,
              ),
            ],
          ),
          if (prescription.prescriptionMapUrl != null) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.network(
                prescription.prescriptionMapUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: AppColors.light500,
                  alignment: Alignment.center,
                  child: const Text('Prescription map unavailable'),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Red = severe, amber = moderate, green = healthy. Outlined boxes '
              'are the patches a boom can actually target.',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ],
          // Everything the operator should know before trusting the numbers.
          ...prescription.notes.map(
            (note) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _Note(text: note),
            ),
          ),
          if (!prescription.calibrated)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: _Note(
                text: 'Uncalibrated capture — the zones rank this field against '
                    'itself, which is what a prescription needs, but the index '
                    'values are not comparable with another field.',
              ),
            ),
        ],
      ),
    );
  }
}

// ── Zones ────────────────────────────────────────────────────────────────────

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({required this.prescription});

  final SprayPrescription prescription;

  static const _labels = {
    'severe': 'Severely affected',
    'moderate': 'Moderately affected',
    'healthy': 'Healthy',
  };
  static final _colors = {
    'severe': AppColors.themeError,
    'moderate': AppColors.themeWarning,
    'healthy': AppColors.themeSuccess,
  };

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What the clustering found', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.md),
          for (final severity in ['severe', 'moderate', 'healthy'])
            _ZoneBar(
              label: _labels[severity]!,
              color: _colors[severity]!,
              percent: prescription.percentOf(severity),
              areaHa: prescription.areasHa[severity],
              patches: prescription.patchCountFor(severity),
            ),
          if (prescription.fieldHa != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Footprint ${prescription.fieldHa!.toStringAsFixed(2)} ha '
              '· ${prescription.coverage.gsdM?.toStringAsFixed(3) ?? '—'} m/pixel',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ZoneBar extends StatelessWidget {
  const _ZoneBar({
    required this.label,
    required this.color,
    required this.percent,
    required this.areaHa,
    required this.patches,
  });

  final String label;
  final Color color;
  final double percent;
  final double? areaHa;
  final int patches;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label, style: AppTextStyle.textSmMedium)),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: AppTextStyle.textSmSemibold,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.light500,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (areaHa != null || patches > 0) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (areaHa != null) '${areaHa!.toStringAsFixed(3)} ha',
                if (patches > 0) '$patches patch${patches == 1 ? '' : 'es'}',
              ].join(' · '),
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark100,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Options ──────────────────────────────────────────────────────────────────

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.state});

  final SprayState state;

  @override
  Widget build(BuildContext context) {
    final prescription = state.prescription!;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your choice', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Each option is costed against spraying the whole block, at '
            '${prescription.dosePerHa.toStringAsFixed(0)} L/ha.',
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final option in prescription.options)
            _OptionTile(
              option: option,
              selected: state.selectedOption == option.id,
              // The blanket row is the baseline to compare against, not
              // something a prescription can be flown as.
              enabled: !option.isBlanket && prescription.canFly,
              busy: state.status == SprayStatus.planning &&
                  state.selectedOption == option.id,
              onTap: () => context.read<SprayCubit>().selectOption(option.id),
            ),
          if (!prescription.canFly) ...[
            const SizedBox(height: AppSpacing.sm),
            _Note(
              text: prescription.coverage.georeferenced
                  ? 'No patch was large enough to target — either the field is '
                        'clean, or the affected pixels are too scattered for a '
                        'boom pass.'
                  : 'This capture cannot become spray waypoints: '
                        '${prescription.coverage.missing.join('; ')}. The '
                        'zones above are still valid for scouting.',
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final SprayOption option;
  final bool selected, enabled, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: enabled && !busy ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryFade : AppColors.light300,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.light500,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      option.label,
                      style: AppTextStyle.textSmSemibold.copyWith(
                        color: enabled ? AppColors.dark700 : AppColors.dark300,
                      ),
                    ),
                  ),
                  if (option.recommended && enabled)
                    _Pill(text: 'Suggested', color: AppColors.primary),
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                option.detail,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  _Metric(
                    label: 'Treated',
                    value: '${option.treatedPercent}%',
                  ),
                  _Metric(
                    label: 'Chemical saved',
                    value: '${option.savingPercent}%',
                    highlight: option.savingPercent > 0,
                  ),
                  if (option.chemicalL != null)
                    _Metric(
                      label: 'Spray',
                      value: '${option.chemicalL!.toStringAsFixed(1)} L',
                    ),
                  if (option.savedL != null && option.savedL! > 0)
                    _Metric(
                      label: 'Litres saved',
                      value: option.savedL!.toStringAsFixed(1),
                      highlight: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label, value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyle.textMdBold.copyWith(
              color: highlight ? AppColors.primary : AppColors.dark700,
            ),
          ),
          Text(
            label,
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),
        ],
      ),
    );
  }
}

// ── Plan + command ───────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.state});

  final SprayState state;

  @override
  Widget build(BuildContext context) {
    final plan = state.plan!;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'What the drone would fly',
                  style: AppTextStyle.textMdSemibold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _Fact(label: 'Patches', value: '${plan.patches}'),
              _Fact(label: 'Waypoints', value: '${plan.waypoints}'),
              _Fact(
                label: 'Path',
                value: '${plan.pathLengthM.toStringAsFixed(0)} m',
              ),
              _Fact(
                label: 'Flight time',
                value: '≈ ${plan.estimatedMinutes.toStringAsFixed(1)} min',
              ),
              _Fact(label: 'Swath', value: '${plan.swathM.toStringAsFixed(1)} m'),
              _Fact(label: 'Pump', value: plan.mechanism),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primaryFade,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${plan.savingPercent}% less chemical',
                        style: AppTextStyle.textLgBold.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        plan.savedL != null
                            ? '${plan.savedL!.toStringAsFixed(1)} L saved vs '
                                  '${plan.blanketL!.toStringAsFixed(1)} L for a '
                                  'blanket pass'
                            : 'Treating ${plan.treatedPercent}% of the block',
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: AppColors.dark500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!plan.variableRate) ...[
            const SizedBox(height: AppSpacing.sm),
            // The saving quoted has to be one the hardware can deliver.
            const _Note(
              text: 'This rig has an on/off pump, so the moderate zones are '
                  'sprayed at full rate. The saving above already accounts for '
                  'that — a proportional valve would save more.',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (state.isOnVehicle)
            _OnVehicleControls(state: state)
          else
            _CommandControls(state: state),
        ],
      ),
    );
  }
}

class _CommandControls extends StatelessWidget {
  const _CommandControls({required this.state});

  final SprayState state;

  @override
  Widget build(BuildContext context) {
    final sending = state.status == SprayStatus.sending;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: sending ? null : () => _confirm(context, start: true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(sending ? 'Sending…' : 'Spray these zones'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: sending ? null : () => _confirm(context, start: false),
            icon: const Icon(Icons.upload_outlined, size: 18),
            label: const Text('Upload to drone without launching'),
          ),
        ),
      ],
    );
  }

  /// Launching a spray run is not undoable from a phone screen, so it is
  /// confirmed in words that say what is about to happen.
  Future<void> _confirm(BuildContext context, {required bool start}) async {
    final cubit = context.read<SprayCubit>();
    final plan = state.plan!;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(start ? 'Start spraying?' : 'Upload to the drone?'),
        content: Text(
          start
              ? 'The aircraft will arm, fly ${plan.patches} patch(es) over '
                    '${plan.pathLengthM.toStringAsFixed(0)} m and open the '
                    'spray valve over each one.\n\n'
                    'Make sure the field is clear of people and livestock.'
              : 'The spray mission will be written to the flight controller. '
                    'Nothing will be sprayed until you launch it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(start ? 'Start spraying' : 'Upload'),
          ),
        ],
      ),
    );

    if (ok == true) await cubit.execute(start: start);
  }
}

class _OnVehicleControls extends StatelessWidget {
  const _OnVehicleControls({required this.state});

  final SprayState state;

  @override
  Widget build(BuildContext context) {
    final spraying = state.status == SprayStatus.spraying;
    return Column(
      children: [
        Row(
          children: [
            Icon(
              spraying ? Icons.water_drop : Icons.check_circle_outline,
              color: spraying ? AppColors.primary : AppColors.themeSuccess,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                spraying
                    ? 'Spraying — the aircraft is flying the prescription.'
                    : 'Mission is on the drone. Launch it when the field is clear.',
                style: AppTextStyle.textSmMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.themeError),
            onPressed: () => context.read<SprayCubit>().stopSpray(),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop spray & hold'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Closes the valve first, then holds the aircraft in place.',
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
        ),
      ],
    );
  }
}

// ── History + shared bits ────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});

  final List<SprayPrescriptionSummary> history;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Past prescriptions', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.sm),
          ...history.take(10).map(
            (row) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.history,
                color: AppColors.primary,
                size: 20,
              ),
              title: Text(
                row.fieldName?.isNotEmpty == true ? row.fieldName! : row.shotId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.textSmMedium,
              ),
              subtitle: Text(
                [
                  row.status,
                  if (row.chosenOption != null) row.chosenOption!,
                  if (row.savingPercent != null) '${row.savingPercent}% saved',
                  '${row.patchCount} patches',
                ].join(' · '),
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
              onTap: () => context.read<SprayCubit>().openPrescription(row.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          Icon(
            Icons.scatter_plot_outlined,
            size: 40,
            color: AppColors.dark100,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No prescription yet',
            style: AppTextStyle.textMdSemibold,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Capture a multispectral shot on the Drone Capture screen, then '
            'build a prescription from it.',
            textAlign: TextAlign.center,
            style: AppTextStyle.textSmRegular.copyWith(color: AppColors.dark300),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRouterNames.capture),
            child: const Text('Go to Drone Capture'),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTextStyle.textSmSemibold),
        Text(
          label,
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: AppColors.themeWarning),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark500),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        text,
        style: AppTextStyle.textXsSemibold.copyWith(color: color),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.lg),
          Text(
            text,
            style: AppTextStyle.textSmRegular.copyWith(color: AppColors.dark300),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: child,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.themeError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.themeError.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: AppColors.themeError,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.themeError,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
