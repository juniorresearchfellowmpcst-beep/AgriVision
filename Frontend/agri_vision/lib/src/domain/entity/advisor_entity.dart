import 'package:equatable/equatable.dart';

/// One turn in the crop-advisor conversation.
class AdvisorMessage extends Equatable {
  /// `user` or `model` — the same vocabulary the backend and Gemini use, so a
  /// history can be sent straight back without translation.
  final String role;
  final String text;

  /// True while a question is in flight, so the bubble can show a spinner in
  /// the place the answer will appear.
  final bool pending;

  /// Set when this turn failed, so a failed question stays on screen with its
  /// reason instead of vanishing and leaving the farmer wondering.
  final String? error;

  /// Whether the farmer attached a photo to this turn.
  final bool hasImage;

  final DateTime at;

  AdvisorMessage({
    required this.role,
    required this.text,
    this.pending = false,
    this.error,
    this.hasImage = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get failed => error != null;

  AdvisorMessage copyWith({String? text, bool? pending, String? error}) {
    return AdvisorMessage(
      role: role,
      text: text ?? this.text,
      pending: pending ?? this.pending,
      error: error ?? this.error,
      hasImage: hasImage,
      at: at,
    );
  }

  /// The shape the backend wants back as conversation history.
  Map<String, String> toHistoryJson() => {'role': role, 'text': text};

  @override
  List<Object?> get props => [role, text, pending, error, at];
}

/// Whether the advisor is configured on this server.
///
/// This is checked before the "More information" button is shown at all: a
/// button that exists and fails when tapped is worse than one that is absent,
/// especially on a ground station with no internet, which is the normal case
/// for every other feature in this app.
class AdvisorAvailability extends Equatable {
  final bool available;
  final String? model;
  final String message;

  const AdvisorAvailability({
    required this.available,
    required this.model,
    required this.message,
  });

  static const AdvisorAvailability unknown = AdvisorAvailability(
    available: false,
    model: null,
    message: '',
  );

  factory AdvisorAvailability.fromJson(Map<String, dynamic> json) {
    return AdvisorAvailability(
      available: json['available'] == true,
      model: json['model']?.toString(),
      message: json['message']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [available, model];
}
