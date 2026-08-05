class AppRouterNames {
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String forgotPassword = '/forgot-password';

  static const String home = '/home';
  static const String settings = '/settings_page';
  static const String maps = '/maps_page';
  static const String alerts = '/alerts_page';
  static const String reports = '/reports_page';
  static const String profile = '/profile_page';
  static const String analysis = '/analysis_page';
  static const String disease = '/disease_page';

  /// Live capture from the drone's multispectral rig + RGB camera.
  static const String capture = '/capture_page';

  /// K-means spray prescription. Optional `arguments`: the shot id to
  /// prescribe from.
  static const String spray = '/spray_page';

  /// Weed + disease scan. Optional `arguments`: the capture session to scan.
  static const String fieldScan = '/field_scan_page';

  static const String droneRunner = '/drone_runner_game';
}
