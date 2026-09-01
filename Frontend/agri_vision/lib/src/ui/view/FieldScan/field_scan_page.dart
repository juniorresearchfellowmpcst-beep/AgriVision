import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/fieldscan/field_scan_cubit.dart';

/// Weed detection and crop-disease classification from the low-pace mission.
///
/// The survey pass says *where* the field is stressed; this pass says *why*.
/// Frames from the RGB camera go through weed detection (crop-row geometry,
/// falling back to colour/texture clustering) and a crop-disease classifier
/// trained on Madhya Pradesh's crops — soybean, rice, wheat, gram, maize,
/// mustard, cotton and tur.
///
/// Picking the crop first is not a formality: the same yellowing is yellow
/// rust in wheat and yellow mosaic in soybean.
class FieldScanPage extends StatefulWidget {
  const FieldScanPage({this.sessionId, super.key});

  /// The capture session to scan, when arriving from the capture screen.
  final String? sessionId;

  @override
  State<FieldScanPage> createState() => _FieldScanPageState();
}

class _FieldScanPageState extends State<FieldScanPage> {
  @override
  void initState() {
    super.initState();
    context.read<FieldScanCubit>().load();
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
          'Weed & Disease Scan',
          style: AppTextStyle.textLgSemibold.copyWith(color: AppColors.light100),
        ),
        actions: [
          BlocBuilder<FieldScanCubit, FieldScanState>(
            buildWhen: (a, b) =>
                a.hasResult != b.hasResult || a.hasSummary != b.hasSummary,
            builder: (context, state) {
              if (!state.hasResult && !state.hasSummary) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'New scan',
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<FieldScanCubit>().reset(),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: BlocBuilder<FieldScanCubit, FieldScanState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _CropPicker(state: state),
                const SizedBox(height: AppSpacing.lg),
                _ScanCard(state: state, sessionId: widget.sessionId),
                if (state.errorMessage.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ErrorBanner(message: state.errorMessage),
                ],
                if (state.isBusy) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (state.hasSummary) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SummaryCard(summary: state.summary!),
                ],
                if (state.hasResult) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ResultSection(result: state.result!, image: state.image),
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

// ── Crop ─────────────────────────────────────────────────────────────────────

class _CropPicker extends StatelessWidget {
  const _CropPicker({required this.state});

  final FieldScanState state;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Which crop?',
                  style: AppTextStyle.textMdSemibold,
                ),
              ),
              _Pill(
                text: state.usesTrainedModel ? 'CNN model' : 'On-device rules',
                color: state.usesTrainedModel
                    ? AppColors.primary
                    : AppColors.dark300,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The crop is part of the diagnosis — the same yellowing means '
            'yellow rust in wheat and yellow mosaic in soybean.',
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),
          const SizedBox(height: AppSpacing.md),
          if (state.crops.isEmpty)
            const LinearProgressIndicator(minHeight: 2)
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final crop in state.crops)
                  ChoiceChip(
                    label: Text(crop.name),
                    selected: state.selectedCrop == crop.id,
                    onSelected: (selected) => context
                        .read<FieldScanCubit>()
                        .selectCrop(selected ? crop.id : null),
                  ),
              ],
            ),
          if (state.crop != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${state.crop!.localName} · ${state.crop!.season} · '
              '${state.crop!.diseaseCount} conditions known',
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

// ── Scan actions ─────────────────────────────────────────────────────────────

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.state, required this.sessionId});

  final FieldScanState state;
  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FieldScanCubit>();
    final session = sessionId ?? state.sessionId;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scan', style: AppTextStyle.textMdSemibold),
          const SizedBox(height: AppSpacing.md),
          if (session != null && session.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: state.isBusy ? null : () => cubit.scanSession(session),
                icon: const Icon(Icons.travel_explore),
                label: const Text('Scan the low-pace pass'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Runs over every RGB frame in $session and gives one answer for '
              'the field — one frame on its own is only an anecdote.',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy ? null : cubit.captureAndScan,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isBusy ? null : cubit.pickAndScan,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          if (session == null || session.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'To scan a whole pass, capture RGB frames on the Drone Capture '
              'screen first.',
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

// ── Field-level summary ──────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final FieldScanSummary summary;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.landscape_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Across the pass',
                  style: AppTextStyle.textMdSemibold,
                ),
              ),
              _Pill(
                text: '${summary.frames} frames',
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(summary.summary, style: AppTextStyle.textSmRegular),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Metric(
                label: 'Weed cover',
                value: '${summary.weedPercent}%',
                highlight: summary.weedLevel == 'high',
              ),
              _Metric(
                label: 'Weed pressure',
                value: summary.weedLevel,
                highlight: summary.weedLevel == 'high',
              ),
              _Metric(
                label: 'Frames affected',
                value: '${summary.diseasedFrames}/${summary.frames}',
                highlight: summary.diseaseIncidence >= 0.5,
              ),
            ],
          ),
          if (summary.conditions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('What showed up', style: AppTextStyle.textSmSemibold),
            const SizedBox(height: AppSpacing.xs),
            ...summary.conditions.map(
              (condition) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        condition.name,
                        style: AppTextStyle.textSmRegular,
                      ),
                    ),
                    Text(
                      '${condition.sharePercent}% of frames',
                      style: AppTextStyle.textXsSemibold.copyWith(
                        color: AppColors.dark300,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (summary.hotspots.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Hotspots (${summary.hotspots.length})',
              style: AppTextStyle.textSmSemibold,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The worst frames, with the coordinates a targeted spray run '
              'would be aimed at.',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
            ...summary.hotspots.take(6).map(
              (spot) => Text(
                '• ${spot.lat.toStringAsFixed(6)}, ${spot.lon.toStringAsFixed(6)}'
                '${spot.condition != null ? ' — ${spot.condition}' : ''}',
                style: AppTextStyle.textXsRegular,
              ),
            ),
          ],
          if (summary.actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _ActionList(actions: summary.actions),
          ],
        ],
      ),
    );
  }
}

