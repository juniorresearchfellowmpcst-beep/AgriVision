import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/settings/settings_service.dart';
import 'package:agri_vision/src/domain/entity/settings_entity.dart';

part 'settings_cubit_state.dart';

/// App preferences and the sync summary, shared by the Settings and Profile
/// screens.
///
/// Toggles are applied optimistically: the switch moves the instant it is
/// tapped and rolls back if the server rejects the write. A toggle that waits
/// for a round trip on field Wi-Fi feels broken, but one that silently lies
/// about being saved is worse — hence the rollback plus an error message.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({SettingsService? service})
    : _service = service ?? SettingsService(),
      super(const SettingsState());

  final SettingsService _service;

  Future<void> load({bool refresh = false}) async {
    if (state.status == SettingsStatus.loading) return;
    if (state.status == SettingsStatus.success && !refresh) return;

    emit(state.copyWith(status: SettingsStatus.loading, errorMessage: ''));
    try {
      final preferences = await _service.fetchPreferences();
      emit(
        state.copyWith(
          status: SettingsStatus.success,
          preferences: preferences,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: SettingsStatus.failure, errorMessage: _clean(e)),
      );
    }
    // The sync summary is secondary — a failure there must not blank out the
    // preferences that already loaded.
    await loadSyncStatus();
  }

  Future<void> loadSyncStatus() async {
    try {
      final items = await _service.fetchSyncStatus();
      emit(state.copyWith(syncItems: items, syncLoaded: true));
    } catch (_) {
      emit(state.copyWith(syncLoaded: true));
    }
  }

  /// Flip one preference by its wire key (see [UserPreferencesEntity]).
  Future<void> setPreference(String key, bool value) async {
    final previous = state.preferences;
    emit(
      state.copyWith(
        preferences: previous.withValue(key, value),
        errorMessage: '',
      ),
    );

    try {
      final saved = await _service.updatePreferences({key: value});
      // Clear the previous error too: leaving it set would stop an identical
      // failure later from re-firing the screen's error listener.
      emit(state.copyWith(preferences: saved, errorMessage: ''));
    } catch (e) {
      // Put the switch back where it was and say what went wrong.
      emit(state.copyWith(preferences: previous, errorMessage: _clean(e)));
    }
  }

  // Named helpers so screens read as intent, not string keys.
  Future<void> setMissionUpdates(bool v) =>
      setPreference(UserPreferencesEntity.keyMissionUpdates, v);

  Future<void> setAiAlerts(bool v) =>
      setPreference(UserPreferencesEntity.keyAiAlerts, v);

  Future<void> setFieldReports(bool v) =>
      setPreference(UserPreferencesEntity.keyFieldReports, v);

  Future<void> setAutoSync(bool v) =>
      setPreference(UserPreferencesEntity.keyAutoSync, v);

  Future<void> setPushNotifications(bool v) =>
      setPreference(UserPreferencesEntity.keyPushNotifications, v);

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}
