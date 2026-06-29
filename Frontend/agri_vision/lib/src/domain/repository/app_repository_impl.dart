import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/env_settings.dart';
import 'package:agri_vision/src/domain/repository/app_repository.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppRepositoryImpl implements AppRepository {
  final dynamic remoteDataSource;
  final dynamic localDataSource;
  final dynamic networkInfo;

  AppRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.networkInfo,
  });

  Future<T> fetchWithCache<T>({
    required Future<T> Function() remoteFetch,
    required Future<T> Function() localFetch,
    required Future<void> Function(T) cacheData,
  }) async {
    if (await _isConnected()) {
      final result = await remoteFetch();
      await cacheData(result);
      return result;
    }

    return await localFetch();
  }

  Future<bool> _isConnected() async {
    if (networkInfo == null) return false;

    if (networkInfo is bool) {
      return networkInfo as bool;
    }

    if (networkInfo is Future<bool>) {
      return await networkInfo as bool;
    }

    if (networkInfo is Function) {
      final value = networkInfo();
      if (value is Future<bool>) return await value;
      if (value is bool) return value;
    }

    try {
      final connectionStatus = await networkInfo.isConnected;
      if (connectionStatus is bool) return connectionStatus;
    } catch (_) {
      return false;
    }

    return false;
  }

  Future<(AppException?, EnvSettings?)> getEnvSettings() async {
    try {
      final envSettings = EnvSettings(
        appUrl: dotenv.get('APP_URL', fallback: ''),
        broadcastPort: dotenv.get('BROADCAST_PORT', fallback: ''),
        ticketIntegrationUrl: dotenv.get(
          'TICKET_INTEGRATION_URL',
          fallback: '',
        ),
        surboBaseUrl: dotenv.get('SURBO_BASE_URL', fallback: ''),
        surboSocketUrl: dotenv.get('SURBO_SOCKET_URL', fallback: ''),
      );

      return (null, envSettings);
    } catch (error) {
      return (
        UnexpectedException(
          code: '',
          message: 'Failed to load environment settings',
          data: error.toString(),
        ),
        null,
      );
    }
  }

  Future<T> loadAppData<T>() async {
    return fetchWithCache<T>(
      remoteFetch: () => remoteDataSource.loadAppData(),
      localFetch: () => localDataSource.getLastAppData(),
      cacheData: (data) => localDataSource.saveAppData(data),
    );
  }
}
