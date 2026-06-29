import 'package:agri_vision/src/ui/view/Home/Alerts_page/alerts_page.dart';
import 'package:agri_vision/src/ui/view/Home/Maps/mape_page.dart' show MapsPage;
import 'package:agri_vision/src/ui/view/Home/Reports/reports.dart';
import 'package:agri_vision/src/ui/view/Home/app_bottom_nav_bar.dart';
import 'package:agri_vision/src/ui/view/Home/home.dart';
import 'package:agri_vision/src/ui/view/Settings/settings.dart';
import 'package:flutter/material.dart';

/// Top-level shell that owns the currently-selected tab and renders the
/// matching feature page. Each feature page is fully self-contained
/// (its own widgets/bloc/cubit/provider can live entirely inside its
/// own `features/<name>/presentation` folder), so this page only
/// orchestrates *which* one is visible.
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;

  // IndexedStack keeps every tab's widget tree alive in memory, so
  // switching tabs doesn't rebuild map state, scroll position, etc.
  final List<Widget> _pages = const [
    HomePage(),
    MapsPage(),
    AlertsPage(),
    ReportsPage(),
    SettingsPage(),
  ];

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}
