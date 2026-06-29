import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '_storage.dart';

class SecureLocalStorage implements Storage {
  const SecureLocalStorage({required FlutterSecureStorage secureStorage})
    : _secureStorage = secureStorage;

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<bool?> readBool({required String key}) async {
    try {
      final value = await _secureStorage.read(key: key);
      return value != null ? value.toLowerCase() == 'true' : null;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<void> write({required String key, required String value}) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<void> writeBool({required String key, required bool value}) async {
    try {
      await _secureStorage.write(key: key, value: value.toString());
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<void> delete({required String key}) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _secureStorage.deleteAll();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }
}
