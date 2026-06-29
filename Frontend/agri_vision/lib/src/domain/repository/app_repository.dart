import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/env_settings.dart';

abstract class AppRepository {
  /*
   * Env Settings 
   */
  Future<(AppException?, EnvSettings?)> getEnvSettings();
}
