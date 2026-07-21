part of 'profile_cubit.dart';

enum ProfileStatus { initial, loading, success, failure }

class ProfileState extends Equatable {
  const ProfileState({
    this.status = ProfileStatus.initial,
    this.profile,
    this.drone,
    this.missionUpdates = true,
    this.aiAlerts = true,
    this.fieldReports = false,
    this.errorMessage = '',
  });

  final ProfileStatus status;
  final PilotProfileEntity? profile;
  final AssignedDroneEntity? drone;
  final bool missionUpdates;
  final bool aiAlerts;
  final bool fieldReports;
  final String errorMessage;

  bool get isLoading => status == ProfileStatus.loading;

  ProfileState copyWith({
    ProfileStatus? status,
    PilotProfileEntity? profile,
    AssignedDroneEntity? drone,
    bool? missionUpdates,
    bool? aiAlerts,
    bool? fieldReports,
    String? errorMessage,
  }) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      drone: drone ?? this.drone,
      missionUpdates: missionUpdates ?? this.missionUpdates,
      aiAlerts: aiAlerts ?? this.aiAlerts,
      fieldReports: fieldReports ?? this.fieldReports,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    profile,
    drone,
    missionUpdates,
    aiAlerts,
    fieldReports,
    errorMessage,
  ];
}
