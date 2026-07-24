import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/cubit/disease/disease_cubit.dart';

/// Plant-disease scanner screen.
///
/// Lets the user **take a photo** of a plant leaf or **upload** one from the
/// gallery, uploads it to the backend, and renders the identified condition:
/// its severity, symptoms, likely causes, a grouped treatment **solution**, and
/// prevention tips.
///
/// State is owned by [DiseaseCubit]; this page is a pure function of that state,
/// matching the app's BLoC/Cubit architecture (same shape as [AnalysisPage]).
class DiseasePage extends StatelessWidget {
  const DiseasePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DiseaseCubit(),
      child: const _DiseaseView(),
    );
  }
}

class _DiseaseView extends StatelessWidget {
  const _DiseaseView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.tertiary,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        foregroundColor: AppColors.light100,
        elevation: 0,
        title: Text(
          'Plant Disease Scan',
          style: AppTextStyle.textLgSemibold.copyWith(color: AppColors.light100),
        ),
        actions: [
          BlocBuilder<DiseaseCubit, DiseaseState>(
            buildWhen: (a, b) => a.hasResult != b.hasResult,
            builder: (context, state) {
              if (!state.hasResult) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'New scan',
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<DiseaseCubit>().reset(),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: BlocBuilder<DiseaseCubit, DiseaseState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const _IntroCard(),
                const SizedBox(height: AppSpacing.lg),
                const _CaptureCard(),
                if (state.hasImage) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _PhotoPreview(bytes: state.image!.bytes),
                ],
                if (state.errorMessage.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ErrorBanner(message: state.errorMessage),
                ],
                if (state.isBusy) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  const _BusyIndicator(),
                ],
                if (state.hasResult) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ResultSection(result: state.result!),
                ],
                const SizedBox(height: 60),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Intro ────────────────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_florist_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text('Identify a plant disease', style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Take a clear photo of a single affected leaf — or upload one from '
            'your gallery. We analyse the leaf and tell you the likely problem '
            'along with how to treat and prevent it.',
            style: AppTextStyle.textSmRegular.copyWith(color: AppColors.dark300),
          ),
        ],
      ),
    );
  }
}

// ── Capture / upload controls ────────────────────────────────────────────────

class _CaptureCard extends StatelessWidget {
  const _CaptureCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiseaseCubit, DiseaseState>(
      builder: (context, state) {
        final cubit = context.read<DiseaseCubit>();
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppIconButton(
                      label: 'Take Photo',
                      startIcon: Icons.photo_camera_outlined,
                      height: 52,
                      mainAxisAlignment: MainAxisAlignment.center,
                      color: AppColors.primary,
                      pressedColor: AppColors.primary6,
                      disabledColor: AppColors.light700,
                      showBorder: false,
                      iconColor: AppColors.light100,
                      pressedIconColor: AppColors.light100,
                      textColor: AppColors.light100,
                      pressedTextColor: AppColors.light100,
                      textStyle: AppTextStyle.textMdSemibold,
                      onPressed: state.isBusy ? null : cubit.captureAndIdentify,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: AppIconButton(
                      label: 'Upload',
                      startIcon: Icons.image_outlined,
                      height: 52,
                      mainAxisAlignment: MainAxisAlignment.center,
                      textStyle: AppTextStyle.textMdSemibold,
                      onPressed: state.isBusy ? null : cubit.pickAndIdentify,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Tip: fill the frame with one leaf on a plain background, in good '
                'light, for the most reliable result.',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Image.memory(
        bytes,
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

// ── Busy / error ─────────────────────────────────────────────────────────────

class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Analysing the leaf…',
          textAlign: TextAlign.center,
          style: AppTextStyle.textSmRegular.copyWith(color: AppColors.dark300),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.themeError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.themeError.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.themeError, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result ───────────────────────────────────────────────────────────────────

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.result});

  final DiseaseResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DiagnosisCard(result: result),
        if (result.symptoms.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _BulletCard(
            title: 'Symptoms',
            icon: Icons.visibility_outlined,
            items: result.symptoms,
          ),
        ],
        if (result.causes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _BulletCard(
            title: 'Likely causes',
            icon: Icons.help_outline,
            items: result.causes,
          ),
        ],
        if (result.solutions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _SolutionsCard(solutions: result.solutions),
        ],
        if (result.prevention.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _BulletCard(
            title: 'Prevention',
            icon: Icons.shield_outlined,
            items: result.prevention,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _DisclaimerNote(text: result.disclaimer),
      ],
    );
  }
}

class _DiagnosisCard extends StatelessWidget {
  const _DiagnosisCard({required this.result});

  final DiseaseResult result;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(result.severityLevel, result.isHealthy);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  result.isHealthy
                      ? Icons.check_circle_outline
                      : Icons.coronavirus_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.isHealthy ? 'Diagnosis' : 'Likely condition',
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.dark300,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(result.name, style: AppTextStyle.textXlBold.copyWith(color: color)),
                    if (result.alsoKnownAs.isNotEmpty)
                      Text(
                        result.alsoKnownAs,
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: AppColors.dark300,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (!result.isHealthy)
                _Chip(
                  label: '${_severityLabel(result.severityLevel)} severity',
                  color: color,
                ),
              _Chip(
                label: '${result.confidencePercent}% confidence',
                color: AppColors.primary,
              ),
              if (!result.isHealthy && result.affectedPercent > 0)
                _Chip(
                  label: '≈${result.affectedPercent}% leaf affected',
                  color: AppColors.dark300,
                ),
            ],
          ),
          if (result.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              result.description,
              style: AppTextStyle.textSmRegular.copyWith(color: AppColors.dark700),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            result.source == 'model'
                ? 'Identified by the trained model.'
                : 'Estimated from a visual leaf analysis.',
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppTextStyle.textXsSemibold.copyWith(color: color),
      ),
    );
  }
}

