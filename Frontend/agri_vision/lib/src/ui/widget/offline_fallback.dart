import 'package:flutter/material.dart';

import 'package:agri_vision/src/core/theme/theme.dart';
import 'package:agri_vision/src/ui/view/game/drone_runner_page.dart';

/// Shown where a list failed to load (usually: the device is offline).
///
/// Starts as a friendly error message with a Retry button; tapping
/// "Play Drone Runner" swaps the minigame into the very same area — no
/// navigation, same screen — with Retry and a close button in its header.
class OfflineFallback extends StatefulWidget {
  const OfflineFallback({
    super.key,
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  /// Human-readable reason, e.g. "No connection to the server."
  final String message;

  final VoidCallback onRetry;

  /// True when embedded inside a scrollable: the game gets a fixed height
  /// instead of expanding to fill the parent.
  final bool compact;

  @override
  State<OfflineFallback> createState() => _OfflineFallbackState();
}

class _OfflineFallbackState extends State<OfflineFallback> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    return _playing ? _game() : _message();
  }

  // ── Error message + actions ────────────────────────────────────────────

  Widget _message() {
    final column = Column(
      mainAxisAlignment: widget.compact
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.dark100),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
        TextButton(
          onPressed: () => setState(() => _playing = true),
          child: Text(
            '🎮  Offline? Play Drone Runner',
            style: AppTextStyle.textSmSemibold.copyWith(
              color: AppColors.dark500,
            ),
          ),
        ),
      ],
    );

    return widget.compact
        ? Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: column,
          )
        : Center(child: column);
  }

  // ── Inline game ────────────────────────────────────────────────────────

  Widget _game() {
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          const Icon(
            Icons.sports_esports_outlined,
            size: 16,
            color: AppColors.dark300,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Drone Runner — tap to jump',
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.dark300,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Retry'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppColors.dark300,
            onPressed: () => setState(() => _playing = false),
          ),
        ],
      ),
    );

    if (widget.compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: AppSpacing.xs),
          const SizedBox(height: 340, child: DroneRunnerGame()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: const DroneRunnerGame(),
          ),
        ),
      ],
    );
  }
}
