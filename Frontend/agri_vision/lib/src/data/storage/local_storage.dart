import 'package:shared_preferences/shared_preferences.dart';
import '_storage.dart';

class LocalStorage implements Storage {
  const LocalStorage({required SharedPreferences sharedPreferences})
    : _sharedPreferences = sharedPreferences;

  final SharedPreferences _sharedPreferences;

  @override
  Future<String?> read({required String key}) async {
    try {
      return _sharedPreferences.getString(key);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<bool?> readBool({required String key}) async {
    try {
      return _sharedPreferences.getBool(key);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<void> write({required String key, required String value}) async {
    try {
      await _sharedPreferences.setString(key, value);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<void> writeBool({required String key, required bool value}) async {
    try {
      await _sharedPreferences.setBool(key, value);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<void> delete({required String key}) async {
    try {
      await _sharedPreferences.remove(key);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _sharedPreferences.clear();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(Exception(error), stackTrace);
    }
  }
}
