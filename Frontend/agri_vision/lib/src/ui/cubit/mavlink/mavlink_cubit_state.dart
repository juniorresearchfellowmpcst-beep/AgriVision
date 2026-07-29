part of 'mavlink_cubit.dart';

/// Link phases the UI reacts to.
///
/// [unavailable] means the *backend* has no pymavlink installed — a setup
/// problem, not a flight problem, and worth saying so plainly instead of
/// showing "disconnected" forever. [stale] means the socket is open but
/// heartbeats stopped: the drone is out of range or the simulator was closed.
enum MavlinkPhase {
  initial,
  connecting,
  connected,
  stale,
  disconnected,
  unavailable,
  failure,
}

class MavlinkState extends Equatable {
  const MavlinkState({
    this.status = MavlinkPhase.initial,
    this.link = const MavlinkStatusEntity(),
    this.errorMessage = '',
  });

  final MavlinkPhase status;
  final MavlinkStatusEntity link;
  final String errorMessage;

  TelemetryEntity get telemetry => link.telemetry;

  /// A link exists (may or may not still be hearing the vehicle).
  bool get isConnected => link.connected;

  /// Telemetry is flowing right now — the only state safe to fly from.
  bool get isLive => link.alive;

  bool get isBusy => status == MavlinkPhase.connecting;

  /// Short label for the link chip on the mission screens.
  String get label => switch (status) {
    MavlinkPhase.connecting => 'Linking…',
    MavlinkPhase.connected => telemetry.mode ?? 'LINKED',
    MavlinkPhase.stale => 'No signal',
    MavlinkPhase.unavailable => 'No MAVLink',
    MavlinkPhase.failure => 'Link error',
    _ => 'Connect',
  };

  MavlinkState copyWith({
    MavlinkPhase? status,
    MavlinkStatusEntity? link,
    String? errorMessage,
  }) {
    return MavlinkState(
      status: status ?? this.status,
      link: link ?? this.link,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, link, errorMessage];
}
