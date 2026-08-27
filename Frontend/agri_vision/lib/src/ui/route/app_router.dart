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

      case AppRouterNames.disease:
        return _buildMaterialPageRoute(
          const DiseasePage(),
          name: AppRouterNames.disease,
        );

      case AppRouterNames.capture:
        return _buildMaterialPageRoute(
          const LiveCapturePage(),
          name: AppRouterNames.capture,
        );

      // Reached cold (from Home) or warm (from the capture screen, naming
      // the camera to open), so the argument is read defensively.
      case AppRouterNames.liveFeed:
        return _buildMaterialPageRoute(
          LiveFeedPage(cameraId: settings.arguments as int?),
          name: AppRouterNames.liveFeed,
        );

      // Both of these can be reached cold (from Home) or warm (from the
      // capture screen, carrying the shot / session to work on), so the
      // argument is read defensively rather than cast.
      case AppRouterNames.spray:
        return _buildMaterialPageRoute(
          SprayPrescriptionPage(shotId: settings.arguments as String?),
          name: AppRouterNames.spray,
        );

      case AppRouterNames.fieldScan:
        return _buildMaterialPageRoute(
          FieldScanPage(sessionId: settings.arguments as String?),
          name: AppRouterNames.fieldScan,
        );

      // Reached cold (from Home) or warm (from history, naming a finished
      // run to re-open), so the argument is read defensively rather than cast.
      case AppRouterNames.survey:
        return _buildMaterialPageRoute(
          SurveyPage(runId: settings.arguments as int?),
          name: AppRouterNames.survey,
        );

      case AppRouterNames.cropScan:
        return _buildMaterialPageRoute(
          const CropScanPage(),
          name: AppRouterNames.cropScan,
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
