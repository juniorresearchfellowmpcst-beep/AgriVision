import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/auth/auth_service.dart';
import 'package:agri_vision/src/data/profile/profile_service.dart';
import 'package:agri_vision/src/domain/entity/profile_entity.dart';

part 'profile_cubit_state.dart';

/// The signed-in pilot's profile: personal details, flight stats and the
/// assigned drone, all served by GET /api/users/me.
///
/// Falls back to the locally stored sign-in user when the backend can't be
/// reached, so the Profile screen always shows at least name + email.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({ProfileService? service, AuthService? authService})
    : _service = service ?? ProfileService(),
      _authService = authService ?? AuthService(),
      super(const ProfileState());

  final ProfileService _service;
  final AuthService _authService;

  Future<void> load({bool refresh = false}) async {
    if (state.status == ProfileStatus.loading) return;
    if (state.status == ProfileStatus.success && !refresh) return;

    emit(state.copyWith(status: ProfileStatus.loading, errorMessage: ''));
    try {
      final (profile, drone) = await _service.fetchMe();
      emit(
        state.copyWith(
          status: ProfileStatus.success,
          profile: profile,
          drone: drone,
        ),
      );
    } catch (e) {
      // Offline / expired-token fallback: show the stored sign-in identity.
      final stored = await _authService.getStoredUser();
      if (stored != null) {
        emit(
          state.copyWith(
            status: ProfileStatus.success,
            profile: PilotProfileEntity.fromJson(stored),
            errorMessage: '',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          status: ProfileStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Update editable fields on the backend and refresh the snapshot.
  Future<void> updateProfile({
    String? username,
    String? phone,
    String? location,
    String? organisation,
  }) async {
    final (profile, drone) = await _service.updateMe(
      username: username,
      phone: phone,
      location: location,
      organisation: organisation,
    );
    emit(
      state.copyWith(
        status: ProfileStatus.success,
        profile: profile,
        drone: drone,
      ),
    );
  }

  // Notification preferences are device-local for now.
  void setMissionUpdates(bool value) =>
      emit(state.copyWith(missionUpdates: value));
  void setAiAlerts(bool value) => emit(state.copyWith(aiAlerts: value));
  void setFieldReports(bool value) => emit(state.copyWith(fieldReports: value));
}