// ── One frame's result ───────────────────────────────────────────────────────

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.result, this.image});

  final FieldScanResult result;

  /// The frame this scan came from, so "Know More" sends the advisor the same
  /// picture. Null when a whole capture session was scanned rather than one
  /// photo — the diagnosis still goes, by id.
  final MediaFile? image;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Above the detail: somebody who does not recognise the verdict needs
        // the way to ask about it before they need the reading material.
        if (result.advisorAvailable) ...[
          KnowMoreCard(
            image: image,
            scanId: result.scanId,
            subject: result.disease.name,
            diagnosis: {
              if (result.cropName != null) 'crop_name': result.cropName,
              'disease': {
                'name': result.disease.name,
                'confidence': result.disease.confidence,
                'source': result.disease.source,
              },
              'severity': {'level': result.severityLevel},
              'weeds': {
                'pressure': {
                  'level': result.weeds.level,
                  'percent': result.weeds.percent,
                },
              },
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (result.overlayUrl != null) ...[
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weed overlay', style: AppTextStyle.textMdSemibold),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(
                    result.overlayUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 100,
                      color: AppColors.light500,
                      alignment: Alignment.center,
                      child: const Text('Overlay unavailable'),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Green = crop, red = weed.',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        _WeedCard(weeds: result.weeds),
        const SizedBox(height: AppSpacing.lg),
        _DiseaseCard(result: result),
        if (result.actions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _Card(child: _ActionList(actions: result.actions)),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          result.disclaimer,
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark100),
        ),
      ],
    );
  }
}

class _WeedCard extends StatelessWidget {
  const _WeedCard({required this.weeds});

  final WeedFinding weeds;

  Color get _levelColor => switch (weeds.level) {
    'high' => AppColors.themeError,
    'moderate' => AppColors.themeWarning,
    'low' => AppColors.primary,
    _ => AppColors.themeSuccess,
  };

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grass_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Weeds', style: AppTextStyle.textMdSemibold)),
              _Pill(text: weeds.level, color: _levelColor),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Metric(label: 'Ground cover', value: '${weeds.percent}%'),
              _Metric(label: 'Patches', value: '${weeds.patchCount}'),
              _Metric(
                label: 'Confidence',
                value: '${(weeds.confidence * 100).round()}%',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // How the weeds were separated from the crop is what the number's
          // reliability rests on, so it is shown rather than hidden.
          Text(
            'Method: ${weeds.methodLabel}',
            style: AppTextStyle.textSmSemibold,
          ),
          if (weeds.note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              weeds.note,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ],
          if (weeds.advice.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(weeds.advice, style: AppTextStyle.textSmRegular),
          ],
          if (weeds.likelyWeeds.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Likely species here', style: AppTextStyle.textSmSemibold),
            const SizedBox(height: AppSpacing.xs),
            ...weeds.likelyWeeds.map((weed) => _WeedTile(weed: weed)),
          ],
        ],
      ),
    );
  }
}

