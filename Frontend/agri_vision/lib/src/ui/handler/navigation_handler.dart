import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/ui/view/Home/home_page.dart';
import 'package:agri_vision/src/ui/view/Settings/settings_page.dart';
import 'package:agri_vision/src/ui/view/Maps/mape_page.dart';
import 'package:agri_vision/src/ui/view/Alerts_page/alerts_page.dart';
import 'package:agri_vision/src/ui/view/Reports/reports_page.dart';
import 'package:agri_vision/src/ui/view/bottom_nav_bar.dart';

enum Menu { home, maps, alerts, reports, settings }

class SidebarState {
  const SidebarState({this.selectedMenu = Menu.home});

  final Menu selectedMenu;
}

class SidebarCubit extends Cubit<SidebarState> {
  SidebarCubit() : super(const SidebarState());

  void selectMenu(Menu menu) => emit(SidebarState(selectedMenu: menu));
}

class NavigationHandler extends StatelessWidget {
  const NavigationHandler({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SidebarCubit, SidebarState>(
      builder: (context, state) {
        final pages = <Widget>[
          const HomePage(),
          const MapsPage(),
          const AlertsPage(),
          const ReportsPage(),
          const SettingsPage(),
        ];

        final currentIndex = state.selectedMenu.index;

        return Scaffold(
          extendBody: true,
          body: IndexedStack(index: currentIndex, children: pages),
          bottomNavigationBar: const AppBottomNavBar(),
        );
      },
    );
  }
}
