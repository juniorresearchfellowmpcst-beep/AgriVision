import 'package:flutter/widgets.dart';

import 'app_language.dart';

/// Every string on the farmer-facing screens, in each language.
///
/// A plain lookup rather than generated ARB classes: the translated surface is
/// one flow (pick a crop, photograph it, read the answer, ask about it), the
/// table is short enough to read in one screen, and a build-time codegen step
/// is a poor trade for that. If this grows past a few hundred entries, move to
/// `flutter gen-l10n` — the call sites (`context.l10n.scanTitle`) would not
/// have to change.
///
/// The Hindi is written the way an agri-dealer or a KVK notice writes it:
/// everyday words, and the English term kept where that is genuinely what
/// people say ("कैमरा", "फोटो"). Translating "camera" into a Sanskritised
/// coinage nobody uses would be worse than not translating it.
class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ??
      const AppStrings(AppLanguage.english);

  String _pick(String en, String hi) =>
      language == AppLanguage.hindi ? hi : en;

  // ── Scan with Phone: the crop picker ──────────────────────────────────
  String get scanTitle => _pick('Scan with Phone', 'फोन से जाँच करें');

  String get scanIntroTitle => _pick('No drone needed', 'ड्रोन की ज़रूरत नहीं');

  String get scanIntroBody => _pick(
    'Pick your crop, photograph the plant, and get the diagnosis with what '
        'to spray for it.',
    'अपनी फसल चुनें, पौधे की फोटो लें, और जानें कि क्या रोग है और उसके लिए '
        'क्या छिड़कना है।',
  );

  String get inSeasonNow => _pick('IN SEASON NOW', 'इस समय की फसलें');

  String get inSeasonHint => _pick(
    'What is usually in the ground this month',
    'इस महीने आमतौर पर जो खेत में होता है',
  );

  String get otherCrops => _pick('OTHER CROPS', 'अन्य फसलें');

  String get crops => _pick('CROPS', 'फसलें');

  String get couldNotLoadCrops =>
      _pick('Could not load the crop list.', 'फसलों की सूची नहीं आ सकी।');

  String diseasesKnown(int count) => _pick(
    '$count diseases',
    '$count रोग',
  );

  // ── Scan with Phone: one crop ─────────────────────────────────────────
  String get takePhoto => _pick('Take photo', 'फोटो लें');

  String get gallery => _pick('Gallery', 'गैलरी');

  String get scanning => _pick('Scanning…', 'जाँच हो रही है…');

  String get photographThePlant =>
      _pick('Photograph the plant', 'पौधे की फोटो लें');

  String get framingHint => _pick(
    'Fill the frame with the affected leaf. A photo from three metres away '
        'tells the model very little.',
    'बीमार पत्ते को फ्रेम में पूरा भरें। तीन मीटर दूर से ली गई फोटो से कुछ '
        'पता नहीं चलता।',
  );

  String get cameraPermissionError => _pick(
    'Could not open the camera or gallery. Check the app\'s permissions in '
        'Settings.',
    'कैमरा या गैलरी नहीं खुल सकी। सेटिंग्स में ऐप की अनुमतियाँ देखें।',
  );

  // ── The result ────────────────────────────────────────────────────────
  String get scanResult => _pick('Scan Result', 'जाँच का नतीजा');

  String get scanAgain => _pick('Scan again', 'दोबारा जाँचें');

  String get severity => _pick('Severity', 'गंभीरता');

  String get confidence => _pick('Confidence', 'भरोसा');

  String get engine => _pick('Engine', 'इंजन');

  String get cnnModel => _pick('CNN model', 'CNN मॉडल');

  String get onDeviceRules => _pick('On-device rules', 'फोन के नियम');

  String get whatToLookFor => _pick('What to look for', 'क्या देखें');

  String get whatToDo => _pick('What to do', 'क्या करें');

  String get healthyCrop =>
      _pick('No disease detected', 'कोई रोग नहीं मिला');

  /// Severity levels, for the chip under the diagnosis.
  String severityLevel(String level) => switch (level) {
    'high' => _pick('high', 'ज़्यादा'),
    'moderate' => _pick('moderate', 'मध्यम'),
    'low' => _pick('low', 'कम'),
    _ => _pick('none', 'कोई नहीं'),
  };

  // ── Know More (the crop advisor) ──────────────────────────────────────
  String get knowMore => _pick('Know More', 'और जानें');

  String get knowMoreHint => _pick(
    'Send this photo and the diagnosis to the crop advisor and ask anything.',
    'यह फोटो और जाँच का नतीजा सलाहकार को भेजें और कुछ भी पूछें।',
  );

  String get cropAdvisor => _pick('Crop Advisor', 'फसल सलाहकार');

  String get askAQuestion => _pick('Ask a question…', 'कोई सवाल पूछें…');

  String get thinking => _pick('Thinking…', 'सोच रहा है…');

  String get tryAgain => _pick('Try again', 'दोबारा कोशिश करें');

  String get advisorNeedsInternet => _pick(
    'This is the one feature that sends a field photo off the ground '
        'station, so it needs internet.',
    'यही एक सुविधा है जो खेत की फोटो बाहर भेजती है, इसलिए इसे इंटरनेट चाहिए।',
  );

  String askAbout(String subject) =>
      _pick('Ask about $subject', '$subject के बारे में पूछें');

  String get askAboutYourCrop =>
      _pick('Ask about your crop', 'अपनी फसल के बारे में पूछें');

  String get advisorAttached => _pick(
    'The photo and the diagnosis are already attached.',
    'फोटो और जाँच का नतीजा पहले से जुड़ा है।',
  );

  // ── Treatment ─────────────────────────────────────────────────────────
  String get treatment => _pick('Treatment', 'इलाज');

  String get whatToSpray => _pick('What to spray', 'क्या छिड़कें');

  String get alsoDoThis => _pick('Also do this', 'यह भी करें');

  String get noSprayWillFix => _pick(
    'No spray will fix this. Do the steps below instead.',
    'इसका कोई छिड़काव इलाज नहीं है। नीचे दिए काम करें।',
  );

  String get perAcre => _pick('per acre', 'प्रति एकड़');

  String doNotHarvestFor(int days) => _pick(
    'Do not harvest for $days days after spraying',
    'छिड़काव के बाद $days दिन तक कटाई न करें',
  );

  // ── Settings ──────────────────────────────────────────────────────────
  String get languageLabel => _pick('Language', 'भाषा');

  String get languageSection => _pick('LANGUAGE', 'भाषा');

  String get chooseLanguage => _pick('Choose a language', 'भाषा चुनें');

  String get languageNote => _pick(
    'Changes the crop scanning screens and the language the crop advisor '
        'answers in. The flight and drone screens stay in English.',
    'इससे फसल जाँच की स्क्रीन और सलाहकार के जवाब की भाषा बदलती है। उड़ान और '
        'ड्रोन की स्क्रीन अंग्रेज़ी में ही रहेंगी।',
  );

  // ── Shared ────────────────────────────────────────────────────────────
  String get retry => _pick('Retry', 'दोबारा');

  String get disclaimerShort => _pick(
    'Automated screening — confirm on the ground before spraying.',
    'यह अपने आप की गई जाँच है — छिड़काव से पहले खेत में जाकर पुष्टि करें।',
  );
}

/// Makes the strings reachable as `context.l10n.scanTitle`.
extension AppStringsX on BuildContext {
  AppStrings get l10n => AppStrings.of(this);
}

/// Publishes [AppStrings] into the widget tree.
///
/// A tiny hand-written delegate rather than a generated one: it has exactly one
/// job, and the language is decided by the app's own setting rather than by the
/// device locale. A farmer handed a phone that boots in English still needs to
/// be able to choose Hindi and have it stick.
class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate(this.language);

  final AppLanguage language;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(language);

  @override
  bool shouldReload(AppStringsDelegate old) => old.language != language;
}