class _WeedTile extends StatelessWidget {
  const _WeedTile({required this.weed});

  final LikelyWeed weed;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        title: Text(
          '${weed.name}${weed.localName.isEmpty ? '' : ' · ${weed.localName}'}',
          style: AppTextStyle.textSmMedium,
        ),
        subtitle: Text(
          weed.type,
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
        ),
        children: [
          if (weed.identify.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('How to tell it apart', style: AppTextStyle.textXsSemibold),
            ),
            ...weed.identify.map(
              (line) => Align(
                alignment: Alignment.centerLeft,
                child: Text('• $line', style: AppTextStyle.textXsRegular),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (weed.control.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Control', style: AppTextStyle.textXsSemibold),
            ),
            ...weed.control.map(
              (line) => Align(
                alignment: Alignment.centerLeft,
                child: Text('• $line', style: AppTextStyle.textXsRegular),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  const _DiseaseCard({required this.result});

  final FieldScanResult result;

  Color get _severityColor => switch (result.severityLevel) {
    'high' => AppColors.themeError,
    'moderate' => AppColors.themeWarning,
    'low' => AppColors.primary,
    _ => AppColors.themeSuccess,
  };

  @override
  Widget build(BuildContext context) {
    final disease = result.disease;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.coronavirus_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Condition', style: AppTextStyle.textMdSemibold),
              ),
              _Pill(
                text: result.isHealthy
                    ? 'healthy'
                    : '${result.severityLevel} · ${result.affectedPercent}%',
                color: _severityColor,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(disease.name, style: AppTextStyle.textLgSemibold),
          if (disease.pathogen.isNotEmpty)
            Text(
              disease.pathogen,
              style: AppTextStyle.textXsRegular.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.dark300,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${disease.confidencePercent}% confidence · '
            '${disease.source == 'model' ? 'trained CNN' : 'on-device rules'}',
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),
          if (disease.alternatives.isNotEmpty)
            Text(
              'Also possible: ${disease.alternatives.join(', ')}',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          if (disease.note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              disease.note,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.themeWarning,
              ),
            ),
          ],
          if (disease.symptoms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('What to look for', style: AppTextStyle.textSmSemibold),
            ...disease.symptoms.map(
              (line) => Text('• $line', style: AppTextStyle.textSmRegular),
            ),
          ],
          if (disease.favours.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Favoured by: ${disease.favours}',
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ],
          if (disease.management.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('What to do', style: AppTextStyle.textSmSemibold),
            ...disease.management.map(
              (line) => Text('• $line', style: AppTextStyle.textSmRegular),
            ),
          ],
          if (disease.severityNote.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              disease.severityNote,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

class _ActionList extends StatelessWidget {
  const _ActionList({required this.actions});

  final List<ScanAction> actions;

  IconData _icon(String category) => switch (category) {
    'weed' => Icons.grass_outlined,
    'disease' => Icons.coronavirus_outlined,
    'spray' => Icons.water_drop_outlined,
    'context' => Icons.info_outline,
    _ => Icons.visibility_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recommended actions', style: AppTextStyle.textSmSemibold),
        const SizedBox(height: AppSpacing.sm),
        ...actions.map(
          (action) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(action.category), size: 18, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(action.title, style: AppTextStyle.textSmMedium),
                      if (action.detail.isNotEmpty)
                        Text(
                          action.detail,
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
        ),
      ],
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
              color: highlight ? AppColors.themeError : AppColors.dark700,
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
          const Icon(Icons.error_outline, color: AppColors.themeError, size: 18),
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
