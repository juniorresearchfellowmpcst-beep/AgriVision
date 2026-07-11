import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/analysis/analysis_cubit.dart';

/// Field-image analysis screen.
///
/// Lets the user pick multispectral band images from their system (no drone
/// needed yet), uploads them to the backend, and renders the returned field
/// report: an overall health score, high/medium/low **risk** regions, an
/// action plan, and per-index readings.
///
/// State is owned by [AnalysisCubit]; this page is a pure function of that
/// state, matching the app's BLoC/Cubit architecture.
class AnalysisPage extends StatelessWidget {
  const AnalysisPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AnalysisCubit(),
      child: const _AnalysisView(),
    );
  }
}

class _AnalysisView extends StatelessWidget {
  const _AnalysisView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.light100,
        elevation: 0,
        title: Text(
          'Field Image Analysis',
          style: AppTextStyle.textLgSemibold.copyWith(color: AppColors.light100),
        ),
        actions: [
          BlocBuilder<AnalysisCubit, AnalysisState>(
            buildWhen: (a, b) => a.hasResult != b.hasResult,
            builder: (context, state) {
              if (!state.hasResult) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'New analysis',
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<AnalysisCubit>().reset(),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: BlocBuilder<AnalysisCubit, AnalysisState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const _IntroCard(),
                const SizedBox(height: AppSpacing.lg),
                const _SelectionCard(),
                if (state.errorMessage.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ErrorBanner(message: state.errorMessage),
                ],
                if (state.isBusy) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  const _BusyIndicator(),
                ],
                if (state.hasResult) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ResultSection(result: state.result!),
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

// ── Intro ────────────────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.eco_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Crop health from images', style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Pick the band images from your multispectral camera (e.g. blue, '
            'green, red, red-edge, NIR). Name them with the band or pick them in '
            'order. We compute the vegetation indices, split the field into '
            'high / medium / low risk zones, and produce an action plan.',
            style: AppTextStyle.textSmRegular.copyWith(color: AppColors.dark300),
          ),
        ],
      ),
    );
  }
}

// ── Selection + controls ─────────────────────────────────────────────────────

class _SelectionCard extends StatelessWidget {
  const _SelectionCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AnalysisCubit, AnalysisState>(
      builder: (context, state) {
        final cubit = context.read<AnalysisCubit>();
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppIconButton(
                label: state.images.isEmpty
                    ? 'Select multispectral images'
                    : 'Add more images',
                startIcon: Icons.add_photo_alternate_outlined,
                width: double.infinity,
                height: 52,
                mainAxisAlignment: MainAxisAlignment.center,
                textStyle: AppTextStyle.textMdSemibold,
                onPressed: state.isBusy ? null : cubit.pickImages,
              ),
              if (state.images.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Assign each image to its band',
                  style: AppTextStyle.textSmSemibold,
                ),
                const SizedBox(height: 2),
                Text(
                  'Guessed from the filenames — correct any that are wrong. '
                  'Unassigned images are auto-detected by the server.',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (int i = 0; i < state.images.length; i++)
                  Builder(
                    builder: (_) {
                      final name = state.images[i].name;
                      final band = state.fileBand[name];
                      // Bands already used by *other* files — greyed out here.
                      final takenByOthers = state.fileBand.values.toSet()
                        ..remove(band);
                      return _BandFileRow(
                        name: name,
                        band: band,
                        enabled: !state.isBusy,
                        disabledBands: takenByOthers,
                        onBandChanged: (b) => cubit.assignBand(name, b),
                        onRemove:
                            state.isBusy ? null : () => cubit.removeImage(i),
                      );
                    },
                  ),
                const SizedBox(height: AppSpacing.md),
                _CalibrateToggle(
                  value: state.calibrate,
                  onChanged: state.isBusy ? null : cubit.setCalibrate,
                ),
                const SizedBox(height: AppSpacing.md),
                AppIconButton(
                  label: state.isBusy ? 'Analyzing…' : 'Analyze field',
                  startIcon: Icons.insights_outlined,
                  width: double.infinity,
                  height: 52,
                  mainAxisAlignment: MainAxisAlignment.center,
                  color: AppColors.primary,
                  pressedColor: AppColors.primary6,
                  disabledColor: AppColors.light700,
                  showBorder: false,
                  iconColor: AppColors.light100,
                  pressedIconColor: AppColors.light100,
                  textColor: AppColors.light100,
                  pressedTextColor: AppColors.light100,
                  textStyle: AppTextStyle.textMdSemibold,
                  onPressed: state.canAnalyze ? cubit.analyze : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Human-readable label for a band key (e.g. 'red_edge' -> 'Red Edge').
const Map<String, String> _bandLabels = {
  'blue': 'Blue',
  'green': 'Green',
  'red': 'Red',
  'red_edge': 'Red Edge',
  'nir': 'NIR',
};

/// One picked image: name + a band dropdown + a remove button.
class _BandFileRow extends StatelessWidget {
  const _BandFileRow({
    required this.name,
    required this.band,
    required this.enabled,
    required this.disabledBands,
    required this.onBandChanged,
    this.onRemove,
  });

  final String name;
  final String? band;
  final bool enabled;
  final Set<String> disabledBands;
  final ValueChanged<String> onBandChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final assigned = band != null;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.light300,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: assigned ? AppColors.primary3 : AppColors.light700,
        ),
      ),
      child: Row(
        children: [
          Icon(
            assigned ? Icons.check_circle : Icons.image_outlined,
            size: 18,
            color: assigned ? AppColors.primary : AppColors.dark100,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.textSmMedium.copyWith(
                color: AppColors.dark700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _BandDropdown(
            value: band,
            enabled: enabled,
            disabledBands: disabledBands,
            onChanged: onBandChanged,
          ),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.close, size: 18, color: AppColors.dark300),
              ),
            ),
        ],
      ),
    );
  }
}