/// A titled card that renders a list of strings as bullet points.
class _BulletCard extends StatelessWidget {
  const _BulletCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.dark700,
                      ),
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

class _SolutionsCard extends StatelessWidget {
  const _SolutionsCard({required this.solutions});

  final List<Solution> solutions;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.healing_outlined, color: AppColors.primary, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text('Solution & treatment', style: AppTextStyle.textMdSemibold),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final s in solutions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _SolutionRow(solution: s),
            ),
        ],
      ),
    );
  }
}

class _SolutionRow extends StatelessWidget {
  const _SolutionRow({required this.solution});

  final Solution solution;

  @override
  Widget build(BuildContext context) {
    final style = _solutionStyle(solution.type);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: style.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(style.icon, size: 18, color: style.color),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      solution.title,
                      style: AppTextStyle.textSmSemibold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: style.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      style.label,
                      style: AppTextStyle.textXsSemibold.copyWith(color: style.color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                solution.detail,
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.dark300,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DisclaimerNote extends StatelessWidget {
  const _DisclaimerNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.themeWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.themeWarning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark500),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared card shell + helpers ──────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: child,
    );
  }
}

Color _severityColor(String level, bool isHealthy) {
  if (isHealthy) return AppColors.themeSuccess;
  switch (level) {
    case 'high':
      return AppColors.themeError;
    case 'moderate':
      return AppColors.themeWarning;
    case 'low':
      return AppColors.primary;
    default:
      return AppColors.dark300;
  }
}

String _severityLabel(String level) {
  switch (level) {
    case 'high':
      return 'High';
    case 'moderate':
      return 'Moderate';
    case 'low':
      return 'Low';
    default:
      return 'Unknown';
  }
}

class _SolutionStyle {
  const _SolutionStyle(this.icon, this.color, this.label);
  final IconData icon;
  final Color color;
  final String label;
}

_SolutionStyle _solutionStyle(String type) {
  switch (type) {
    case 'organic':
      return _SolutionStyle(Icons.eco_outlined, AppColors.themeSuccess, 'Organic');
    case 'chemical':
      return _SolutionStyle(Icons.science_outlined, AppColors.themeWarning, 'Chemical');
    case 'monitoring':
      return _SolutionStyle(Icons.search_outlined, AppColors.secondary, 'Monitor');
    case 'cultural':
    default:
      return _SolutionStyle(Icons.agriculture_outlined, AppColors.primary, 'Cultural');
  }
}
