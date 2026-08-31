import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/crops/crop_cubit.dart';
import 'package:agri_vision/src/ui/view/CropScan/crop_detail_page.dart';

/// The crop picker — the drone-free way in.
///
/// A farmer standing in a field with a suspicious leaf does not want to charge
/// a battery, fit a camera and fly a survey. They want to point their phone at
/// it. So this screen has no aircraft in it at all: pick the crop, take a
/// photo, read the answer.
///
/// The crop comes first and is not decoration. It is part of the diagnosis:
/// the same yellowing is yellow rust in wheat and yellow mosaic in soybean.
class CropScanPage extends StatefulWidget {
  const CropScanPage({super.key});

  @override
  State<CropScanPage> createState() => _CropScanPageState();
}

class _CropScanPageState extends State<CropScanPage> {
  @override
  void initState() {
    super.initState();
    context.read<CropCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.tertiary,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.light100,
        elevation: 0,
        title: Text(
          l10n.scanTitle,
          style: AppTextStyle.textLgSemibold.copyWith(color: AppColors.light100),
        ),
      ),
      body: BlocBuilder<CropCubit, CropState>(
        builder: (context, state) {
          if (state.crops.isEmpty && state.status == CropStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.crops.isEmpty) {
            return OfflineFallback(
              message: state.errorMessage.isEmpty
                  ? l10n.couldNotLoadCrops
                  : state.errorMessage,
              onRetry: () => context.read<CropCubit>().load(refresh: true),
            );
          }

          // Crops only. The Weeds tile used to sit here; weed work belongs to
          // the drone, which can see a whole block, and a phone photo of one
          // patch cannot say how much of a field is weedy.
          final crops = state.crops;
          final inSeason = crops.where((c) => c.inSeason == true).toList();
          final rest = crops.where((c) => c.inSeason != true).toList();

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => context.read<CropCubit>().load(refresh: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _Intro()),

                // In-season crops first. In August a farmer here is looking at
                // soybean and paddy; scrolling past wheat to reach it every
                // time is a small daily tax.
                if (inSeason.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      l10n.inSeasonNow,
                      hint: l10n.inSeasonHint,
                    ),
                  ),
                  _CropGrid(crops: inSeason),
                ],
                if (rest.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      inSeason.isEmpty ? l10n.crops : l10n.otherCrops,
                    ),
                  ),
                  _CropGrid(crops: rest),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.photo_camera_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.scanIntroTitle, style: AppTextStyle.textMdSemibold),
                const SizedBox(height: 2),
                Text(
                  l10n.scanIntroBody,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                    height: 1.4,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyle.textXsSemibold.copyWith(
              color: AppColors.dark100,
              letterSpacing: 0.8,
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
        ],
      ),
    );
  }
}

/// The crop grid, sized by the screen rather than by a fixed column count.
///
/// A hard `crossAxisCount: 3` is what makes a layout look wrong on real
/// devices: three columns are right on a 360 dp phone, cramped on a 320 dp
/// one, and absurdly stretched on a tablet where each tile ends up 240 dp
/// wide. Giving the delegate a *maximum tile width* instead lets the column
/// count fall out of the screen — 3 on a normal phone, 2 on a very narrow one,
/// 5 or 6 on a tablet — with the tiles staying a readable size throughout.
class _CropGrid extends StatelessWidget {
  const _CropGrid({required this.crops});

  final List<CropCatalogItem> crops;

  /// Widest a tile may get. Past this the artwork stops gaining anything and
  /// the grid just looks sparse.
  static const double _maxTileWidth = 132;

  @override
  Widget build(BuildContext context) {
    // Text scaling is the other half of "fits the screen": a farmer with large
    // system text needs the tile to grow with it, or the crop name clips.
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _maxTileWidth * textScale.clamp(1.0, 1.4),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          // Taller than it is wide, and more so as text grows: the tile holds
          // an icon plus two lines of text, and it is the text that overflows.
          childAspectRatio: 1 / (1.16 + (textScale - 1) * 0.45),
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _CropTile(crop: crops[index]),
          childCount: crops.length,
        ),
      ),
    );
  }
}

class _CropTile extends StatelessWidget {
  const _CropTile({required this.crop});

  final CropCatalogItem crop;

  /// One glyph per crop. Flutter's icon set has no soybean, so these are the
  /// nearest honest stand-ins rather than a wrong-but-pretty picture.
  static const Map<String, IconData> _icons = {
    'soybean': Icons.spa_outlined,
    'rice': Icons.rice_bowl_outlined,
    'wheat': Icons.grass,
    'maize': Icons.local_florist_outlined,
    'gram': Icons.scatter_plot_outlined,
    'mustard': Icons.filter_vintage_outlined,
    'cotton': Icons.cloud_outlined,
    'pigeonpea': Icons.eco_outlined,
  };

  static const Map<String, Color> _colors = {
    'soybean': Color(0xFF7CB342),
    'rice': Color(0xFF26A69A),
    'wheat': Color(0xFFD4A017),
    'maize': Color(0xFFE7B10A),
    'gram': Color(0xFF8D6E63),
    'mustard': Color(0xFFE07B39),
    'cotton': Color(0xFF78909C),
    'pigeonpea': Color(0xFF8E6FD8),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[crop.id] ?? AppColors.primary;
    final radius = BorderRadius.circular(AppRadius.lg);

    return Material(
      color: AppColors.light100,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => CropDetailPage.open(context, cropId: crop.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.light500),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          // LayoutBuilder rather than fixed sizes: the icon circle scales with
          // whatever width the grid handed this tile, so the same code looks
          // right on a 320 dp phone and a 12" tablet.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final glyph = (constraints.maxWidth * 0.42).clamp(32.0, 54.0);
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: glyph,
                    height: glyph,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _icons[crop.id] ?? Icons.eco_outlined,
                      size: glyph * 0.5,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Shrinks the name rather than clipping it: a farmer has to
                  // be able to read which crop they are tapping.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        crop.name,
                        textAlign: TextAlign.center,
                        style: AppTextStyle.textSmSemibold,
                      ),
                    ),
                  ),
                  if (crop.shortLocalName.isNotEmpty)
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          crop.shortLocalName,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark100,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
