import 'package:agri_vision/src/src.dart';
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

      case AppRouterNames.forgotPassword:
        return _buildMaterialPageRoute(
          const ForgotPasswordPage(),
          name: AppRouterNames.forgotPassword,
        );
      case AppRouterNames.home:
        return _buildMaterialPageRoute(
          const NavigationHandler(child: Scaffold()),
          name: AppRouterNames.home,
        );
      case AppRouterNames.settings:
      case AppRouterNames.maps:
      case AppRouterNames.alerts:
      case AppRouterNames.reports:
        // These routes are handled within the NavigationHandler via tab switching
        return _buildMaterialPageRoute(
          const NavigationHandler(child: Scaffold()),
          name: AppRouterNames.home,
        );

      case AppRouterNames.profile:
        return _buildMaterialPageRoute(
          const ProfilePage(),
          name: AppRouterNames.profile,
        );

      case AppRouterNames.analysis:
        return _buildMaterialPageRoute(
          const AnalysisPage(),
          name: AppRouterNames.analysis,
        );

      case AppRouterNames.droneRunner:
        return _buildMaterialPageRoute(
          const DroneRunnerPage(),
          name: AppRouterNames.droneRunner,
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
