import 'package:flutter/material.dart';

/// Simple data class describing one tab in the bottom navigation bar.
/// Lives in `core` because it's shared infrastructure, not tied to
/// any single feature.
class NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}
