part of 'missions_cubit.dart';

enum MissionsStatus { initial, loading, success, failure }

class MissionsState extends Equatable {
  const MissionsState({
    this.status = MissionsStatus.initial,
    this.missions = const [],
    this.errorMessage = '',
  });

  final MissionsStatus status;
  final List<MissionReportEntity> missions;
  final String errorMessage;

  bool get isLoading => status == MissionsStatus.loading;

  MissionsState copyWith({
    MissionsStatus? status,
    List<MissionReportEntity>? missions,
    String? errorMessage,
  }) {
    return MissionsState(
      status: status ?? this.status,
      missions: missions ?? this.missions,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, missions, errorMessage];
}
