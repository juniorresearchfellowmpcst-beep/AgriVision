import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Home dashboard screen.
///
/// Composed entirely from reusable widgets:
///   - [GcsConnectionBanner]   → dark-green header connection pill
///   - [DroneStatusCard]       → Battery / Tank / GPS stat cards
///   - [AppIconButton]         → New Mission CTA (from core/widgets)
///   - [SectionHeader]         → "Recent Missions" + "View Reports"
///   - [MissionListTile]       → each mission row
///   - [AppBottomNavBar]       → bottom navigation (from core/navigation)
///
/// Wire the hardcoded values below to your HomeCubit/HomeBloc state.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // TODO: replace with HomeCubit state
  static const _missions = [
    MissionItem(
      title: 'Block A – North Section',
      date: 'Jun 21, 2026',
      area: '4.2 ha',
      status: MissionStatus.done,
    ),
    MissionItem(
      title: 'Orchard Rows 7–12',
      date: 'Jun 19, 2026',
      area: '1.8 ha',
      status: MissionStatus.done,
    ),
    MissionItem(
      title: 'Paddock 3 – South',
      date: 'Jun 17, 2026',
      area: '6.1 ha',
      status: MissionStatus.partial,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,

      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // ── Dark-green header ────────────────────────────────────
            SliverToBoxAdapter(child: _Header()),
            // spacing between header and cards
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
            // ── Stat cards (overlap header by peeking into it) ───────
            SliverToBoxAdapter(child: _StatusRow()),

            // ── New Mission button ────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.xl,
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
                  onPressed: () {
                    // TODO: navigate to new-mission flow
                  },
                ),
              ),
            ),

            // ── Recent Missions header ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: SectionHeader(
                  title: 'Recent Missions',
                  actionLabel: 'View Reports',
                  onAction: () {
                    // TODO: navigate to reports tab
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            // ── Mission list ──────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              sliver: SliverList.separated(
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm + 2),
                itemCount: _missions.length,
                itemBuilder: (context, index) => MissionListTile(
                  mission: _missions[index],
                  onTap: () {
                    // TODO: navigate to mission detail
                  },
                ),
              ),
            ),

            // bottom padding above nav bar
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private sub-widgets (used only in this file)
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
        AppSpacing.xxl + 8, // extra bottom so cards overlap into it
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
                    // TODO: replace with real date from HomeCubit
                    Text(
                      'Mon, 23 Jun 2026',
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.light100.withOpacity(0.70),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Good morning, Raj', // TODO: from HomeCubit
                      style: AppTextStyle.text2xlBold.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.light100.withOpacity(0.15),
                child: Icon(
                  Icons.person_outline,
                  color: AppColors.light100,
                  size: 20,
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

class _StatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -20),
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
