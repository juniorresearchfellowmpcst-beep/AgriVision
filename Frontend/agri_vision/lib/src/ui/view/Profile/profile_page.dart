import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/auth/auth_cubit.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';
import 'package:agri_vision/src/ui/cubit/profile/profile_cubit.dart';

/// Pilot profile screen, pushed from the Settings page's USER PROFILE row.
///
/// Sections (all built from reusable widgets):
///   Header                → [ProfileHeader]
///   Stats                 → [ProfileStatsCard]
///   PERSONAL DETAILS      → [SettingsSectionCard] + [ProfileDetailRow]
///   PILOT CREDENTIALS     → [SettingsSectionCard] + [ProfileDetailRow] + [CredentialStatusBadge]
///   ASSIGNED DRONE        → [AssignedDroneCard]
///   RECENT ACTIVITY       → [SettingsSectionCard] + [ActivityListTile]
///   NOTIFICATION PREFS    → [SettingsSectionCard] + [ProfileToggleRow]
///   ACCOUNT SECURITY      → [SettingsSectionCard] + [ProfileNavRow]
///   Sign Out              → [SignOutButton]
///
/// Profile, stats and the assigned drone come from [ProfileCubit]
/// (GET /api/users/me); recent activity is derived from mission history.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Static demo credentials until a licensing backend exists.
  List<PilotCredentialEntity> get _credentials =>
      PilotCredentialEntity.getDummyData();

  @override
  void initState() {
    super.initState();
    context.read<ProfileCubit>().load();
    context.read<DroneCubit>().load();
    context.read<MissionsCubit>().load();
  }

  /// Recent missions rendered as the activity feed.
  List<ProfileActivityEntity> _activityFrom(List<MissionReportEntity> missions) {
    return [
      for (final m in missions.take(4))
        ProfileActivityEntity(
          title: switch (m.status.toLowerCase()) {
            'done' => 'Completed mission',
            'partial' => 'Partially completed mission',
            'in_progress' => 'Mission in progress',
            _ => 'Planned mission',
          },
          subtitle: m.title,
          time: m.date,
          type: ActivityType.missionCompleted,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<ProfileCubit, ProfileState>(
          builder: (context, state) {
            if (state.isLoading && state.profile == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final profile =
                state.profile ?? PilotProfileEntity.getDummyData();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── FIXED: Dark-green header ──────────────────────────────
                ProfileHeader(
                  profile: profile,
                  onBack: () => Navigator.of(context).maybePop(),
                  onEdit: () {
                    // TODO: navigate to edit-profile flow
                  },
                ),

                // ── FIXED: Stats card overlapping header bottom edge ──────
                _StatsRow(profile: profile),

                // ── SCROLLABLE: All profile sections ──────────────────────
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () =>
                        context.read<ProfileCubit>().load(refresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
                      children: [
                        // ── PERSONAL DETAILS ─────────────────────────────────
                        SettingsSectionCard(
                          label: 'PERSONAL DETAILS',
                          children: [
                            ProfileDetailRow(
                              icon: Icons.person_outline,
                              label: 'FULL NAME',
                              value: profile.name,
                            ),
                            ProfileDetailRow(
                              icon: Icons.email_outlined,
                              label: 'EMAIL',
                              value: profile.email,
                            ),
                            ProfileDetailRow(
                              icon: Icons.phone_outlined,
                              label: 'PHONE',
                              value: profile.phone,
                            ),
                            ProfileDetailRow(
                              icon: Icons.location_on_outlined,
                              label: 'LOCATION',
                              value: profile.location,
                            ),
                            ProfileDetailRow(
                              icon: Icons.apartment_outlined,
                              label: 'ORGANISATION',
                              value: profile.organisation,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── PILOT CREDENTIALS ────────────────────────────────
                        SettingsSectionCard(
                          label: 'PILOT CREDENTIALS',
                          children: [
                            for (final c in _credentials)
                              ProfileDetailRow(
                                icon: c.icon,
                                label: c.label,
                                value: c.value,
                                iconBackground: c.status.iconBackground,
                                iconColor: c.status.iconColor,
                                trailing:
                                    CredentialStatusBadge(status: c.status),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── ASSIGNED DRONE ───────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.xs,
                            bottom: AppSpacing.sm,
                          ),
                          child: Text(
                            'ASSIGNED DRONE',
                            style: AppTextStyle.textXsSemibold.copyWith(
                              color: AppColors.dark100,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        // Prefer the drone from /users/me; otherwise show the
                        // shared unit reported by the drone status endpoint.
                        BlocBuilder<DroneCubit, DroneState>(
                          builder: (context, droneState) {
                            final drone = state.drone ?? droneState.drone;
                            if (drone == null) {
                              return Text(
                                'No drone paired yet.',
                                style: AppTextStyle.textSmRegular.copyWith(
                                  color: AppColors.dark300,
                                ),
                              );
                            }
                            return AssignedDroneCard(drone: drone);
                          },
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── RECENT ACTIVITY ──────────────────────────────────
                        BlocBuilder<MissionsCubit, MissionsState>(
                          builder: (context, missionsState) {
                            final activity =
                                _activityFrom(missionsState.missions);
                            if (activity.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SettingsSectionCard(
                                  label: 'RECENT ACTIVITY',
                                  children: [
                                    for (final a in activity)
                                      ActivityListTile(activity: a),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xl),
                              ],
                            );
                          },
                        ),

                        // ── NOTIFICATION PREFERENCES ─────────────────────────
                        SettingsSectionCard(
                          label: 'NOTIFICATION PREFERENCES',
                          children: [
                            ProfileToggleRow(
                              title: 'Mission Updates',
                              subtitle: 'Start, complete, and abort events',
                              value: state.missionUpdates,
                              onChanged: (v) => context
                                  .read<ProfileCubit>()
                                  .setMissionUpdates(v),
                            ),
                            ProfileToggleRow(
                              title: 'AI Alerts',
                              subtitle: 'Detections requiring your review',
                              value: state.aiAlerts,
                              onChanged: (v) =>
                                  context.read<ProfileCubit>().setAiAlerts(v),
                            ),
                            ProfileToggleRow(
                              title: 'Field Reports',
                              subtitle: 'Auto-generated post-mission PDFs',
                              value: state.fieldReports,
                              onChanged: (v) => context
                                  .read<ProfileCubit>()
                                  .setFieldReports(v),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── ACCOUNT SECURITY ─────────────────────────────────
                        SettingsSectionCard(
                          label: 'ACCOUNT SECURITY',
                          children: [
                            ProfileNavRow(
                              icon: Icons.lock_outline,
                              title: 'Change Password',
                              subtitle: 'Reset via email OTP',
                              onTap: () => Navigator.of(context)
                                  .pushNamed(AppRouterNames.forgotPassword),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── SIGN OUT ──────────────────────────────────────────
                        SignOutButton(
                          onTap: () async {
                            await context.read<AuthCubit>().signOut();
                            if (!context.mounted) return;
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              AppRouterNames.signIn,
                              (route) => false,
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Center(
                          child: Text(
                            'AgriDrone GCS v2.4.1 · © 2026 Agridrone Systems',
                            style: AppTextStyle.textXsRegular.copyWith(
                              color: AppColors.dark100,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.profile});

  final PilotProfileEntity profile;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      // pull the card up so it overlaps the header's bottom padding
      offset: const Offset(0, -22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ProfileStatsCard(
          missionsFlown: profile.missionsFlown,
          areaFlownHa: profile.areaFlownHa,
          airTimeHours: profile.airTimeHours,
        ),
      ),
    );
  }
}
