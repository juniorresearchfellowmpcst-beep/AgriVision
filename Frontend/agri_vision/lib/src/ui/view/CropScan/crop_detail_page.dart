import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/view/CropScan/crop_scan_result_page.dart';
import 'package:agri_vision/src/ui/widget/survey/treatment_cards.dart';

/// One crop opened from the picker.
///
/// Two things on one screen, and they belong together: the camera button that
/// diagnoses *this* plant, and the reference list of what this crop gets here.
/// A farmer who is unsure often recognises the disease from the symptom list
/// before the camera ever comes out — and if they do, they still need the
/// treatment, which is on the same card.
class CropDetailPage extends StatefulWidget {
  const CropDetailPage({required this.cropId, super.key});

  final String cropId;

  static Future<void> open(BuildContext context, {required String cropId}) {
    // The cubit is app-scoped, so the detail screen reads the same instance
    // the picker filled — no second fetch of a catalogue already in memory.
    context.read<CropCubit>().openCrop(cropId);
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CropDetailPage(cropId: cropId)),
    );
  }

  @override
  State<CropDetailPage> createState() => _CropDetailPageState();
}

class _CropDetailPageState extends State<CropDetailPage> {
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CropCubit, CropState>(
      listenWhen: (a, b) => a.result != b.result && b.result != null,
      listener: (context, state) {
        // A finished scan pushes its own screen: the result is the thing the
        // farmer came for, and burying it below a reference list would hide it.
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CropScanResultPage()),
        );
      },
      builder: (context, state) {
        final detail = state.detail;

        return Scaffold(
          backgroundColor: AppColors.tertiary,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: AppColors.light100,
            elevation: 0,
            title: Text(
              detail?.name ?? 'Crop',
              style: AppTextStyle.textLgSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
          ),
          body: detail == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  top: false,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      _ScanCard(state: state, detail: detail),

                      if (detail.note.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _Note(text: detail.note),
                      ],

                      if (state.isWeedsSelected) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _WeedCropNarrower(state: state),
                      ],

                      if (detail.diseases.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'What ${detail.name} gets here',
                          style: AppTextStyle.textMdSemibold,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Tap one to see the symptoms and what treats it. '
                          'Recognising it yourself is often faster than a scan.',
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark300,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final disease in detail.diseases)
                          _DiseaseCard(disease: disease),
                      ],

                      if (detail.weeds.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          state.isWeedsSelected
                              ? 'Weeds this app knows'
                              : 'Weeds that come with ${detail.name}',
                          style: AppTextStyle.textMdSemibold,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final weed in detail.weeds)
                          _WeedCard(weed: weed),
                      ],

                      if (detail.herbicides.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Herbicides registered for ${detail.name}',
                          style: AppTextStyle.textMdSemibold,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Safe over this crop. The same products will damage '
                          'a different one.',
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark300,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final product in detail.herbicides)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: ProductTile(product: product),
                          ),
                      ],

                      if (detail.disclaimer.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          detail.disclaimer,
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark100,
                            height: 1.45,
                          ),
                        ),
                      ],

                      const SizedBox(height: 60),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// The camera, and what it will be asked to look for.
