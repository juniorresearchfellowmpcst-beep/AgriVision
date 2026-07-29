part of 'profile_cubit.dart';

enum ProfileStatus { initial, loading, success, failure }

/// Identity, flight stats and the paired drone.
///
/// Notification toggles deliberately do *not* live here — they are server-
/// backed and shared with the Settings screen, so [SettingsCubit] owns them.
/// Keeping a second copy here was how the Profile and Settings screens could
/// disagree about the same switch.
class ProfileState extends Equatable {
  const ProfileState({
    this.status = ProfileStatus.initial,
    this.profile,
    this.drone,
    this.errorMessage = '',
  });

  final ProfileStatus status;
  final PilotProfileEntity? profile;
  final AssignedDroneEntity? drone;
  final String errorMessage;

  bool get isLoading => status == ProfileStatus.loading;

  ProfileState copyWith({
    ProfileStatus? status,
    PilotProfileEntity? profile,
    AssignedDroneEntity? drone,
    String? errorMessage,
  }) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      drone: drone ?? this.drone,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, profile, drone, errorMessage];
}
