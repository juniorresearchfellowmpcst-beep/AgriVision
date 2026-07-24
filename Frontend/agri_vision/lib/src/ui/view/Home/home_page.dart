import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';

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
            _Header(firstName: _firstName),

            // ── FIXED: Stat cards overlapping header bottom edge ──────
            const _StatusRow(),

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
                onPressed: () =>
                    context.read<BottomNavBarCubit>().selectMenu(Menu.maps),
              ),
            ),

            // ── FIXED: Plant Disease Scan CTA ─────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: AppIconButton(
                label: 'Scan Plant Disease',
                startIcon: Icons.local_florist_outlined,
                color: AppColors.light100,
                pressedColor: AppColors.primary6,
                borderColor: AppColors.primary3,
                pressedBorderColor: AppColors.primary,
                iconColor: AppColors.primary,
                pressedIconColor: AppColors.primary,
                textColor: AppColors.primary,
                pressedTextColor: AppColors.primary,
                textStyle: AppTextStyle.textLgSemibold,
                width: double.infinity,
                height: 52,
                borderRadius: AppRadius.lg,
                mainAxisAlignment: MainAxisAlignment.center,
                onPressed: () => Navigator.of(
                  context,
                ).pushNamed(AppRouterNames.disease),
              ),
            ),

            // ── FIXED: "Recent Missions" label + "View Reports" ───────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SectionHeader(
                title: 'Recent Missions',
                actionLabel: 'View Reports',
                onAction: () => context
                    .read<BottomNavBarCubit>()
                    .selectMenu(Menu.reports),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── SCROLLABLE: Only the missions list scrolls ────────────
            Expanded(
              child: BlocBuilder<MissionsCubit, MissionsState>(
                builder: (context, state) {
                  if (state.isLoading && state.missions.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.status == MissionsStatus.failure &&
                      state.missions.isEmpty) {
                    // Offline: error + Retry, with the Drone Runner minigame
                    // playable right here in the missions area.
                    return OfflineFallback(
                      message:
                          'Could not load missions.\n${state.errorMessage}',
                      onRetry: () =>
                          context.read<MissionsCubit>().load(refresh: true),
                    );
                  }
                  if (state.missions.isEmpty) {
                    return const _MissionsMessage(
                      icon: Icons.flight_takeoff_rounded,
                      text:
                          'No missions yet.\nPlan your first survey with "New Mission".',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        context.read<MissionsCubit>().load(refresh: true),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
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
                          onTap: () => context
                              .read<BottomNavBarCubit>()
                              .selectMenu(Menu.reports),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(
              height: 60,
            ), // extra bottom padding so last item isn't cut off by nav bar
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MissionsMessage extends StatelessWidget {
  const _MissionsMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: AppColors.dark100),
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
          BlocBuilder<DroneCubit, DroneState>(
            builder: (context, state) {
              final drone = state.drone;
              if (drone == null) {
                return GcsConnectionBanner(
                  gcsId: 'GCS',
                  frequency: '—',
                  signalDbm: '—',
                  isConnected: false,
                );
              }
              return GcsConnectionBanner(
                gcsId: _shortId(drone.unitName),
                frequency: drone.frequency,
                signalDbm: drone.signalDbm,
                isConnected: drone.isConnected,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 'AgriDrone Unit GCS-04' → 'GCS-04' for the compact banner.
  static String _shortId(String unitName) {
    final parts = unitName.trim().split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.last : unitName;
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
            final battery = drone?.batteryPercent ?? 0;
            final tank = drone?.tankPercent ?? 0;
            final gps = drone?.gpsSatellites ?? 0;

            Color batteryColor() {
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
                      value: drone == null ? '—' : '$battery%',
                      progress: battery / 100,
                      progressColor: batteryColor(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: DroneStatusCard(
                      icon: Icons.water_drop_outlined,
                      iconColor: const Color(0xFF2E86DE),
                      label: 'Tank',
                      value: drone == null ? '—' : '$tank%',
                      progress: tank / 100,
                      progressColor: const Color(0xFF2E86DE),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: DroneStatusCard(
                      icon: Icons.signal_cellular_alt,
                      iconColor: AppColors.themeSuccess,
                      label: 'GPS',
                      value: drone == null ? '—' : '$gps',
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
