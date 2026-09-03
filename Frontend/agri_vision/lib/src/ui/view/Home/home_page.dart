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
///   Survey Flight CTA→ the one primary action
///   [_PhoneScanCard] → the drone-free path: pick a crop, photograph a plant
///   [_QuickActions]  → 2×2 grid of the capture / scan / analysis entry points
///   Recent Missions  → the mission history list
///
/// The phone-scan card sits above the quick actions and outside them on
/// purpose. Everything else on this screen needs an aircraft; that one needs
/// a phone, and a farmer standing in a field with a suspicious leaf should not
/// have to work out which of six drone tiles is the one that does not fly.
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
                child: Column(
                  children: [
                    // The primary action is the whole job — fly, scan, read
                    // the report, spray — rather than just planning a path,
                    // which was only ever its first step. It leads on colour
                    // rather than on size: the same metrics as the button
                    // below it, so the pair reads as one stack instead of two
                    // mismatched controls.
                    AppIconButton(
                      label: context.l10n.startSurveyFlight,
                      startIcon: Icons.flight_takeoff,
                      color: AppColors.primary,
                      pressedColor: AppColors.primary6,
                      showBorder: false,
                      textColor: AppColors.light100,
                      pressedTextColor: AppColors.light100,
                      iconColor: AppColors.light100,
                      pressedIconColor: AppColors.light100,
                      textStyle: AppTextStyle.textMdSemibold,
                      width: double.infinity,
                      height: 48,
                      borderRadius: AppRadius.lg,
                      mainAxisAlignment: MainAxisAlignment.center,
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamed(AppRouterNames.survey),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppIconButton(
                      label: context.l10n.planMissionPath,
                      startIcon: Icons.add_location_alt_outlined,
                      color: AppColors.dark700,
                      pressedColor: AppColors.dark500,
                      showBorder: false,
                      textColor: AppColors.light100,
                      pressedTextColor: AppColors.light100,
                      iconColor: AppColors.light100,
                      pressedIconColor: AppColors.light100,
                      textStyle: AppTextStyle.textMdSemibold,
                      width: double.infinity,
                      height: 48,
                      borderRadius: AppRadius.lg,
                      mainAxisAlignment: MainAxisAlignment.center,
                      onPressed: () =>
                          context.read<BottomNavBarCubit>().selectMenu(Menu.maps),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: _PhoneScanCard()),

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
                  title: context.l10n.recentMissions,
                  actionLabel: context.l10n.viewReports,
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
                  return SliverToBoxAdapter(
                    child: _MissionsMessage(text: context.l10n.noMissionsYet),
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

  String _greeting(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour < 12) return context.l10n.goodMorning;
    if (hour < 17) return context.l10n.goodAfternoon;
    return context.l10n.goodEvening;
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
                        firstName.isEmpty
                            ? _greeting(context)
                            : '${_greeting(context)}, $firstName',
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
                      label: context.l10n.battery,
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
                      label: context.l10n.tank,
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
                      label: context.l10n.gps,
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

/// The drone-free path, given its own card above the quick actions.
///
/// Everything else on this screen needs an aircraft. This needs a phone: pick
/// the crop, photograph the plant, read the diagnosis and what to spray for
/// it. It is separate from the drone tiles rather than hidden among them
/// because a farmer holding a suspicious leaf should not have to work out
/// which of six tiles is the one that does not fly.
class _PhoneScanCard extends StatelessWidget {
  const _PhoneScanCard();

  /// The crops shown as a preview row; the full list is behind the card.
  ///
  /// Ordered by how much of MP is under them, so the first chips are the ones
  /// most people tapping this card are looking for. How many actually render
  /// depends on the width available — see [build].
  static const List<({String label, IconData icon, Color color})> _preview = [
    (label: 'Soybean', icon: Icons.spa_outlined, color: Color(0xFF7CB342)),
    (label: 'Wheat', icon: Icons.grass, color: Color(0xFFD4A017)),
    (label: 'Rice', icon: Icons.rice_bowl_outlined, color: Color(0xFF26A69A)),
    (label: 'Maize', icon: Icons.local_florist_outlined, color: Color(0xFFE7B10A)),
    (label: 'Gram', icon: Icons.scatter_plot_outlined, color: Color(0xFF8D6E63)),
  ];

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: DecoratedBox(
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
            onTap: () =>
                Navigator.of(context).pushNamed(AppRouterNames.cropScan),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 21,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.scanWithPhoneCta,
                              style: AppTextStyle.textMdSemibold,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.scanWithPhoneHint,
                              style: AppTextStyle.textXsRegular.copyWith(
                                color: AppColors.dark300,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.dark100,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Five fixed chips crushed the labels on a 320 dp phone and
                  // looked sparse on a tablet. Fit as many as the row can hold
                  // at a readable size instead, and drop the rest — this is a
                  // preview of the picker, not the picker.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const minChip = 56.0;
                      final scale =
                          MediaQuery.textScalerOf(context).scale(1.0);
                      final fits = ((constraints.maxWidth + AppSpacing.sm) /
                              ((minChip * scale) + AppSpacing.sm))
                          .floor();
                      final shown = _preview.take(
                        fits.clamp(2, _preview.length),
                      ).toList();

                      return Row(
                        children: [
                          for (final crop in shown) ...[
                            Expanded(child: _CropChip(crop: crop)),
                            if (crop != shown.last)
                              const SizedBox(width: AppSpacing.sm),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropChip extends StatelessWidget {
  const _CropChip({required this.crop});

  final ({String label, IconData icon, Color color}) crop;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: crop.color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(crop.icon, size: 19, color: crop.color),
        ),
        const SizedBox(height: 4),
        // Scales the label down rather than truncating "Soybean" to "Soy…",
        // which is the sort of detail that makes a build look unfinished.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            crop.label,
            maxLines: 1,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// The drone entry points, as a grid of cards.
///
/// These used to be identical full-width buttons stacked down the page, which
/// read as a settings menu and pushed the mission list off screen. Everything
/// here needs an aircraft — the phone-only path is [_PhoneScanCard], above.
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
              context.l10n.quickActions,
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
                    label: context.l10n.captureAndSpray,
                    hint: context.l10n.captureAndSprayHint,
                    onTap: () => go(AppRouterNames.capture),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.grass_outlined,
                    accent: AppColors.primary,
                    label: context.l10n.weedAndDisease,
                    hint: context.l10n.weedAndDiseaseHint,
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
                    label: context.l10n.plantDisease,
                    hint: context.l10n.plantDiseaseHint,
                    onTap: () => go(AppRouterNames.disease),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.insights_outlined,
                    accent: const Color(0xFF8E6FD8),
                    label: context.l10n.cropAnalysis,
                    hint: context.l10n.cropAnalysisHint,
                    onTap: () => go(AppRouterNames.analysis),
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
                    icon: Icons.videocam_outlined,
                    accent: const Color(0xFFD64545),
                    label: context.l10n.liveFeed,
                    hint: context.l10n.liveFeedHint,
                    onTap: () => go(AppRouterNames.liveFeed),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.summarize_outlined,
                    accent: AppColors.darkGreen,
                    label: context.l10n.surveyReports,
                    hint: context.l10n.surveyReportsHint,
                    onTap: () => go(AppRouterNames.survey),
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
