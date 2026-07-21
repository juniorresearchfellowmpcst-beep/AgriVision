import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/alerts/alerts_cubit.dart';

/// AI Alerts screen.
///
/// Layout:
///   - Fixed custom app bar: "AI Alerts" title + [AlertActiveChip]
///     + context subtitle
///   - Scrollable list of [AlertListTile] cards (swipe to resolve)
///   - [AppBottomNavBar] with Alerts tab pre-selected
///
/// State is owned by [AlertsCubit]; alerts are raised server-side by each
/// multispectral analysis run.
class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  @override
  void initState() {
    super.initState();
    context.read<AlertsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<AlertsCubit, AlertsState>(
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── FIXED: App bar ────────────────────────────────────────
                _AlertsAppBar(
                  activeCount: state.activeCount,
                  subtitle: _subtitle(state),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── SCROLLABLE: Alert list ────────────────────────────────
                Expanded(child: _AlertsBody(state: state)),
              ],
            );
          },
        ),
      ),
    );
  }

  String _subtitle(AlertsState state) {
    if (state.alerts.isEmpty) {
      return 'Alerts appear after each field analysis';
    }
    final latest = state.alerts.first;
    final date = DateFormat('d MMM yyyy').format(DateTime.now());
    return '${latest.location} · $date · swipe to resolve';
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AlertsBody extends StatelessWidget {
  const _AlertsBody({required this.state});

  final AlertsState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.alerts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.status == AlertsStatus.failure && state.alerts.isEmpty) {
      // Offline: error + Retry, with the Drone Runner minigame playable
      // right here in the alerts area.
      return OfflineFallback(
        message: 'Could not load alerts.\n${state.errorMessage}',
        onRetry: () => context.read<AlertsCubit>().load(refresh: true),
      );
    }

    if (state.alerts.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.verified_outlined,
        text:
            'No active alerts.\nRun "Analyze Field Images" from Reports to scan your field.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<AlertsCubit>().load(refresh: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        itemCount: state.alerts.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm + 2),
        itemBuilder: (context, index) {
          final alert = state.alerts[index];
          return Dismissible(
            key: ValueKey('alert-${alert.id}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => context.read<AlertsCubit>().resolve(alert),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.themeSuccess,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white),
            ),
            child: AlertListTile(alert: alert, onTap: () {}),
          );
        },
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.text});

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AlertsAppBar extends StatelessWidget {
  const _AlertsAppBar({required this.activeCount, required this.subtitle});

  final int activeCount;
  final String subtitle;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('AI Alerts', style: AppTextStyle.displayH3),
              AlertActiveChip(count: activeCount),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // subtitle: context line
          Text(
            subtitle,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
        ],
      ),
    );
  }
}
