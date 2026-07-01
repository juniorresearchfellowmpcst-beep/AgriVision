import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// AI Alerts screen.
///
/// Layout:
///   - Fixed custom app bar: "AI Alerts" title + [AlertActiveChip]
///     + mission context subtitle ("Block A Mission · date · GCS-04")
///   - Scrollable list of [AlertListTile] cards
///   - [AppBottomNavBar] with Alerts tab pre-selected
///
/// All hardcoded values below should be wired to an AlertsCubit
/// following the same pattern as HomeCubit.
class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  // TODO: replace with AlertsCubit state
  static final List<AlertEntity> _alerts = AlertEntity.getDummyData();
  static const int _activeCount = 5;
  static const String _mission = 'Block A Mission';
  static const String _date = '23 Jun 2026';
  static const String _gcsId = 'GCS-04';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── FIXED: App bar ────────────────────────────────────────
            _AlertsAppBar(
              activeCount: _activeCount,
              mission: _mission,
              date: _date,
              gcsId: _gcsId,
            ),
            const SizedBox(height: AppSpacing.sm),

            // ── SCROLLABLE: Alert list ────────────────────────────────
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                itemCount: _alerts.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm + 2),
                itemBuilder: (context, index) => AlertListTile(
                  alert: _alerts[index],
                  onTap: () {
                    // TODO: navigate to alert detail
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AlertsAppBar extends StatelessWidget {
  const _AlertsAppBar({
    required this.activeCount,
    required this.mission,
    required this.date,
    required this.gcsId,
  });

  final int activeCount;
  final String mission;
  final String date;
  final String gcsId;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.tertiary,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('AI Alerts', style: AppTextStyle.displayH3),
              AlertActiveChip(count: activeCount),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // subtitle: mission · date · GCS ID
          Text(
            '$mission · $date · $gcsId',
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
        ],
      ),
    );
  }
}
