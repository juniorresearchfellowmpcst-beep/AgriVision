import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  // TODO: drive from ReportsCubit state
  String _selectedBlock = 'Block A – North Section';
  int _notesPage = 1;

  static const _blocks = [
    'Block A – North Section',
    'Block B – Row 3',
    'Orchard Row 8',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,

      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── FIXED: Dark-green mission header ─────────────────────
            _MissionHeader(
              selectedBlock: _selectedBlock,
              blocks: _blocks,
              onBlockChanged: (b) =>
                  setState(() => _selectedBlock = b ?? _selectedBlock),
            ),

            // ── SCROLLABLE: All report content ────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
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
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed(AppRouterNames.analysis),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── 2×2 stat grid ─────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: ReportStatCard(
                          label: 'Area Covered',
                          value: '4.2 ha',
                          valueColor: AppColors.primary,
                          subLabel: '100% complete',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: ReportStatCard(
                          label: 'Flight Time',
                          value: '18 min',
                          valueColor: AppColors.dark900,
                          subLabel: '2 passes',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: ReportStatCard(
                          label: 'Pesticide Used',
                          value: '2.1 L',
                          valueColor: const Color(0xFF2E86DE),
                          subLabel: 'Saved 1.4 L vs est.',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: ReportStatCard(
                          label: 'Detections',
                          value: '7',
                          valueColor: AppColors.themeWarning,
                          subLabel: '2 high severity',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Coverage map ──────────────────────────────────
                  const CoverageMapCard(coveragePercent: 100),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Detection by zone chart ───────────────────────
                  const DetectionByZoneCard(
                    zones: ['Block A', 'Block B', 'Block C', 'Orchard'],
                    values: [75, 85, 55, 90],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Precision spray savings ───────────────────────
                  const PrecisionSavingsCard(
                    usedLitres: 2.1,
                    savedLitres: 1.4,
                    totalLitres: 3.5,
                    savedPercent: 40,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Field notes + pagination ──────────────────────
                  FieldNotesCard(
                    notes:
                        'Wind conditions were calm throughout. Slight delay in Row 14 due to detection override.',
                    currentPage: _notesPage,
                    totalPages: 3,
                    onEdit: () {
                      // TODO: open notes editor
                    },
                    onPrevious: () =>
                        setState(() => _notesPage = _notesPage - 1),
                    onNext: () => setState(() => _notesPage = _notesPage + 1),
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
                      // TODO: trigger export
                    },
                  ),
                  SizedBox(height: 50),
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

class _MissionHeader extends StatelessWidget {
  const _MissionHeader({
    required this.selectedBlock,
    required this.blocks,
    required this.onBlockChanged,
  });

  final String selectedBlock;
  final List<String> blocks;
  final ValueChanged<String?> onBlockChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1F4D38),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
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
                      'Block A – Morning Run',
                      style: AppTextStyle.textXlBold.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Jun 23, 2026 · Raj Patel',
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.light100.withOpacity(0.70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const ReportStatusBadge(status: ReportStatus.complete),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // block selector
          BlockSelectorDropdown(
            selectedBlock: selectedBlock,
            blocks: blocks,
            onChanged: onBlockChanged,
          ),
        ],
      ),
    );
  }
}
