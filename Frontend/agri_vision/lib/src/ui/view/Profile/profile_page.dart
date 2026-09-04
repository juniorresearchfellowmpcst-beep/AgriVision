import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/auth/auth_cubit.dart';
import 'package:agri_vision/src/ui/cubit/credentials/credentials_cubit.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/missions/missions_cubit.dart';
import 'package:agri_vision/src/ui/cubit/profile/profile_cubit.dart';
import 'package:agri_vision/src/ui/cubit/settings/settings_cubit.dart';

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
/// (GET /api/users/me); credentials from [CredentialsCubit]
/// (GET /api/credentials); notification toggles from [SettingsCubit]
/// (GET/PUT /api/users/me/preferences); recent activity is derived from
/// mission history.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    context.read<ProfileCubit>().load();
    context.read<DroneCubit>().load();
    context.read<MissionsCubit>().load();
    context.read<CredentialsCubit>().load();
    context.read<SettingsCubit>().load();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// Fill in or correct one credential's number and expiry date.
  Future<void> _editCredential(PilotCredentialEntity credential) async {
    final saved = await CredentialEditSheet.show(context, credential: credential);
    if (saved == true && mounted) {
      _showSnack('${credential.label} updated.');
    }
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

            final profile = state.profile ?? PilotProfileEntity.empty();

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
                        BlocBuilder<CredentialsCubit, CredentialsState>(
                          builder: (context, credentialsState) {
                            if (credentialsState.status ==
                                    CredentialsStatus.failure &&
                                credentialsState.credentials.isEmpty) {
                              return SettingsSectionCard(
                                label: 'PILOT CREDENTIALS',
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(AppSpacing.md),
                                    child: Text(
                                      'Could not load credentials.\n'
                                      '${credentialsState.errorMessage}',
                                      style: AppTextStyle.textSmRegular
                                          .copyWith(color: AppColors.dark300),
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SettingsSectionCard(
                                  label: 'PILOT CREDENTIALS',
                                  children: [
                                    for (final c in credentialsState.credentials)
                                      ProfileDetailRow(
                                        icon: c.icon,
                                        label: c.label,
                                        // A seeded-but-empty row should invite
                                        // the operator to complete it rather
                                        // than sit there as a bare dash.
                                        value: c.isBlank
                                            ? 'Tap to add details'
                                            : c.value,
                                        iconBackground: c.status.iconBackground,
                                        iconColor: c.status.iconColor,
                                        trailing: c.isBlank
                                            ? Icon(
                                                Icons.add_circle_outline,
                                                size: 18,
                                                color: AppColors.dark100,
                                              )
                                            : CredentialStatusBadge(
                                                status: c.status,
                                              ),
                                        onTap: () => _editCredential(c),
                                      ),
                                  ],
                                ),
                                if (credentialsState.needsAttention)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.sm,
                                      left: AppSpacing.xs,
                                    ),
                                    child: Text(
                                      credentialsState.expiredCount > 0
                                          ? '${credentialsState.expiredCount} '
                                                'credential(s) have expired — '
                                                'renew before your next flight.'
                                          : '${credentialsState.expiringCount} '
                                                'credential(s) expiring soon.',
                                      style: AppTextStyle.textXsRegular.copyWith(
                                        color: credentialsState.expiredCount > 0
                                            ? AppColors.themeError
                                            : AppColors.themeWarning,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
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
                        // Prefer the drone from /users/me; the status endpoint
                        // is the fallback. Neither invents one — with nothing
                        // paired the card becomes the way to pair.
                        BlocBuilder<DroneCubit, DroneState>(
                          builder: (context, droneState) {
                            final drone = state.drone ?? droneState.drone;
                            if (drone == null) {
                              return DroneConnectCard.unpaired(
                                onConnect: () =>
                                    DroneConnectSheet.show(context),
                              );
                            }
                            return AssignedDroneCard(
                              drone: drone,
                              onTap: () => DroneConnectSheet.show(context),
                            );
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
                        // Server-backed, so they follow the pilot to any
                        // device they sign in on.
                        BlocConsumer<SettingsCubit, SettingsState>(
                          listenWhen: (before, after) =>
                              before.errorMessage != after.errorMessage &&
                              after.errorMessage.isNotEmpty,
                          listener: (context, settings) =>
                              _showSnack(settings.errorMessage),
                          builder: (context, settings) {
                            final prefs = settings.preferences;
                            return SettingsSectionCard(
                              label: 'NOTIFICATION PREFERENCES',
                              children: [
                                ProfileToggleRow(
                                  title: 'Mission Updates',
                                  subtitle: 'Start, complete, and abort events',
                                  value: prefs.missionUpdates,
                                  onChanged: (v) => context
                                      .read<SettingsCubit>()
                                      .setMissionUpdates(v),
                                ),
                                ProfileToggleRow(
                                  title: 'AI Alerts',
                                  subtitle: 'Detections requiring your review',
                                  value: prefs.aiAlerts,
                                  onChanged: (v) => context
                                      .read<SettingsCubit>()
                                      .setAiAlerts(v),
                                ),
                                ProfileToggleRow(
                                  title: 'Field Reports',
                                  subtitle: 'Auto-generated post-mission PDFs',
                                  value: prefs.fieldReports,
                                  onChanged: (v) => context
                                      .read<SettingsCubit>()
                                      .setFieldReports(v),
                                ),
                              ],
                            );
                          },
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
