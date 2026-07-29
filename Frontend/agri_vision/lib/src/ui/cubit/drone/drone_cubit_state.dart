part of 'drone_cubit.dart';

enum DroneStatus { initial, loading, success, failure }

class DroneState extends Equatable {
  const DroneState({
    this.status = DroneStatus.initial,
    this.drone,
    this.errorMessage = '',
  });

  final DroneStatus status;

  /// Null means no drone is paired to this account — a normal state the UI
  /// answers with its connect flow, not an error and never a stand-in unit.
  final AssignedDroneEntity? drone;
  final String errorMessage;

  bool get hasDrone => drone != null;

  /// A paired drone that is also reporting: the only case where the gauges
  /// on Home / Profile / the mission strip mean anything.
  bool get isConnected => drone?.isConnected ?? false;

  /// The server answered and there is simply nothing paired yet.
  bool get isUnpaired => status == DroneStatus.success && drone == null;

  bool get isLoading => status == DroneStatus.loading;

  DroneState copyWith({
    DroneStatus? status,
    AssignedDroneEntity? drone,
    bool clearDrone = false,
    String? errorMessage,
  }) {
    return DroneState(
      status: status ?? this.status,
      drone: clearDrone ? null : (drone ?? this.drone),
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, drone, errorMessage];
}
