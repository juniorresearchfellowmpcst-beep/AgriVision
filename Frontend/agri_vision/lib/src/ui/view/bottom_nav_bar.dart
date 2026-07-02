import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/src.dart';

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({super.key, this.alertCount = 0});

  final int alertCount;

  static const List<_NavEntry> _items = [
    _NavEntry(menu: Menu.home, label: 'Home', icon: Icons.home_outlined),

    _NavEntry(menu: Menu.maps, label: 'Map', icon: Icons.map_outlined),
    _NavEntry(
      menu: Menu.alerts,
      label: 'Alerts',
      icon: Icons.notifications_none_rounded,
    ),
    _NavEntry(
      menu: Menu.reports,
      label: 'Reports',
      icon: Icons.description_outlined,
    ),
    _NavEntry(
      menu: Menu.settings,
      label: 'Settings',
      icon: Icons.settings_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BottomNavBarCubit, BottomNavBarState>(
      buildWhen: (prev, curr) => prev.selectedMenu != curr.selectedMenu,
      builder: (context, state) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.light100,
            border: Border(
              top: BorderSide(color: AppColors.light700, width: 1),
            ),
          ),
          child: SafeArea(
            top: true,
            bottom: true,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (final item in _items)
                    Expanded(
                      child: _BottomNavItem(
                        entry: item,
                        isSelected: state.selectedMenu == item.menu,
                        badgeCount: item.menu == Menu.alerts ? alertCount : 0,
                        onTap: () => context
                            .read<BottomNavBarCubit>()
                            .selectMenu(item.menu),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavEntry {
  final Menu menu;
  final String label;
  final IconData icon;

  const _NavEntry({
    required this.menu,
    required this.label,
    required this.icon,
  });
}

class _BottomNavItem extends StatelessWidget {
  final _NavEntry entry;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.entry,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.primary : AppColors.dark300;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(entry.icon, size: 23, color: color),
              if (badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.themeError,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: AppTextStyle.textXsBold.copyWith(
                        color: AppColors.light100,
                        fontSize: 10,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            entry.label,
            style:
                (isSelected
                        ? AppTextStyle.textXsSemibold
                        : AppTextStyle.textXsRegular)
                    .copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
