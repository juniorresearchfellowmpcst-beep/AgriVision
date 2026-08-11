class StorageConstants {
  StorageConstants._();

  static const String bearerToken = 'BEARER_TOKEN';
  static const String userId = 'USER_ID';
  static const String autoSessionToken = 'AUTO_SESSION_TOKEN';
  static const String userData = 'USER_DATA';
  static const String userchatStatus = 'USER_CHAT_STATUS';
  static const String droneRunnerBestScore = 'DRONE_RUNNER_BEST_SCORE';

  /// Set once the mission map has shown its "how to draw a block" hint, so it
  /// is a first-run introduction rather than a permanent banner.
  static const String missionHintSeen = 'MISSION_EMPTY_HINT_SEEN';
}
