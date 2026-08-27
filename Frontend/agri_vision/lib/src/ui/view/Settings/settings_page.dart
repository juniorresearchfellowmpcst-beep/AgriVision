import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/auth/auth_cubit.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';
import 'package:agri_vision/src/ui/cubit/settings/settings_cubit.dart';
import 'package:agri_vision/src/ui/cubit/system/system_cubit.dart';

/// Settings screen.
///
/// Sections (all built from reusable widgets):
///   CONNECTIVITY   → [SettingsNavRow] × 2 + [SettingsToggleRow]
///   SERVER LINKS   → [ConnectionLinksCard] — the addresses other
///                    software (a second handset, Mission Planner,
///                    QGroundControl) needs in order to reach this backend
///   SYNC QUEUE     → [SyncQueueRow] per record type
///   DRONE PAIRING  → [DronePairingCard]
///   USER PROFILE   → [UserProfileRow] + [SettingsToggleRow]
///   Sign Out       → [SignOutButton]
///
/// Toggles are server-backed via [SettingsCubit] (they follow the pilot to
/// any device); the sync queue reports what the backend actually holds.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Signed-in user, loaded from local storage. Blank until it arrives — an
  // invented name here would be indistinguishable from a real one.
  String _userName = '—';
  String _userEmail = '—';

  @override
  void initState() {
    super.initState();
    _loadStoredUser();
    context.read<DroneCubit>().load();
    context.read<SettingsCubit>().load();
    context.read<SystemCubit>().load();
  }

  Future<void> _loadStoredUser() async {
    final user = await AuthService().getStoredUser();
    if (!mounted || user == null) return;

    setState(() {
      _userName = user['username']?.toString() ?? _userName;
      _userEmail = user['email']?.toString() ?? _userEmail;
    });
  }

  String get _userInitials {
    final parts = _userName.trim().split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '?';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

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
            const _SettingsAppBar(),

            // ── SCROLLABLE: All settings sections ─────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  // Clears the bottom nav bar — at the old 24px the Sign Out
                  // button sat underneath it.
                  90,
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
                        trailing: BlocBuilder<DroneCubit, DroneState>(
                          builder: (context, state) {
                            final drone = state.drone;
                            final connected = drone?.isConnected ?? false;
                            final label = drone == null
                                ? 'Not paired'
                                : drone.shortId;
                            final color = connected
                                ? AppColors.primary
                                : AppColors.themeError;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // A long unit name would otherwise push the
                                // tick off the row and overflow the card.
                                Flexible(
                                  child: Text(
                                    label,
                                    style: AppTextStyle.textSmSemibold.copyWith(
                                      color: color,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  connected
                                      ? Icons.check_rounded
                                      : Icons.close_rounded,
                                  size: 14,
                                  color: color,
                                ),
                              ],
                            );
                          },
                        ),
                        onTap: () => DroneConnectSheet.show(context),
                      ),
                      BlocBuilder<SettingsCubit, SettingsState>(
                        builder: (context, settings) => SettingsToggleRow(
                          icon: Icons.sync_rounded,
                          label: 'Auto Sync',
                          iconColor: AppColors.dark500,
                          value: settings.preferences.autoSync,
                          onChanged: (v) =>
                              context.read<SettingsCubit>().setAutoSync(v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── SERVER LINKS ──────────────────────────────────────
                  // Where this backend is reachable. Two audiences: the app on
                  // another handset needs the API URL; a ground station needs
                  // a UDP target to send telemetry to.
                  BlocBuilder<SystemCubit, SystemState>(
                    builder: (context, system) => SettingsSectionCard(
                      label: 'SERVER LINKS',
                      children: [
                        ConnectionLinksCard(
                          links: system.links,
                          isLoading: system.isLoading,
                          errorMessage: system.errorMessage,
                          onRefresh: () =>
                              context.read<SystemCubit>().load(refresh: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── SYNC QUEUE ────────────────────────────────────────
                  // Real per-record-type counts from the backend; 'pending'
                  // means the server still considers a record open.
                  BlocConsumer<SettingsCubit, SettingsState>(
                    listenWhen: (before, after) =>
                        before.errorMessage != after.errorMessage &&
                        after.errorMessage.isNotEmpty,
                    listener: (context, settings) => ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(settings.errorMessage),
                          behavior: SnackBarBehavior.floating,
                        ),
                      ),
                    builder: (context, settings) {
                      return SettingsSectionCard(
                        label: 'SYNC QUEUE',
                        children: [
                          if (!settings.syncLoaded)
                            const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          else if (settings.syncItems.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'Sign in to see what has been synced.',
                                style: AppTextStyle.textSmRegular.copyWith(
                                  color: AppColors.dark300,
                                ),
                              ),
                            )
                          else
                            for (final item in settings.syncItems)
                              SyncQueueRow(
                                label: item.label,
                                count: item.displayCount,
                                status: item.isPending
                                    ? SyncStatus.pending
                                    : SyncStatus.synced,
                              ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── DRONE PAIRING ─────────────────────────────────────
                  SettingsSectionCard(
                    label: 'DRONE PAIRING',
                    children: [
                      BlocBuilder<DroneCubit, DroneState>(
                        builder: (context, state) {
                          final drone = state.drone;
                          return DronePairingCard(
                            unitName: drone?.unitName,
                            serialNumber: drone?.serialNumber,
                            isOnline: drone?.isConnected ?? false,
                            onPairNew: () => DroneConnectSheet.show(context),
                          );
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
                        initials: _userInitials,
                        name: _userName,
                        role: 'Operator',
                        email: _userEmail,
                        onTap: () {
                          Navigator.of(
                            context,
                          ).pushNamed(AppRouterNames.profile);
                        },
                      ),
                      BlocBuilder<SettingsCubit, SettingsState>(
                        builder: (context, settings) => SettingsToggleRow(
                          icon: Icons.notifications_outlined,
                          label: 'Push Notifications',
                          iconColor: AppColors.dark500,
                          value: settings.preferences.pushNotifications,
                          onChanged: (v) => context
                              .read<SettingsCubit>()
                              .setPushNotifications(v),
                        ),
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
  const _SettingsAppBar();

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
