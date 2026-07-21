import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/reports/reports_cubit.dart';

/// Field Reports screen, driven by [ReportsCubit].
///
/// Every "Analyze Field Images" run is persisted by the backend; this page
/// lists that history: pick a report in the header dropdown and see its
/// health score, primary index, risk-zone split and alert count.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  @override
  void initState() {
    super.initState();
    context.read<ReportsCubit>().load();
  }

  /// Unique dropdown label per report (titles/dates can repeat).
  List<String> _labels(List<FieldReportEntity> reports) {
    final labels = <String>[];
    for (final r in reports) {
      var label = r.date.isNotEmpty ? '${r.title} · ${r.date}' : r.title;
      while (labels.contains(label)) {
        label = '$label ·';
      }
      labels.add(label);
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<ReportsCubit, ReportsState>(
          builder: (context, state) {
            final labels = _labels(state.reports);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── FIXED: Dark-green report header ──────────────────────
                _ReportHeader(
                  report: state.selected,
                  labels: labels,
                  selectedIndex: state.selectedIndex,
                  onChanged: (label) {
                    final index = labels.indexOf(label ?? '');
                    if (index >= 0) context.read<ReportsCubit>().select(index);
                  },
                ),

                // ── SCROLLABLE: Report content ────────────────────────────
                Expanded(child: _ReportBody(state: state)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.state});

  final ReportsState state;

  @override
  Widget build(BuildContext context) {
    final report = state.selected;

    return RefreshIndicator(
      onRefresh: () => context.read<ReportsCubit>().load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl + 50,
        ),
        children: [
          // ── Analyze field images (multispectral) ──────────
          AppIconButton(
            label: 'Analyze Field Images',
            subtitle: 'Upload multispectral photos → risk zones & plan',
            startIcon: Icons.insights_outlined,
            endIcon: Icons.chevron_right,
            color: AppColors.primary,
            pressedColor: AppColors.primary6,
            showBorder: false,
            iconColor: AppColors.light100,
            pressedIconColor: AppColors.light100,
            textColor: AppColors.light100,
            pressedTextColor: AppColors.light100,
            textStyle: AppTextStyle.textMdSemibold,
            subtitleColor: AppColors.light100,
            width: double.infinity,
            borderRadius: AppRadius.lg,
            onPressed: () async {
              await Navigator.of(context).pushNamed(AppRouterNames.analysis);
              // A new run may have been recorded while we were away.
              if (context.mounted) {
                context.read<ReportsCubit>().load(refresh: true);
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          if (state.isLoading && state.reports.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.status == ReportsStatus.failure &&
              state.reports.isEmpty)
            // Offline: error + Retry, with the Drone Runner minigame playable
            // right here in the report list (compact = fixed height, since
            // this sits inside the scrollable).
            OfflineFallback(
              message: 'Could not load reports.\n${state.errorMessage}',
              onRetry: () => context.read<ReportsCubit>().load(refresh: true),
              compact: true,
            )
          else if (report == null)
            const _EmptyState(
              icon: Icons.analytics_outlined,
              text:
                  'No field reports yet.\nRun "Analyze Field Images" to generate your first report.',
            )
          else ...[
            // ── 2×2 stat grid ─────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ReportStatCard(
                    label: 'Health Score',
                    value: '${report.healthScore.round()} / 100',
                    valueColor: AppColors.primary,
                    subLabel: report.healthLabel.isNotEmpty
                        ? report.healthLabel
                        : '—',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ReportStatCard(
                    label: 'Primary Index',
                    value: report.primaryIndex.isNotEmpty
                        ? report.primaryIndex
                        : '—',
                    valueColor: AppColors.dark900,
                    subLabel: report.calibrated
                        ? 'Calibrated reflectance'
                        : 'Uncalibrated (relative)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: ReportStatCard(
                    label: 'High-Risk Area',
                    value: '${(report.riskHigh * 100).round()}%',
                    valueColor: AppColors.themeError,
                    subLabel: 'of analysed field',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ReportStatCard(
                    label: 'Detections',
                    value: '${report.alertCount}',
                    valueColor: AppColors.themeWarning,
                    subLabel: report.alertCount == 1
                        ? '1 stress flag raised'
                        : '${report.alertCount} stress flags raised',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Risk split chart ──────────────────────────────
            DetectionByZoneCard(
              zones: const ['Low Risk', 'Medium', 'High Risk'],
              values: [
                report.riskLow * 100,
                report.riskMedium * 100,
                report.riskHigh * 100,
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Export button ─────────────────────────────────
            AppIconButton(
              label: 'Export PDF / CSV',
              startIcon: Icons.download_outlined,
              color: AppColors.light100,
              pressedColor: AppColors.light300,
              borderColor: AppColors.light700,
              pressedBorderColor: AppColors.primary,
              iconColor: AppColors.dark700,
              pressedIconColor: AppColors.primary,
              textColor: AppColors.dark700,
              pressedTextColor: AppColors.primary,
              textStyle: AppTextStyle.textMdSemibold,
              width: double.infinity,
              height: 52,
              borderRadius: AppRadius.lg,
              mainAxisAlignment: MainAxisAlignment.center,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Export is coming soon.')),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
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

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.report,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final FieldReportEntity? report;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<String?> onChanged;

  ReportStatus get _status {
    final r = report;
    if (r == null) return ReportStatus.scheduled;
    return r.healthLabel.isNotEmpty
        ? ReportStatus.complete
        : ReportStatus.inProgress;
  }

  @override
  Widget build(BuildContext context) {
    final title = report?.title ?? 'Field Reports';
    final subtitle = report != null
        ? '${report!.date}${report!.primaryIndex.isNotEmpty ? ' · ${report!.primaryIndex}' : ''}'
        : 'Multispectral analysis history';

    return Container(
      color: const Color(0xFF1F4D38),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyle.textXlBold.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.light100.withOpacity(0.70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              ReportStatusBadge(status: _status),
            ],
          ),

          // report selector (only when there is history to pick from)
          if (labels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            BlockSelectorDropdown(
              selectedBlock:
                  labels[selectedIndex.clamp(0, labels.length - 1)],
              blocks: labels,
              onChanged: onChanged,
            ),
          ],
        ],
      ),
    );
  }
}
