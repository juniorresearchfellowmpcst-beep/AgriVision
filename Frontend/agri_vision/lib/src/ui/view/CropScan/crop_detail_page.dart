import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/view/CropScan/crop_scan_result_page.dart';

/// One crop, and the camera.
///
/// This screen used to also carry the reference material: every disease the
/// crop gets, its usual weeds, the registered herbicides, and a
/// disease/weed/both mode picker. All of it was accurate and none of it
/// belonged here.
///
/// A farmer opens this screen holding a sick plant. What they need is the
/// shutter. Making them scroll past an encyclopedia to reach it — and decide
/// up front whether they are looking at a disease or a weed, which is the very
/// question they came to have answered — put two obstacles between the problem
/// and the answer. The reference content still exists in the knowledge base and
/// is what fills the *result*, where it is about the plant in the photo rather
/// than a list to study first.
class CropDetailPage extends StatefulWidget {
  const CropDetailPage({required this.cropId, super.key});

  final String cropId;

  static Future<void> open(BuildContext context, {required String cropId}) {
    // The cubit is app-scoped, so this screen reads the same instance the
    // picker filled — no second fetch of a catalogue already in memory.
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
    final l10n = context.l10n;

    return BlocConsumer<CropCubit, CropState>(
      listenWhen: (a, b) => a.result != b.result && b.result != null,
      listener: (context, state) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CropScanResultPage()),
        );
      },
      builder: (context, state) {
        final detail = state.detail;
        final name = detail?.name ?? state.selected?.name ?? '';

        return Scaffold(
          backgroundColor: AppColors.tertiary,
          appBar: AppBar(
            backgroundColor: AppColors.darkGreen,
            foregroundColor: AppColors.light100,
            elevation: 0,
            title: Text(
              name,
              style: AppTextStyle.textLgSemibold.copyWith(
                color: AppColors.light100,
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            // Centred and width-capped: on a tablet a full-width column of two
            // buttons looks like a broken page, and the camera is the only
            // thing on this screen.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    _CropHeader(
                      name: name,
                      localName: detail?.localName ?? '',
                      season: detail?.season ?? '',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _ScanCard(state: state),
                    if (state.errorMessage.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _ErrorNote(message: state.errorMessage),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      l10n.disclaimerShort,
                      textAlign: TextAlign.center,
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: AppColors.dark100,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CropHeader extends StatelessWidget {
  const _CropHeader({
    required this.name,
    required this.localName,
    required this.season,
  });

  final String name;
  final String localName;
  final String season;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.eco_outlined,
            size: 36,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          name,
          textAlign: TextAlign.center,
          style: AppTextStyle.textXlSemibold,
        ),
        if (localName.isNotEmpty)
          Text(
            localName,
            textAlign: TextAlign.center,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
      ],
    );
  }
}

/// The shutter. The whole screen, really.
class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.state});

  final CropState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CropCubit>();
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.photographThePlant,
            style: AppTextStyle.textMdSemibold,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.framingHint,
            textAlign: TextAlign.center,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SizedBox(
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              onPressed: state.isBusy ? null : cubit.captureAndScan,
              icon: state.isScanning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.light100,
                      ),
                    )
                  : const Icon(Icons.photo_camera_outlined, size: 20),
              label: Text(
                state.isScanning ? l10n.scanning : l10n.takePhoto,
                style: AppTextStyle.textLgSemibold.copyWith(
                  color: AppColors.light100,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: state.isBusy ? null : cubit.pickAndScan,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(l10n.gallery),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.themeError.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: AppColors.themeError,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.themeError,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
