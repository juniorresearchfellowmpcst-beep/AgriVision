import 'package:flutter/widgets.dart';

/// The languages the app is offered in.
///
/// Two, and that is a deliberate stopping point rather than a first instalment.
/// Madhya Pradesh's farmers read Hindi; the app's operator-facing drone screens
/// are full of terms (MAVLink, NDVI, boustrophedon) that have no settled Hindi
/// rendering and would be *less* usable half-translated. So the farmer-facing
/// surfaces are translated properly and the flight-control screens stay in
/// English, which is what the people flying drones already work in.
///
/// Adding a third language means adding one column to
/// [AppStrings] — no new plumbing.
enum AppLanguage {
  english('en', 'English', 'English'),
  hindi('hi', 'Hindi', 'हिन्दी');

  const AppLanguage(this.code, this.englishName, this.nativeName);

  /// ISO 639-1, and the key stored in preferences.
  final String code;

  /// The name in English, for an operator setting a device up for someone else.
  final String englishName;

  /// The name in its own script. This is what the picker shows first: somebody
  /// looking for Hindi is looking for "हिन्दी", not for the word "Hindi".
  final String nativeName;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) {
    for (final language in AppLanguage.values) {
      if (language.code == code) return language;
    }
    return AppLanguage.english;
  }

  /// The language name to send the crop advisor, so Gemini answers in it
  /// rather than guessing from the farmer's typing.
  String get advisorName => switch (this) {
    AppLanguage.english => 'English',
    AppLanguage.hindi => 'Hindi (हिन्दी)',
  };
}
