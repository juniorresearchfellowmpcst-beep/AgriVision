part of 'advisor_cubit.dart';

enum AdvisorStatus {
  initial,
  loading,
  ready,
  asking,

  /// No key configured on this server, so the feature does not exist here.
  /// Distinct from a failure: nothing went wrong, the button should simply
  /// not have been offered.
  unavailable,
}

class AdvisorState extends Equatable {
  final AdvisorStatus status;
  final AdvisorAvailability availability;

  final List<AdvisorMessage> messages;

  /// Starter questions, tailored to what the scan found. Cleared once the
  /// farmer asks something of their own.
  final List<String> suggestions;

  /// The app's own diagnosis, sent with every question so the advisor builds
  /// on the CNN's answer rather than quietly replacing it.
  final Map<String, dynamic>? context;

  /// A photo the phone holds, sent with the first question only.
  final MediaFile? image;
  final bool imageSent;

  /// Ids naming something the server already holds, so a picture on the
  /// ground station is never re-uploaded to it.
  final int? frameId;
  final int? scanId;
  final int? diseaseScanId;
  final int? runId;

  /// What this conversation is about, for the screen's subtitle — the disease
  /// name, or the block.
  final String? subject;

  /// The language the advisor is asked to answer in.
  final AppLanguage language;

  const AdvisorState({
    this.status = AdvisorStatus.initial,
    this.availability = AdvisorAvailability.unknown,
    this.messages = const [],
    this.suggestions = const [],
    this.context,
    this.image,
    this.imageSent = false,
    this.frameId,
    this.scanId,
    this.diseaseScanId,
    this.runId,
    this.subject,
    this.language = AppLanguage.english,
  });

  bool get isAsking => status == AdvisorStatus.asking;
  bool get isLoading => status == AdvisorStatus.loading;
  bool get isUnavailable => status == AdvisorStatus.unavailable;
  bool get hasConversation => messages.isNotEmpty;

  AdvisorState copyWith({
    AdvisorStatus? status,
    AdvisorAvailability? availability,
    List<AdvisorMessage>? messages,
    List<String>? suggestions,
    Map<String, dynamic>? context,
    MediaFile? image,
    bool? imageSent,
    int? frameId,
    int? scanId,
    int? diseaseScanId,
    int? runId,
    String? subject,
    AppLanguage? language,
  }) {
    return AdvisorState(
      status: status ?? this.status,
      availability: availability ?? this.availability,
      messages: messages ?? this.messages,
      suggestions: suggestions ?? this.suggestions,
      context: context ?? this.context,
      image: image ?? this.image,
      imageSent: imageSent ?? this.imageSent,
      frameId: frameId ?? this.frameId,
      scanId: scanId ?? this.scanId,
      diseaseScanId: diseaseScanId ?? this.diseaseScanId,
      runId: runId ?? this.runId,
      subject: subject ?? this.subject,
      language: language ?? this.language,
    );
  }

  @override
  List<Object?> get props => [
    status,
    availability,
    messages,
    suggestions,
    imageSent,
    frameId,
    scanId,
    diseaseScanId,
    runId,
    subject,
    language,
  ];
}