class _BandDropdown extends StatelessWidget {
  const _BandDropdown({
    required this.value,
    required this.enabled,
    required this.disabledBands,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final Set<String> disabledBands;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final assigned = value != null;
    return Container(
      // Fixed width so the rows line up and the box doesn't resize when the
      // label changes from "Band?" to e.g. "Red Edge".
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: assigned ? AppColors.primary3 : AppColors.light700,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: Text(
            'Band?',
            style: AppTextStyle.textXsSemibold.copyWith(
              color: AppColors.dark300,
            ),
          ),
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          style: AppTextStyle.textXsSemibold.copyWith(color: AppColors.dark700),
          onChanged: enabled ? (b) => b == null ? null : onChanged(b) : null,
          selectedItemBuilder: (_) => [
            // Always render the selected value in the normal colour, even
            // though the same band is "disabled" for other rows.
            for (final b in kBands)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_bandLabels[b] ?? b),
              ),
          ],
          items: [
            for (final b in kBands)
              DropdownMenuItem(
                value: b,
                enabled: !disabledBands.contains(b),
                child: Row(
                  children: [
                    Text(
                      _bandLabels[b] ?? b,
                      style: disabledBands.contains(b)
                          ? AppTextStyle.textXsRegular.copyWith(
                              color: AppColors.light900,
                            )
                          : null,
                    ),
                    if (disabledBands.contains(b)) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check, size: 12, color: AppColors.primary3),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CalibrateToggle extends StatelessWidget {
  const _CalibrateToggle({required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Panel calibration', style: AppTextStyle.textSmSemibold),
              Text(
                'Also add a calibration-panel photo for true reflectance',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ── Busy / error ─────────────────────────────────────────────────────────────

class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Processing bands, computing indices and risk zones…',
          textAlign: TextAlign.center,
          style: AppTextStyle.textSmRegular.copyWith(color: AppColors.dark300),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.themeError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.themeError.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.themeError, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result ───────────────────────────────────────────────────────────────────

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.result});

  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!result.calibrated) _UncalibratedNote(),
        if (!result.calibrated) const SizedBox(height: AppSpacing.md),
        _HealthCard(result: result),
        const SizedBox(height: AppSpacing.lg),
        _RiskCard(result: result),
        if (result.riskMapUrl != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _RiskMapCard(url: result.riskMapUrl!),
        ],
        if (result.flags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _FlagsCard(flags: result.flags),
        ],
        if (result.actionPlan.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _ActionPlanCard(actions: result.actionPlan),
        ],
        if (result.indexSummaries.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _IndicesCard(summaries: result.indexSummaries),
        ],
      ],
    );
  }
}

class _UncalibratedNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.themeWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.themeWarning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Uncalibrated — index values are relative. Add a panel photo for '
              'absolute reflectance.',
              style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark500),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.result});

  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final score = result.healthScore ?? 0;
    final color = _healthColor(result.healthLabel);
    return _Card(
      child: Row(
        children: [
          _ScoreRing(score: score, color: color),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Field health', style: AppTextStyle.textSmRegular.copyWith(
                  color: AppColors.dark300,
                )),
                const SizedBox(height: 2),
                Text(
                  result.healthLabel.toUpperCase(),
                  style: AppTextStyle.textXlBold.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  'Primary index: ${result.primaryIndex?.toUpperCase() ?? '—'} · '
                  'bands: ${result.bandsUsed.join(', ')}',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
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

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 7,
              backgroundColor: AppColors.light500,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text('$score', style: AppTextStyle.textLgBold.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.result});

  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Risk zones', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.sm),
          _RiskBar(
            high: result.highRisk,
            medium: result.mediumRisk,
            low: result.lowRisk,
          ),
          const SizedBox(height: AppSpacing.md),
          _RiskLegendRow(label: 'High risk', color: AppColors.themeError, fraction: result.highRisk),
          const SizedBox(height: 6),
          _RiskLegendRow(label: 'Medium risk', color: AppColors.themeWarning, fraction: result.mediumRisk),
          const SizedBox(height: 6),
          _RiskLegendRow(label: 'Low risk', color: AppColors.themeSuccess, fraction: result.lowRisk),
        ],
      ),
    );
  }
}

