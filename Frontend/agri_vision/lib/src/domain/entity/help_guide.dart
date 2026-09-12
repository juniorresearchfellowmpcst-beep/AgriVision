import 'package:flutter/material.dart';

import '../../core/l10n/app_language.dart';

/// The "how do I use this?" content, in both languages.
///
/// It lives here rather than in [AppStrings] because it is not labels: it is
/// the few paragraphs that turn a screen full of buttons into something a
/// farmer can follow the first time, and the table of short UI strings would
/// stop being readable with them in it.
///
/// Every guide answers the same two questions in order — *what is this for*,
/// then *what do I press* — and ends with a way to go straight there. A help
/// page that describes a screen without taking you to it just adds a step.

/// Where a guide can send the operator when they ask to be shown.
///
/// Named rather than a route string, because two of these are not routes: the
/// map and settings are tabs of the home shell, and the drone link is a sheet.
enum HelpTarget { cropScan, survey, missionMap, spray, capture, droneLink }

class HelpStep {
  const HelpStep(this.text, {this.note});

  final String text;

  /// The thing people get wrong at this step, where there is one.
  final String? note;
}

class HelpGuide {
  const HelpGuide({
    required this.id,
    required this.icon,
    required this.title,
    required this.summary,
    required this.steps,
    this.target,
    this.openLabel,
    this.needsDrone = false,
  });

  final String id;
  final IconData icon;
  final String title;
  final String summary;
  final List<HelpStep> steps;

  /// Where "show me" goes. Null for a guide that is only an explanation.
  final HelpTarget? target;
  final String? openLabel;

  /// Marked so nobody works through a guide only to find they needed hardware.
  final bool needsDrone;
}

/// The labels of the help screen itself.
class HelpStrings {
  const HelpStrings({
    required this.title,
    required this.subtitle,
    required this.sectionLabel,
    required this.firstTimeTitle,
    required this.firstTimeBody,
    required this.showMe,
    required this.notNow,
    required this.openDefault,
    required this.needsDroneLabel,
  });

  final String title;
  final String subtitle;
  final String sectionLabel;
  final String firstTimeTitle;
  final String firstTimeBody;
  final String showMe;
  final String notNow;
  final String openDefault;
  final String needsDroneLabel;
}

String _pick(AppLanguage language, String en, String hi) =>
    language == AppLanguage.hindi ? hi : en;

HelpStrings helpStrings(AppLanguage language) {
  String p(String en, String hi) => _pick(language, en, hi);

  return HelpStrings(
    title: p('Help', 'मदद'),
    subtitle: p('How to use AgriVision', 'AgriVision कैसे इस्तेमाल करें'),
    sectionLabel: p('HELP', 'मदद'),
    firstTimeTitle: p('First time here?', 'पहली बार आए हैं?'),
    firstTimeBody: p(
      'A short guide walks you through the first scan, the first flight and '
          'the first spray.',
      'एक छोटी गाइड पहली जाँच, पहली उड़ान और पहले छिड़काव तक साथ ले जाती है।',
    ),
    showMe: p('Show me how', 'तरीका दिखाएँ'),
    notNow: p('Not now', 'अभी नहीं'),
    openDefault: p('Open this screen', 'यह स्क्रीन खोलें'),
    needsDroneLabel: p('Needs a drone', 'ड्रोन चाहिए'),
  );
}

