import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/auth/auth_cubit.dart';
import 'package:agri_vision/src/ui/cubit/drone/drone_cubit.dart';

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

  // Signed-in user, loaded from local storage (dummy fallbacks).
  String _userName = 'Raj Patel';
  String _userEmail = 'raj.patel@agridrone.in';

  @override
  void initState() {
    super.initState();
    _loadStoredUser();
    context.read<DroneCubit>().load();
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
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  /// Pair the account with a drone by serial number (requires sign-in).
  Future<void> _showPairDialog(BuildContext context) async {
    final controller = TextEditingController();
    final serial = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Pair New Drone', style: AppTextStyle.textLgBold),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Serial number',
            hintText: 'e.g. ADU-2024-04-7832',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (serial == null || serial.isEmpty || !mounted) return;

    await context.read<DroneCubit>().pair(serial);
    if (!mounted) return;
    final state = context.read<DroneCubit>().state;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.status == DroneStatus.failure
              ? 'Pairing failed: ${state.errorMessage}'
              : 'Paired with ${state.drone?.unitName ?? 'drone'}',
        ),
      ),
    );
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
                        trailing: BlocBuilder<DroneCubit, DroneState>(
                          builder: (context, state) {
                            final drone = state.drone;
                            final connected = drone?.isConnected ?? false;
                            final label = drone == null
                                ? '—'
                                : drone.unitName
                                      .trim()
                                      .split(RegExp(r'\s+'))
                                      .last;
                            final color = connected
                                ? AppColors.primary
                                : AppColors.themeError;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  label,
                                  style: AppTextStyle.textSmSemibold.copyWith(
                                    color: color,
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
                      BlocBuilder<DroneCubit, DroneState>(
                        builder: (context, state) {
                          final drone = state.drone;
                          return DronePairingCard(
                            unitName: drone?.unitName ?? 'No drone paired',
                            serialNumber: drone?.serialNumber ?? '—',
                            isOnline: drone?.isConnected ?? false,
                            onPairNew: () => _showPairDialog(context),
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