class _RiskBar extends StatelessWidget {
  const _RiskBar({required this.high, required this.medium, required this.low});

  final double high;
  final double medium;
  final double low;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        height: 16,
        child: Row(
          children: [
            Expanded(flex: (high * 1000).round().clamp(0, 1000), child: Container(color: AppColors.themeError)),
            Expanded(flex: (medium * 1000).round().clamp(0, 1000), child: Container(color: AppColors.themeWarning)),
            Expanded(flex: (low * 1000).round().clamp(0, 1000), child: Container(color: AppColors.themeSuccess)),
          ],
        ),
      ),
    );
  }
}

class _RiskLegendRow extends StatelessWidget {
  const _RiskLegendRow({
    required this.label,
    required this.color,
    required this.fraction,
  });

  final String label;
  final Color color;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: AppTextStyle.textSmRegular)),
        Text(
          '${(fraction * 100).round()}%',
          style: AppTextStyle.textSmSemibold.copyWith(color: AppColors.dark700),
        ),
      ],
    );
  }
}

class _RiskMapCard extends StatelessWidget {
  const _RiskMapCard({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Risk map', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              errorBuilder: (_, __, ___) => _ImageError(),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 160,
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Red = high risk · amber = medium · green = low',
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),
        ],
      ),
    );
  }
}

class _ImageError extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 120,
    alignment: Alignment.center,
    color: AppColors.light500,
    child: Text(
      'Preview unavailable',
      style: AppTextStyle.textSmRegular.copyWith(color: AppColors.dark300),
    ),
  );
}

class _FlagsCard extends StatelessWidget {
  const _FlagsCard({required this.flags});

  final List<ReportFlag> flags;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detected issues', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.sm),
          for (final f in flags)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: f.severity == 'high'
                          ? AppColors.themeError
                          : AppColors.themeWarning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      f.issue,
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.dark700,
                      ),
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

class _ActionPlanCard extends StatelessWidget {
  const _ActionPlanCard({required this.actions});

  final List<ActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text('Action plan', style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PriorityBadge(priority: a.priority, order: a.order),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title, style: AppTextStyle.textSmSemibold),
                        const SizedBox(height: 2),
                        Text(
                          a.detail,
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark300,
                          ),
                        ),
                      ],
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

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority, required this.order});

  final int priority;
  final int order;

  @override
  Widget build(BuildContext context) {
    final color = priority <= 1
        ? AppColors.themeError
        : priority == 2
            ? AppColors.themeWarning
            : AppColors.primary;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color),
      ),
      child: Text(
        '$order',
        style: AppTextStyle.textSmBold.copyWith(color: color),
      ),
    );
  }
}

class _IndicesCard extends StatelessWidget {
  const _IndicesCard({required this.summaries});

  final List<IndexSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Index readings', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final s in summaries) _IndexPill(summary: s)],
          ),
        ],
      ),
    );
  }
}

class _IndexPill extends StatelessWidget {
  const _IndexPill({required this.summary});

  final IndexSummary summary;

  @override
  Widget build(BuildContext context) {
    final color = summary.status == 'good'
        ? AppColors.themeSuccess
        : summary.status == 'poor'
            ? AppColors.themeError
            : AppColors.themeWarning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.light300,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.light700),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(summary.name, style: AppTextStyle.textSmSemibold),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            summary.mean.toStringAsFixed(2),
            style: AppTextStyle.textMdBold.copyWith(color: AppColors.dark700),
          ),
        ],
      ),
    );
  }
}

// ── Shared card shell ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: child,
    );
  }
}

Color _healthColor(String label) {
  switch (label) {
    case 'healthy':
      return AppColors.themeSuccess;
    case 'moderate':
      return AppColors.themeWarning;
    case 'poor':
      return AppColors.themeError;
    default:
      return AppColors.dark300;
  }
}
