part of 'spray_cubit.dart';

enum SprayStatus {
  initial,
  prescribing, // clustering the capture
  ready, // options on screen, waiting for the operator
  planning, // building the mission for the chosen option
  planned, // mission ready, nothing sent yet
  sending, // uploading to the aircraft
  uploaded, // on the vehicle, not launched
  spraying, // flying the prescription
  failure,
}

class SprayState extends Equatable {
  final SprayStatus status;
  final SprayPrescription? prescription;

  /// The option the operator picked — `severe_only` or `severe_moderate`.
  final String? selectedOption;

  /// What that choice would actually fly, and what it would actually cost.
  final SprayPlan? plan;

  final List<SprayPrescriptionSummary> history;
  final String message;
  final String errorMessage;

  const SprayState({
    this.status = SprayStatus.initial,
    this.prescription,
    this.selectedOption,
    this.plan,
    this.history = const [],
    this.message = '',
    this.errorMessage = '',
  });

  bool get isBusy =>
      status == SprayStatus.prescribing ||
      status == SprayStatus.planning ||
      status == SprayStatus.sending;

  bool get hasPrescription => prescription != null && prescription!.isOk;
  bool get hasPlan => plan != null;

  /// True once the mission is on the vehicle — the point past which "cancel"
  /// means stopping an aircraft, not closing a screen.
  bool get isOnVehicle =>
      status == SprayStatus.uploaded || status == SprayStatus.spraying;

  SprayState copyWith({
    SprayStatus? status,
    SprayPrescription? prescription,
    String? selectedOption,
    SprayPlan? plan,
    List<SprayPrescriptionSummary>? history,
    String? message,
    String? errorMessage,
    bool clearPrescription = false,
    bool clearPlan = false,
    bool clearOption = false,
  }) {
    return SprayState(
      status: status ?? this.status,
      prescription: clearPrescription ? null : (prescription ?? this.prescription),
      selectedOption: clearOption ? null : (selectedOption ?? this.selectedOption),
      plan: clearPlan ? null : (plan ?? this.plan),
      history: history ?? this.history,
      message: message ?? this.message,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    prescription,
    selectedOption,
    plan,
    history,
    message,
    errorMessage,
  ];
}
