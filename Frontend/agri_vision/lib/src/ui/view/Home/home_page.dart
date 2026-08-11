import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';

/// Home / dashboard.
///
/// Layout, top to bottom:
///   [_Header]        → greeting + avatar + link status, on the green banner
///   [_StatusRow]     → battery / tank / GPS cards lifted onto the banner edge
///   New Mission CTA  → the one primary action
///   [_QuickActions]  → 2×2 grid of the capture / scan / analysis entry points
///   Recent Missions  → the mission history list
///
/// The whole screen is one scroll view rather than a fixed column with a
/// scrolling tail: on a short phone the old layout squeezed the mission list
/// into a couple of centimetres, and pull-to-refresh only worked over the list.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _firstName = '';

  @override
  void initState() {
    super.initState();
    context.read<DroneCubit>().load();
    context.read<MissionsCubit>().load();
    _loadStoredUser();
  }

  Future<void> _loadStoredUser() async {
    final user = await AuthService().getStoredUser();
    if (!mounted || user == null) return;
    final name = user['username']?.toString() ?? '';
    if (name.isEmpty) return;
    setState(() => _firstName = name.trim().split(RegExp(r'\s+')).first);
  }

  MissionStatus _toStatus(String status) => switch (status.toLowerCase()) {
    'done' => MissionStatus.done,
    'partial' => MissionStatus.partial,
    _ => MissionStatus.inProgress,
  };

  /// Pull-to-refresh re-reads the link too: it's the operator's way to
  /// re-check a drone that has gone quiet.
  Future<void> _refresh() => Future.wait([
    context.read<MissionsCubit>().load(refresh: true),
    context.read<DroneCubit>().load(refresh: true),
  ]);

  void _openReports() =>
      context.read<BottomNavBarCubit>().selectMenu(Menu.reports);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: MediaQuery.paddingOf(context).top + AppSpacing.xxl,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Banner and stat cards share one sliver on purpose: the cards are
            // lifted onto the banner's bottom edge, and a viewport paints its
            // slivers back-to-front, so as separate slivers the banner would
            // cover them. Inside a Column the cards paint last, on top.
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(firstName: _firstName),
                  const _StatusRow(),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
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
                  height: 54,
                  borderRadius: AppRadius.lg,
                  mainAxisAlignment: MainAxisAlignment.center,
                  onPressed: () =>
                      context.read<BottomNavBarCubit>().selectMenu(Menu.maps),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: _QuickActions()),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: SectionHeader(
                  title: 'Recent Missions',
                  actionLabel: 'View Reports',
                  onAction: _openReports,
                ),
              ),
            ),

            BlocBuilder<MissionsCubit, MissionsState>(
              builder: (context, state) {
                if (state.isLoading && state.missions.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                if (state.status == MissionsStatus.failure &&
                    state.missions.isEmpty) {
                  // Offline: error + Retry, with the Drone Runner minigame
                  // playable right here in the missions area.
                  return SliverToBoxAdapter(
                    child: OfflineFallback(
                      compact: true,
                      message: 'Could not load missions.\n${state.errorMessage}',
                      onRetry: () =>
                          context.read<MissionsCubit>().load(refresh: true),
                    ),
                  );
                }
                if (state.missions.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: _MissionsMessage(
                      text:
                          'No missions yet.\nPlan your first survey with "New Mission".',
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  sliver: SliverList.separated(
                    itemCount: state.missions.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm + 2),
                    itemBuilder: (context, index) {
                      final m = state.missions[index];
                      return MissionListTile(
                        mission: MissionItem(
                          title: m.title,
                          date: m.date,
                          area: m.area,
                          status: _toStatus(m.status),
                        ),
                        onTap: _openReports,
                      );
                    },
                  ),
                );
              },
            ),

            // Clears the bottom nav bar so the last tile is never half-hidden.
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MissionsMessage extends StatelessWidget {
  const _MissionsMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          const DroneIcon(size: 40, color: AppColors.dark100),
          const SizedBox(height: AppSpacing.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.firstName});

  final String firstName;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The banner runs under the status bar, so its icons have to go light.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF245C43), Color(0xFF1A3A28)],
          ),
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(AppRadius.xl + 8),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          // Fill the status-bar strip rather than leaving a pale band above
          // the banner, which is what a SafeArea around the whole page gave.
          MediaQuery.paddingOf(context).top + AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl + 14, // extra bottom so the stat cards overlap into it
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
                        DateFormat('EEE, d MMM yyyy').format(DateTime.now()),
                        style: AppTextStyle.textSmRegular.copyWith(
                          color: AppColors.light100.withOpacity(0.70),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        firstName.isEmpty ? _greeting : '$_greeting, $firstName',
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
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.light100.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.light100.withOpacity(0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      color: AppColors.light100,
                      size: 21,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            BlocBuilder<DroneCubit, DroneState>(
              builder: (context, state) {
                final drone = state.drone;
                return GcsConnectionBanner(
                  gcsId: drone?.shortId ?? 'No drone',
                  frequency: drone?.frequency ?? '—',
                  signalDbm: drone?.signalLabel ?? '—',
                  isConnected: drone?.isConnected ?? false,
                  onTap: () => DroneConnectSheet.show(context),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      // pull cards up so they overlap the header's bottom padding
      offset: const Offset(0, -22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: BlocBuilder<DroneCubit, DroneState>(
          builder: (context, state) {
            final drone = state.drone;

            // Nothing paired, or paired but silent: the gauges have no source,
            // so the row becomes the way to give them one.
            if (drone == null) {
              return DroneConnectCard.unpaired(
                onConnect: () => DroneConnectSheet.show(context),
              );
            }
            if (!drone.isConnected) {
              return DroneConnectCard.offline(
                unitName: drone.shortId,
                onConnect: () => DroneConnectSheet.show(context),
              );
            }

            final battery = drone.batteryPercent;
            final tank = drone.tankPercent;

            Color batteryColor() {
              if (battery == null) return AppColors.dark100;
              if (battery > 50) return AppColors.themeSuccess;
              if (battery > 20) return AppColors.themeWarning;
              return AppColors.themeError;
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: DroneStatusCard(
                      icon: Icons.battery_5_bar,
                      iconColor: batteryColor(),
                      label: 'Battery',
                      value: drone.batteryLabel,
                      // No bar for a reading the aircraft isn't sending —
                      // an empty bar reads as "flat", which is a lie.
                      progress: battery == null ? null : battery / 100,
                      progressColor: batteryColor(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: DroneStatusCard(
                      icon: Icons.water_drop_outlined,
                      iconColor: const Color(0xFF2E86DE),
                      label: 'Tank',
                      value: drone.tankLabel,
                      progress: tank == null ? null : tank / 100,
                      progressColor: const Color(0xFF2E86DE),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: DroneStatusCard(
                      icon: Icons.signal_cellular_alt,
                      iconColor: AppColors.themeSuccess,
                      label: 'GPS',
                      value: drone.gpsLabel,
                      subLabel: 'sats',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// The four working entry points, as a 2×2 grid of cards.
///
/// These used to be four identical full-width buttons stacked down the page,
/// which read as a settings menu and pushed the mission list off screen.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    void go(String route) => Navigator.of(context).pushNamed(route);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'QUICK ACTIONS',
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.dark100,
                letterSpacing: 0.8,
              ),
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.camera_alt_outlined,
                    accent: const Color(0xFF2E86DE),
                    label: 'Capture & Spray',
                    hint: 'Drone imagery, then a targeted dose',
                    onTap: () => go(AppRouterNames.capture),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.grass_outlined,
                    accent: AppColors.primary,
                    label: 'Weed & Disease',
                    hint: 'Scan a captured field session',
                    onTap: () => go(AppRouterNames.fieldScan),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.local_florist_outlined,
                    accent: const Color(0xFFE7B10A),
                    label: 'Plant Disease',
                    hint: 'Photograph a leaf to identify it',
                    onTap: () => go(AppRouterNames.disease),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.insights_outlined,
                    accent: const Color(0xFF8E6FD8),
                    label: 'Crop Analysis',
                    hint: 'NDVI and crop-stress indices',
                    onTap: () => go(AppRouterNames.analysis),
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

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);

    return DecoratedBox(
      // Shadow lives outside the Material so the ink ripple can be clipped to
      // the rounded corners without clipping the shadow away with it.
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppColors.dark900.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: AppColors.light100,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  label,
                  style: AppTextStyle.textMdSemibold,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