/// Every guide, in the order a first-time operator needs them.
List<HelpGuide> helpGuides(AppLanguage language) {
  String p(String en, String hi) => _pick(language, en, hi);

  return [
    HelpGuide(
      id: 'start-here',
      icon: Icons.flag_outlined,
      title: p('Start here — what to do first', 'यहाँ से शुरू करें — पहले क्या करें'),
      summary: p(
        'The whole app in six steps, in the order that makes sense.',
        'पूरा ऐप छह कदमों में, उसी क्रम में जिसमें करना चाहिए।',
      ),
      steps: [
        HelpStep(
          p(
            'Scan a plant with your phone. It is the quickest way to see what '
                'the app does.',
            'फोन से किसी पौधे की जाँच करें। ऐप क्या करता है, यह देखने का सबसे '
                'तेज़ तरीका यही है।',
          ),
          note: p(
            'Everything else on the app needs a drone. This one does not.',
            'ऐप की बाकी सब चीज़ों के लिए ड्रोन चाहिए, इसके लिए नहीं।',
          ),
        ),
        HelpStep(
          p(
            'Pair your drone and open the telemetry link, so the app can see '
                'its battery, GPS and position.',
            'अपना ड्रोन जोड़ें और टेलीमेट्री लिंक खोलें, जिससे ऐप को उसकी '
                'बैटरी, GPS और जगह दिखने लगे।',
          ),
        ),
        HelpStep(
          p(
            'Draw the block you want to survey on the map.',
            'मैप पर वह खेत बनाएँ जिसका सर्वे करना है।',
          ),
        ),
        HelpStep(
          p(
            'Fly the survey. The app scans every frame while the drone flies.',
            'सर्वे उड़ान करें। ड्रोन के उड़ते समय ऐप हर फ्रेम की जाँच करता है।',
          ),
        ),
        HelpStep(
          p(
            'Read the report: what was found, where it was found, and what to '
                'do about it.',
            'रिपोर्ट पढ़ें: क्या मिला, कहाँ मिला, और उसका क्या करना है।',
          ),
        ),
        HelpStep(
          p(
            'Spray only the marked zones, after filling the tank and giving '
                'permission.',
            'टंकी भरकर और अनुमति देकर, सिर्फ़ चिह्नित हिस्सों पर छिड़काव करें।',
          ),
        ),
      ],
    ),

    HelpGuide(
      id: 'phone-scan',
      icon: Icons.photo_camera_outlined,
      title: p('Scan a plant with your phone', 'फोन से पौधे की जाँच करें'),
      summary: p(
        'Photograph a leaf, and get the disease with what to spray for it.',
        'पत्ते की फोटो लें, और जानें कौन-सा रोग है और उसके लिए क्या छिड़कें।',
      ),
      target: HelpTarget.cropScan,
      openLabel: p('Open Scan with Phone', '“फोन से जाँच करें” खोलें'),
      steps: [
        HelpStep(
          p(
            'Open Scan with Phone and pick your crop.',
            '“फोन से जाँच करें” खोलें और अपनी फसल चुनें।',
          ),
        ),
        HelpStep(
          p(
            'Fill the frame with the affected leaf, and take the photo.',
            'बीमार पत्ते को फ्रेम में पूरा भरें, और फोटो लें।',
          ),
          note: p(
            'A photo from three metres away tells the model very little.',
            'तीन मीटर दूर से ली गई फोटो से मॉडल को कुछ पता नहीं चलता।',
          ),
        ),
        HelpStep(
          p(
            'Read the result: the disease, how sure the app is, and the '
                'treatment for it.',
            'नतीजा पढ़ें: कौन-सा रोग है, ऐप कितना पक्का है, और उसका इलाज क्या है।',
          ),
        ),
        HelpStep(
          p(
            'Tap More information to ask the crop advisor about it in your '
                'own words.',
            'अपनी भाषा में सवाल पूछने के लिए “और जानकारी” दबाएँ।',
          ),
        ),
      ],
    ),

    HelpGuide(
      id: 'drone-link',
      icon: Icons.settings_input_antenna,
      title: p('Connect the drone', 'ड्रोन जोड़ें'),
      summary: p(
        'Two separate things: the aircraft itself, and the telemetry link that '
            'carries its readings.',
        'दो अलग चीज़ें: एक ड्रोन खुद, और दूसरा टेलीमेट्री लिंक जो उसकी जानकारी '
            'लाता है।',
      ),
      target: HelpTarget.droneLink,
      openLabel: p('Open Connect Drone', '“ड्रोन जोड़ें” खोलें'),
      needsDrone: true,
      steps: [
        HelpStep(
          p(
            'Open Connect Drone and enter the serial number of your aircraft.',
            '“ड्रोन जोड़ें” खोलें और अपने ड्रोन का सीरियल नंबर डालें।',
          ),
        ),
        HelpStep(
          p(
            'Plug the telemetry radio into the computer running the server, '
                'and switch the drone on.',
            'टेलीमेट्री रेडियो को उस कंप्यूटर में लगाएँ जिस पर सर्वर चल रहा है, '
                'और ड्रोन चालू करें।',
          ),
          note: p(
            'The server has to run on a computer at the field. A drone cannot '
                'reach a server on the internet.',
            'सर्वर खेत पर मौजूद कंप्यूटर पर ही चलना चाहिए। इंटरनेट पर चल रहे '
                'सर्वर तक ड्रोन नहीं पहुँच सकता।',
          ),
        ),
        HelpStep(
          p(
            'Choose the address: a radio is COM5 or /dev/ttyUSB0, a Wi-Fi link '
                'is udpin:0.0.0.0:14550.',
            'पता चुनें: रेडियो के लिए COM5 या /dev/ttyUSB0, और Wi-Fi लिंक के '
                'लिए udpin:0.0.0.0:14550।',
          ),
        ),
        HelpStep(
          p(
            'For a radio, pick the speed as well — 57600 unless yours is set '
                'to something else.',
            'रेडियो के लिए स्पीड भी चुनें — आमतौर पर 57600।',
          ),
        ),
        HelpStep(
          p(
            'Tap Connect. Once the chip turns green, the readings are live.',
            '“कनेक्ट” दबाएँ। चिह्न हरा होते ही जानकारी आने लगती है।',
          ),
        ),
      ],
    ),

    HelpGuide(
      id: 'mission-map',
      icon: Icons.add_location_alt_outlined,
      title: p('Draw the block on the map', 'मैप पर खेत बनाएँ'),
      summary: p(
        'The path the drone will fly, and how high and how fast it goes.',
        'ड्रोन किस रास्ते, कितनी ऊँचाई और कितनी रफ़्तार से उड़ेगा।',
      ),
      target: HelpTarget.missionMap,
      openLabel: p('Open the map', 'मैप खोलें'),
      steps: [
        HelpStep(
          p(
            'Open the Map tab and tap the corners of your field, or import a '
                'KML boundary.',
            '“मैप” टैब खोलें और खेत के कोनों पर टैप करें, या KML फ़ाइल लें।',
          ),
        ),
        HelpStep(
          p(
            'Set the height and the speed in the sheet at the bottom.',
            'नीचे की शीट में ऊँचाई और रफ़्तार तय करें।',
          ),
          note: p(
            '120 m above the ground is the legal limit, and the app will not '
                'send a mission above it.',
            'ज़मीन से 120 मीटर तक ही उड़ाने की अनुमति है, और ऐप इससे ऊपर का '
                'मिशन नहीं भेजेगा।',
          ),
        ),
        HelpStep(
          p(
            'Save the mission, so the same block can be flown again next week.',
            'मिशन सेव करें, ताकि अगले हफ़्ते वही खेत दोबारा उड़ाया जा सके।',
          ),
        ),
        HelpStep(
          p(
            'Tap Start Mission, choose the flight profile, and read the '
                'pre-flight check before the drone arms.',
            '“मिशन शुरू करें” दबाएँ, उड़ान का तरीका चुनें, और ड्रोन चालू होने '
                'से पहले उड़ान-पूर्व जाँच पढ़ें।',
          ),
        ),
      ],
    ),

    HelpGuide(
      id: 'survey',
      icon: Icons.flight_takeoff,
      title: p('Fly a survey', 'सर्वे उड़ान करें'),
      summary: p(
        'The drone flies the block while the app scans what its camera sees.',
        'ड्रोन खेत के ऊपर उड़ता है और ऐप उसके कैमरे में जो दिखता है उसकी जाँच '
            'करता है।',
      ),
      target: HelpTarget.survey,
      openLabel: p('Open Survey Flight', '“सर्वे उड़ान” खोलें'),
      needsDrone: true,
      steps: [
        HelpStep(
          p(
            'Open Survey Flight and choose which camera the drone is carrying.',
            '“सर्वे उड़ान” खोलें और चुनें कि ड्रोन पर कौन-सा कैमरा लगा है।',
          ),
        ),
        HelpStep(
          p(
            'Start the run. What is found appears as the drone flies, with the '
                'place each one was seen.',
            'उड़ान शुरू करें। ड्रोन के उड़ते ही जो मिलता है वह अपनी जगह के साथ '
                'दिखने लगता है।',
          ),
          note: p(
            'Without a GPS fix the findings cannot be put on the map, so the '
                'spray step has nowhere to send the drone.',
            'GPS फिक्स के बिना मिली चीज़ें नक्शे पर नहीं आतीं, इसलिए छिड़काव के '
                'लिए कोई जगह तय नहीं हो पाती।',
          ),
        ),
        HelpStep(
          p(
            'Finish the run to get the report: crop health, what was found, '
                'and the action plan.',
            'उड़ान पूरी करें और रिपोर्ट लें: फसल की सेहत, क्या मिला, और आगे '
                'क्या करना है।',
          ),
        ),
        HelpStep(
          p(
            'If a treatment map was made, the spray follows straight on from '
                'it.',
            'अगर इलाज का नक्शा बना है, तो छिड़काव उसी से आगे बढ़ता है।',
          ),
        ),
      ],
    ),

    HelpGuide(
      id: 'spray',
      icon: Icons.water_drop_outlined,
      title: p(
        'Spray only where it is needed',
        'सिर्फ़ ज़रूरत वाली जगह छिड़काव करें',
      ),
      summary: p(
        'The map decides where the valve opens, so healthy crop is skipped.',
        'नक्शा तय करता है कि वॉल्व कहाँ खुलेगा, जिससे स्वस्थ फसल छूट जाती है।',
      ),
      target: HelpTarget.spray,
      openLabel: p('Open Targeted Spray', '“छिड़काव” खोलें'),
      needsDrone: true,
      steps: [
        HelpStep(
          p(
            'Open the treatment map from a survey report, or the spray screen '
                'from a multispectral shot.',
            'सर्वे रिपोर्ट से इलाज का नक्शा खोलें, या मल्टीस्पेक्ट्रल फोटो से '
                '“छिड़काव” स्क्रीन खोलें।',
          ),
        ),
        HelpStep(
          p(
            'Pick how much to treat: the severe zones only, or the moderate '
                'ones as well. Each choice shows the chemical it saves.',
            'चुनें कितना इलाज करना है: सिर्फ़ ज़्यादा बीमार हिस्से, या मध्यम '
                'भी। हर विकल्प के साथ दिखता है कि कितनी दवा बचेगी।',
          ),
        ),
        HelpStep(
          p(
            'Fill the tank, say who is authorising the spray, and confirm the '
                'field is clear.',
            'टंकी भरें, बताएँ कि छिड़काव की अनुमति कौन दे रहा है, और पक्का '
                'करें कि खेत खाली है।',
          ),
          note: p(
            'Nobody should be in the field or downwind of it. The app cannot '
                'see that for you.',
            'खेत में या हवा की दिशा में कोई नहीं होना चाहिए। ऐप यह नहीं देख '
                'सकता।',
          ),
        ),
        HelpStep(
          p(
            'While it sprays: Stop spray shuts the valve, and Return home or '
                'Land brings the drone down.',
            'छिड़काव के दौरान: “छिड़काव रोकें” वॉल्व बंद करता है, और “वापस घर” '
                'या “यहीं उतारें” ड्रोन को नीचे लाता है।',
          ),
        ),
      ],
    ),

    HelpGuide(
      id: 'first-real-flight',
      icon: Icons.shield_outlined,
      title: p('Before the first real flight', 'पहली असली उड़ान से पहले'),
      summary: p(
        'What to check the first time an actual aircraft is on the link.',
        'जब पहली बार असली ड्रोन जुड़े, तब क्या-क्या देखना है।',
      ),
      target: HelpTarget.droneLink,
      openLabel: p('Open Connect Drone', '“ड्रोन जोड़ें” खोलें'),
      needsDrone: true,
      steps: [
        HelpStep(
          p(
            'Try it with the propellers off first: connect, watch the readings '
                'change, send a mission, then cancel.',
            'पहले बिना पंखों के करें: लिंक जोड़ें, जानकारी बदलती हुई देखें, '
                'मिशन भेजें, फिर रद्द कर दें।',
          ),
        ),
        HelpStep(
          p(
            'Wait for a 3-D GPS fix and a battery above 30%. The app will not '
                'launch without them.',
            '3-D GPS फिक्स और 30% से ज़्यादा बैटरी का इंतज़ार करें। इनके बिना '
                'ऐप उड़ान शुरू नहीं करेगा।',
          ),
        ),
        HelpStep(
          p(
            'Keep the transmitter switched on and in your hands.',
            'रिमोट चालू रखें और अपने हाथ में रखें।',
          ),
          note: p(
            'A mode switch on the transmitter overrides anything the app '
                'asked the drone to do.',
            'रिमोट का मोड स्विच ऐप के किसी भी आदेश पर भारी पड़ता है।',
          ),
        ),
        HelpStep(
          p(
            'Choose an empty field, a small block and a low speed for the '
                'first flight.',
            'पहली उड़ान के लिए खाली खेत, छोटा हिस्सा और कम रफ़्तार चुनें।',
          ),
        ),
        HelpStep(
          p(
            'For the first spray, put only water in the tank.',
            'पहले छिड़काव में टंकी में सिर्फ़ पानी डालें।',
          ),
        ),
      ],
    ),
  ];
}
