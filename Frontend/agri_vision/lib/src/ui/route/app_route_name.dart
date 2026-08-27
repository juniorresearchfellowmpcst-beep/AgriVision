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

  /// Watch the drone's camera live, and scan the feed while it flies.
  /// Optional `arguments`: the camera id to open (int).
  static const String liveFeed = '/live_feed_page';

  /// K-means spray prescription. Optional `arguments`: the shot id to
  /// prescribe from.
  static const String spray = '/spray_page';

  /// Weed + disease scan. Optional `arguments`: the capture session to scan.
  static const String fieldScan = '/field_scan_page';

  /// The survey flight: camera selection -> live CNN scan -> crop-health
  /// report and action plan -> K-means treatment map -> an authorised spray.
  /// Optional `arguments`: a finished run id (int) to re-open.
  static const String survey = '/survey_page';

  /// The crop picker, for scanning with the phone instead of the drone.
  static const String cropScan = '/crop_scan_page';

  static const String droneRunner = '/drone_runner_game';
}
