import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/auth/auth_cubit.dart';

/// Settings screen.
///
/// Sections (all built from reusable widgets):
///   CONNECTIVITY   → [SettingsNavRow] × 2 + [SettingsToggleRow]
///   SYNC QUEUE     → [SyncQueueRow] × 3
///   DRONE PAIRING  → [DronePairingCard]
///   USER PROFILE   → [UserProfileRow] + [SettingsToggleRow]
///   Sign Out       → [SignOutButton]
///
/// All values below should be driven by a SettingsCubit.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // TODO: move to SettingsCubit
  bool _autoSync = true;
  bool _pushNotifications = true;

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
            _SettingsAppBar(),
            const SizedBox(height: AppSpacing.sm),

            // ── SCROLLABLE: All settings sections ─────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: [
                  // ── CONNECTIVITY ─────────────────────────────────────
                  SettingsSectionCard(
                    label: 'CONNECTIVITY',
                    children: [
                      SettingsNavRow(
                        icon: Icons.wifi_rounded,
                        label: 'Network',
                        iconColor: AppColors.dark500,
                        trailing: Text(
                          'Online',
                          style: AppTextStyle.textSmSemibold.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        onTap: () {},
                      ),
                      SettingsNavRow(
                        icon: Icons.sensors_rounded,
                        label: 'Drone Telemetry',
                        iconColor: AppColors.dark500,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'GCS-04',
                              style: AppTextStyle.textSmSemibold.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                        onTap: () {},
                      ),
                      SettingsToggleRow(
                        icon: Icons.sync_rounded,
                        label: 'Auto Sync',
                        iconColor: AppColors.dark500,
                        value: _autoSync,
                        onChanged: (v) => setState(() => _autoSync = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── SYNC QUEUE ────────────────────────────────────────
                  SettingsSectionCard(
                    label: 'SYNC QUEUE',
                    children: const [
                      SyncQueueRow(
                        label: 'Mission logs',
                        count: 3,
                        status: SyncStatus.synced,
                      ),
                      SyncQueueRow(
                        label: 'Detection frames',
                        count: 47,
                        status: SyncStatus.synced,
                      ),
                      SyncQueueRow(
                        label: 'Field reports',
                        count: 1,
                        status: SyncStatus.pending,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── DRONE PAIRING ─────────────────────────────────────
                  SettingsSectionCard(
                    label: 'DRONE PAIRING',
                    children: [
                      DronePairingCard(
                        unitName: 'AgriDrone Unit GCS-04',
                        serialNumber: 'ADU-2024-04-7832',
                        isOnline: true,
                        onPairNew: () {
                          // TODO: open drone pairing flow
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── USER PROFILE ──────────────────────────────────────
                  SettingsSectionCard(
                    label: 'USER PROFILE',
                    children: [
                      UserProfileRow(
                        initials: 'RP',
                        name: 'Raj Patel',
                        role: 'Operator',
                        email: 'raj.patel@agridrone.in',
                        onTap: () {
                          Navigator.of(
                            context,
                          ).pushNamed(AppRouterNames.profile);
                        },
                      ),
                      SettingsToggleRow(
                        icon: Icons.notifications_outlined,
                        label: 'Push Notifications',
                        iconColor: AppColors.dark500,
                        value: _pushNotifications,
                        onChanged: (v) =>
                            setState(() => _pushNotifications = v),
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

class _SettingsAppBar extends StatelessWidget {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: AppTextStyle.displayH3),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'AgriDrone GCS v2.4.1 · Build 2024-06-23',
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
        ],
      ),
    );
  }
}
