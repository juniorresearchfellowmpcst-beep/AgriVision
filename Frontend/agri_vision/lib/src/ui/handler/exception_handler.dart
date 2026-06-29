import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/ui/route/app_router.dart';
import 'package:dio/dio.dart';

class ExceptionHandler {
  static void handle(Object error, {StackTrace? stackTrace}) {
    if (error is DioException) {
      _handleDioException(error, stackTrace);
    } else {
      _handleDefaultException(error, stackTrace);
    }
  }

  static void _handleDefaultException(Object error, StackTrace? stackTrace) {
    Logger.e('$error \n$stackTrace');
  }

  static void _handleDioException(DioException e, StackTrace? stackTrace) {
    switch (e.response?.statusCode) {
      case 401:
        Logger.e('Unauthorised: ${e.message}\n$stackTrace');
        final context = AppRouter.navigationKey.currentContext;
        if (context != null) {
          //need to create a custom dialog box
        }

        break;
      case 400:
        Logger.e('Bad Request: ${e.message}\n$stackTrace');
        break;
      case 422:
        Logger.e('Validation Failed: ${e.message}\n$stackTrace');
        break;
      case 500:
        Logger.e('Server Error: ${e.message}\n$stackTrace');
        break;
      default:
        Logger.e('Dio error: ${e.message}\n$stackTrace');
    }
  }
}
