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
/// The crop comes first and is not optional decoration. It is part of the
/// diagnosis: the same yellowing is yellow rust in wheat and yellow mosaic in
/// soybean, and a herbicide that clears one crop will kill another.
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
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.light100,
        elevation: 0,
        title: Text(
          'Scan with Phone',
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
                  ? 'Could not load the crop list.'
                  : state.errorMessage,
              onRetry: () => context.read<CropCubit>().load(refresh: true),
            );
          }

          final tiles = state.tiles;
          final inSeason = tiles.where((c) => c.inSeason == true).toList();
          final rest = tiles.where((c) => c.inSeason != true).toList();

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => context.read<CropCubit>().load(refresh: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: _Intro()),

                // In-season crops first. In August a farmer here is looking at
                // soybean and paddy, and scrolling past wheat to reach it every
                // time is a small daily tax.
                if (inSeason.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: _SectionHeader(
                      'IN SEASON NOW',
                      hint: 'What is usually in the ground this month',
                    ),
                  ),
                  _CropGrid(crops: inSeason),
                ],
                if (rest.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      inSeason.isEmpty ? 'CROPS' : 'OTHER CROPS',
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
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
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
                Text(
                  'No drone needed',
                  style: AppTextStyle.textMdSemibold,
                ),
                const SizedBox(height: 2),
                Text(
                  'Pick your crop, photograph the plant, and get the diagnosis '
                  'with what to spray for it.',
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

class _CropGrid extends StatelessWidget {
  const _CropGrid({required this.crops});

  final List<CropCatalogItem> crops;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.86,
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
    'weeds': Icons.grass_outlined,
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
    'weeds': Color(0xFFD64545),
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
            border: Border.all(
              // The Weeds tile is not a crop, and the grid says so quietly
              // rather than hiding it somewhere else in the app.
              color: crop.isWeeds ? color.withOpacity(0.4) : AppColors.light500,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _icons[crop.id] ?? Icons.eco_outlined,
                  size: 24,
                  color: color,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                crop.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.textSmSemibold,
              ),
              if (crop.shortLocalName.isNotEmpty)
                Text(
                  crop.shortLocalName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark100,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                crop.isWeeds
                    ? '${crop.weedCount} weeds'
                    : '${crop.diseaseCount} diseases',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: color,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
