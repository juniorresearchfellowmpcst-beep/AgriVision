import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  List<MissionReportEntity> get _missions => MissionReportEntity.getDummyData();

  MissionStatus _toStatus(String status) => switch (status.toLowerCase()) {
    'done' => MissionStatus.done,
    'partial' => MissionStatus.partial,
    _ => MissionStatus.inProgress,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── FIXED: Dark-green header ──────────────────────────────
            _Header(),

            // ── FIXED: Stat cards overlapping header bottom edge ──────
            _StatusRow(),

            // ── FIXED: New Mission CTA ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: AppIconButton(
                label: 'New Mission',
                startIcon: Icons.add,
                color: AppColors.dark700,
                pressedColor: AppColors.dark500,
                showBorder: false,
                textColor: AppColors.light100,
                pressedTextColor: AppColors.light100,
                iconColor: AppColors.light100,
                pressedIconColor: AppColors.light100,
                textStyle: AppTextStyle.textLgSemibold,
                width: double.infinity,
                height: 52,
                borderRadius: AppRadius.lg,
                mainAxisAlignment: MainAxisAlignment.center,
                onPressed: () => context
                    .read<BottomNavBarCubit>()
                    .selectMenu(Menu.maps),
              ),
            ),

            // ── FIXED: "Recent Missions" label + "View Reports" ───────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SectionHeader(
                title: 'Recent Missions',
                actionLabel: 'View Reports',
                onAction: () {
                  // TODO: navigate to reports tab
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── SCROLLABLE: Only the missions list scrolls ────────────
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                itemCount: _missions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm + 2),
                itemBuilder: (context, index) {
                  final m = _missions[index];
                  return MissionListTile(
                    mission: MissionItem(
                      title: m.title,
                      date: m.date,
                      area: m.area,
                      status: _toStatus(m.status),
                    ),
                    onTap: () {
                      // TODO: navigate to mission detail
                    },
                  );
                },
              ),
            ),
            SizedBox(
              height: 60,
            ), // extra bottom padding so last item isn't cut off by nav bar
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1F4D38),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl + 14, // extra bottom so stat cards overlap into it
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mon, 23 Jun 2026',
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.light100.withOpacity(0.70),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Good morning, Raj',
                      style: AppTextStyle.text2xlBold.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  );
                },
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: AppColors.light100.withOpacity(0.15),
                  child: const Icon(
                    Icons.person_outline,
                    color: AppColors.light100,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const GcsConnectionBanner(
            gcsId: 'GCS-04',
            frequency: '2.4 GHz',
            signalDbm: '−68 dBm',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      // pull cards up so they overlap the header's bottom padding
      offset: const Offset(0, -22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Expanded(
                child: DroneStatusCard(
                  icon: Icons.battery_5_bar,
                  iconColor: AppColors.themeSuccess,
                  label: 'Battery',
                  value: '84%',
                  progress: 0.84,
                  progressColor: AppColors.themeSuccess,
                ),
              ),
              SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: DroneStatusCard(
                  icon: Icons.water_drop_outlined,
                  iconColor: Color(0xFF2E86DE),
                  label: 'Tank',
                  value: '63%',
                  progress: 0.63,
                  progressColor: Color(0xFF2E86DE),
                ),
              ),
              SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: DroneStatusCard(
                  icon: Icons.signal_cellular_alt,
                  iconColor: AppColors.themeSuccess,
                  label: 'GPS',
                  value: '18',
                  subLabel: 'sats',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
