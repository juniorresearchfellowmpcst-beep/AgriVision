part of 'drone_cubit.dart';

enum DroneStatus { initial, loading, success, failure }

class DroneState extends Equatable {
  const DroneState({
    this.status = DroneStatus.initial,
    this.drone,
    this.errorMessage = '',
  });

  final DroneStatus status;
  final AssignedDroneEntity? drone;
  final String errorMessage;

  bool get hasDrone => drone != null;

  DroneState copyWith({
    DroneStatus? status,
    AssignedDroneEntity? drone,
    String? errorMessage,
  }) {
    return DroneState(
      status: status ?? this.status,
      drone: drone ?? this.drone,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, drone, errorMessage];
}