class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.state, required this.detail});

  final CropState state;
  final CropDetail detail;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CropCubit>();

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
              Expanded(
                child: Text(
                  'Scan a plant',
                  style: AppTextStyle.textMdSemibold,
                ),
              ),
              if (detail.localName.isNotEmpty)
                Text(
                  detail.localName,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // The Weeds tile has already answered this question, so the choice
          // only appears where there is genuinely one to make.
          if (!state.isWeedsSelected) ...[
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final mode in ScanMode.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: state.mode == mode,
                    selectedColor: AppColors.primary,
                    labelStyle: AppTextStyle.textSmMedium.copyWith(
                      color: state.mode == mode
                          ? AppColors.light100
                          : AppColors.dark500,
                    ),
                    onSelected: (_) => cubit.selectMode(mode),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: state.isBusy ? null : cubit.captureAndScan,
                    icon: state.isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.light100,
                            ),
                          )
                        : const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(state.isScanning ? 'Scanning…' : 'Take photo'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: state.isBusy ? null : cubit.pickAndScan,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Fill the frame with the affected leaf or the patch of ground. A '
            'photo from three metres away tells the model very little.',
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
              height: 1.4,
            ),
          ),

          if (state.errorMessage.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.themeError.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                state.errorMessage,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.themeError,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which crop the weeds are growing in.
///
/// Not a filter for convenience: without a crop the app can measure weed
/// pressure but must not name a herbicide, because the product that clears
/// wheat will flatten a soybean field.
class _WeedCropNarrower extends StatelessWidget {
  const _WeedCropNarrower({required this.state});

  final CropState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.themeWarning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Which crop are they growing in?',
            style: AppTextStyle.textSmSemibold,
          ),
          const SizedBox(height: 2),
          Text(
            'Without this the app can measure the weed pressure but cannot '
            'name a herbicide — the one that clears wheat kills soybean.',
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final crop in state.crops)
                ChoiceChip(
                  label: Text(crop.name),
                  selected: state.weedCrop == crop.id,
                  selectedColor: AppColors.primary,
                  labelStyle: AppTextStyle.textSmMedium.copyWith(
                    color: state.weedCrop == crop.id
                        ? AppColors.light100
                        : AppColors.dark500,
                  ),
                  onSelected: (selected) => context
                      .read<CropCubit>()
                      .narrowWeedsTo(selected ? crop.id : null),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiseaseCard extends StatelessWidget {
  const _DiseaseCard({required this.disease});

  final CropDisease disease;

  static const Map<String, Color> _urgencyColors = {
    'urgent': AppColors.themeError,
    'soon': AppColors.themeWarning,
    'routine': AppColors.dark300,
  };

  @override
  Widget build(BuildContext context) {
    final color = _urgencyColors[disease.urgency] ?? AppColors.dark300;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
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
                child: Text(disease.name, style: AppTextStyle.textSmSemibold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  disease.urgency,
                  style: AppTextStyle.textXsSemibold.copyWith(color: color),
                ),
              ),
            ],
          ),
          subtitle: disease.pathogen.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    disease.pathogen,
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.dark300,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
          children: [
            if (disease.symptoms.isNotEmpty) ...[
              _Label('What it looks like'),
              for (final symptom in disease.symptoms)
                _Bullet(symptom),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (disease.favours.isNotEmpty) ...[
              _Label('When it shows up'),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  disease.favours,
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.dark500,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (!disease.treatment.isEmpty)
              TreatmentCard(
                title: 'Treatment',
                treatment: disease.treatment,
                initiallyExpanded: true,
              ),
            if (disease.severityNote.isNotEmpty)
              Text(
                disease.severityNote,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark100,
                  height: 1.4,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeedCard extends StatelessWidget {
  const _WeedCard({required this.weed});

  final WeedEntry weed;

  static const Map<String, Color> _typeColors = {
    'grass': Color(0xFF7CB342),
    'sedge': Color(0xFF26A69A),
    'broadleaf': Color(0xFFE07B39),
  };

  @override
  Widget build(BuildContext context) {
    final color = _typeColors[weed.type] ?? AppColors.dark300;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
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
                child: Text(weed.name, style: AppTextStyle.textSmSemibold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  weed.type,
                  style: AppTextStyle.textXsSemibold.copyWith(color: color),
                ),
              ),
            ],
          ),
          subtitle: weed.localName.isEmpty
              ? null
              : Text(
                  weed.localName,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
          children: [
            if (weed.note.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  weed.note,
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.dark500,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (weed.identify.isNotEmpty) ...[
              // The part that matters standing in a field: several of these
              // look almost exactly like a young crop.
              _Label('How to tell it apart'),
              for (final line in weed.identify) _Bullet(line),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (weed.control.isNotEmpty) ...[
              _Label('Control'),
              for (final line in weed.control) _Bullet(line),
            ],
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text, style: AppTextStyle.textSmSemibold),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: AppTextStyle.textSmRegular.copyWith(color: AppColors.primary),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.light300,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        text,
        style: AppTextStyle.textXsRegular.copyWith(
          color: AppColors.dark300,
          height: 1.45,
        ),
      ),
    );
  }
}
