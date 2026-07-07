import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/auth/auth_cubit.dart';

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
/// All values below should be driven by a ProfileCubit.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // TODO: move to ProfileCubit
  bool _missionUpdates = true;
  bool _aiAlerts = true;
  bool _fieldReports = false;

  PilotProfileEntity get _profile => PilotProfileEntity.getDummyData();
  List<PilotCredentialEntity> get _credentials =>
      PilotCredentialEntity.getDummyData();
  AssignedDroneEntity get _drone => AssignedDroneEntity.getDummyData();
  List<ProfileActivityEntity> get _activity =>
      ProfileActivityEntity.getDummyData();

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
            ProfileHeader(
              profile: _profile,
              onBack: () => Navigator.of(context).maybePop(),
              onEdit: () {
                // TODO: navigate to edit-profile flow
              },
            ),

            // ── FIXED: Stats card overlapping header bottom edge ──────
            _StatsRow(profile: _profile),

            // ── SCROLLABLE: All profile sections ──────────────────────
            Expanded(
              child: ListView(
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
                        value: _profile.name,
                      ),
                      ProfileDetailRow(
                        icon: Icons.email_outlined,
                        label: 'EMAIL',
                        value: _profile.email,
                      ),
                      ProfileDetailRow(
                        icon: Icons.phone_outlined,
                        label: 'PHONE',
                        value: _profile.phone,
                      ),
                      ProfileDetailRow(
                        icon: Icons.location_on_outlined,
                        label: 'LOCATION',
                        value: _profile.location,
                      ),
                      ProfileDetailRow(
                        icon: Icons.apartment_outlined,
                        label: 'ORGANISATION',
                        value: _profile.organisation,
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
                          trailing: CredentialStatusBadge(status: c.status),
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
                  AssignedDroneCard(drone: _drone),
                  const SizedBox(height: AppSpacing.xl),

                  // ── RECENT ACTIVITY ──────────────────────────────────
                  SettingsSectionCard(
                    label: 'RECENT ACTIVITY',
                    children: [
                      for (final a in _activity) ActivityListTile(activity: a),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── NOTIFICATION PREFERENCES ─────────────────────────
                  SettingsSectionCard(
                    label: 'NOTIFICATION PREFERENCES',
                    children: [
                      ProfileToggleRow(
                        title: 'Mission Updates',
                        subtitle: 'Start, complete, and abort events',
                        value: _missionUpdates,
                        onChanged: (v) => setState(() => _missionUpdates = v),
                      ),
                      ProfileToggleRow(
                        title: 'AI Alerts',
                        subtitle: 'Detections requiring your review',
                        value: _aiAlerts,
                        onChanged: (v) => setState(() => _aiAlerts = v),
                      ),
                      ProfileToggleRow(
                        title: 'Field Reports',
                        subtitle: 'Auto-generated post-mission PDFs',
                        value: _fieldReports,
                        onChanged: (v) => setState(() => _fieldReports = v),
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
                        subtitle: 'Last changed 45 days ago',
                        onTap: () {
                          // TODO: navigate to change-password flow
                        },
                      ),
                      ProfileNavRow(
                        icon: Icons.shield_outlined,
                        title: 'Two-Factor Auth',
                        subtitle: 'SMS · +91 982xx xx712 · Active',
                        onTap: () {
                          // TODO: navigate to two-factor auth flow
                        },
                      ),
                      ProfileNavRow(
                        icon: Icons.sync_rounded,
                        title: 'Active Sessions',
                        subtitle: '2 devices · Tap to review',
                        onTap: () {
                          // TODO: navigate to active-sessions flow
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── SIGN OUT ──────────────────────────────────────────
                  SignOutButton(
                    onTap: () async {
                      await context.read<AuthCubit>().signOut();
                      if (!context.mounted) return;
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil(
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
          ],
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
