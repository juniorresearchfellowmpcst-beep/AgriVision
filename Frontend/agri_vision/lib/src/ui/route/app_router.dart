import 'package:agri_vision/src/src.dart';
import 'package:agri_vision/src/ui/view/login/sign_in.dart';
import 'package:flutter/material.dart';

class AppRouter {
  static final navigationKey = GlobalKey<NavigatorState>();

  static final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRouterNames.signIn:
        return _buildMaterialPageRoute(
          const SignInPage(),
          name: AppRouterNames.signIn,
        );

      case AppRouterNames.signUp:
        return _buildMaterialPageRoute(
          const SignUpPage(),
          name: AppRouterNames.signUp,
        );
      case AppRouterNames.home:
        return _buildMaterialPageRoute(
          const HomePage(),
          name: AppRouterNames.home,
        );
      case AppRouterNames.settings:
        return _buildMaterialPageRoute(
          const SettingsPage(),
          name: AppRouterNames.settings,
        );
      case AppRouterNames.maps:
        return _buildMaterialPageRoute(
          const MapsPage(),
          name: AppRouterNames.maps,
        );
      case AppRouterNames.alerts:
        return _buildMaterialPageRoute(
          const AlertsPage(),
          name: AppRouterNames.alerts,
        );
      case AppRouterNames.reports:
        return _buildMaterialPageRoute(
          const ReportsPage(),
          name: AppRouterNames.reports,
        );

      default:
        return _buildMaterialPageRoute(const Scaffold());
    }
  }

  static Route<dynamic> _buildMaterialPageRoute(Widget widget, {String? name}) {
    return MaterialPageRoute(
      builder: (_) => widget,
      settings: RouteSettings(name: name),
    );
  }
}
