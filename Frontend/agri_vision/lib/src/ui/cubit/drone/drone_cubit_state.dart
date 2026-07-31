part of 'drone_cubit.dart';

enum DroneStatus { initial, loading, success, failure }

class DroneState extends Equatable {
  const DroneState({
    this.status = DroneStatus.initial,
    this.drone,
    this.errorMessage = '',
    this.lastMessage = '',
    this.registeredNewDrone = false,
  });

  final DroneStatus status;

  /// Null means no drone is paired to this account — a normal state the UI
  /// answers with its connect flow, not an error and never a stand-in unit.
  final AssignedDroneEntity? drone;
  final String errorMessage;

  /// The server's wording for the last successful pairing.
  final String lastMessage;

  /// True when the last pairing *created* the aircraft because the serial was
  /// unknown, rather than matching one already on file. Worth flagging — it is
  /// what a mistyped serial looks like.
  final bool registeredNewDrone;

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
    String? lastMessage,
    bool? registeredNewDrone,
  }) {
    return DroneState(
      status: status ?? this.status,
      drone: clearDrone ? null : (drone ?? this.drone),
      errorMessage: errorMessage ?? this.errorMessage,
      lastMessage: lastMessage ?? this.lastMessage,
      registeredNewDrone: registeredNewDrone ?? this.registeredNewDrone,
    );
  }

  @override
  List<Object?> get props => [
    status,
    drone,
    errorMessage,
    lastMessage,
    registeredNewDrone,
  ];
}
