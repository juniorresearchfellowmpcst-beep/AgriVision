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
          icon: Icons.my_location_rounded,
          tooltip: 'GPS Locate',
          onTap: onGpsLocate,
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    Color bg;
    Color iconColor;
    if (disabled) {
      bg = const Color(0xFF1A3A28).withOpacity(0.55);
      iconColor = AppColors.dark100;
    } else if (isPrimary) {
      bg = AppColors.primary;
      iconColor = AppColors.light100;
    } else if (isDanger) {
      bg = AppColors.themeError.withOpacity(0.15);
      iconColor = AppColors.themeError;
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
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(
              color: isPrimary
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
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}
