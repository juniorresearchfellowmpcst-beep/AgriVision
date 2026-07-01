import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/ui/view/Home/home_page.dart';
import 'package:agri_vision/src/ui/view/Settings/settings_page.dart';
import 'package:agri_vision/src/ui/view/Maps/mape_page.dart';
import 'package:agri_vision/src/ui/view/Alerts_page/alerts_page.dart';
import 'package:agri_vision/src/ui/view/Reports/reports_page.dart';
import 'package:agri_vision/src/ui/view/bottom_nav_bar.dart';

enum Menu { home, maps, alerts, reports, settings }

class BottomNavBarState {
  const BottomNavBarState({this.selectedMenu = Menu.home});

  final Menu selectedMenu;
}

class BottomNavBarCubit extends Cubit<BottomNavBarState> {
  BottomNavBarCubit() : super(const BottomNavBarState());

  void selectMenu(Menu menu) => emit(BottomNavBarState(selectedMenu: menu));
}

class NavigationHandler extends StatelessWidget {
  const NavigationHandler({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BottomNavBarCubit, BottomNavBarState>(
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
