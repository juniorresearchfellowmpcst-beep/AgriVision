import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Cluster of floating action buttons on the right side of the map.
/// Each FAB is a small dark circle with a tooltip.
///
/// The cluster has two states driven by [editMode]:
///  - view: edit toggle + GPS + center only
///  - edit: full toolset (add / undo / redo / delete / import KML)
class MissionFabCluster extends StatelessWidget {
  const MissionFabCluster({
    super.key,
    required this.editMode,
    required this.onToggleEdit,
    required this.onAddWaypoint,
    required this.onUndo,
    required this.onRedo,
    required this.onDelete,
    required this.onCenter,
    required this.onGpsLocate,
    required this.onImport,
    required this.canUndo,
    required this.canRedo,
    required this.canDelete,
    this.gpsBusy = false,
    this.gpsActive = false,
  });

  final bool editMode;
  final VoidCallback onToggleEdit;
  final VoidCallback onAddWaypoint;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onDelete;
  final VoidCallback onCenter;
  final VoidCallback onGpsLocate;
  final VoidCallback onImport;
  final bool canUndo;
  final bool canRedo;
  final bool canDelete;

  /// A fix is being taken right now — the button spins instead of inviting a
  /// second press that would queue another read.
  final bool gpsBusy;

  /// A location pin is already on the map, so the button reads as "on".
  final bool gpsActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Fab(
          icon: editMode ? Icons.check_rounded : Icons.edit_outlined,
          tooltip: editMode ? 'Done Editing' : 'Edit Mission',
          onTap: onToggleEdit,
          isPrimary: true,
        ),
        if (editMode) ...[
          const SizedBox(height: AppSpacing.sm),
          _Fab(
            icon: Icons.add_location_alt_outlined,
            tooltip: 'Add Waypoint',
            onTap: onAddWaypoint,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Fab(
            icon: Icons.undo_rounded,
            tooltip: 'Undo',
            onTap: canUndo ? onUndo : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          _Fab(
            icon: Icons.redo_rounded,
            tooltip: 'Redo',
            onTap: canRedo ? onRedo : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Fab(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete Selected',
            onTap: canDelete ? onDelete : null,
            isDanger: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Fab(
            icon: Icons.file_upload_outlined,
            tooltip: 'Import KML',
            onTap: onImport,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _Fab(
          icon: gpsActive
              ? Icons.my_location_rounded
              : Icons.location_searching_rounded,
          tooltip: gpsBusy ? 'Locating…' : 'Pin My Location',
          onTap: gpsBusy ? null : onGpsLocate,
          busy: gpsBusy,
          isActive: gpsActive,
        ),
        const SizedBox(height: AppSpacing.xs),
        _Fab(
          icon: Icons.center_focus_strong_outlined,
          tooltip: 'Center Map',
          onTap: onCenter,
        ),
      ],
    );
  }
}

class _Fab extends StatelessWidget {
  const _Fab({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isPrimary = false,
    this.isDanger = false,
    this.isActive = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isDanger;

  /// Toggle-style "this is currently on" highlight.
  final bool isActive;

  /// Replaces the glyph with a spinner while work is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !busy;

    Color bg;
    Color iconColor;
    if (busy) {
      bg = const Color(0xFF1A3A28).withOpacity(0.88);
      iconColor = AppColors.primary3;
    } else if (disabled) {
      bg = const Color(0xFF1A3A28).withOpacity(0.55);
      iconColor = AppColors.dark100;
    } else if (isPrimary) {
      bg = AppColors.primary;
      iconColor = AppColors.light100;
    } else if (isDanger) {
      bg = AppColors.themeError.withOpacity(0.15);
      iconColor = AppColors.themeError;
    } else if (isActive) {
      bg = AppColors.primary.withOpacity(0.9);
      iconColor = AppColors.light100;
    } else {
      bg = const Color(0xFF1A3A28).withOpacity(0.88);
      iconColor = AppColors.light100;
    }

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(
              color: isPrimary || isActive
                  ? AppColors.primary
                  : isDanger
                  ? AppColors.themeError.withOpacity(0.4)
                  : AppColors.primary.withOpacity(0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(disabled ? 0.1 : 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                )
              : Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}
