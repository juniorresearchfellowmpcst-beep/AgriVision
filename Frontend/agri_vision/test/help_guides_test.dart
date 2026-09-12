import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agri_vision/src/core/l10n/app_language.dart';
import 'package:agri_vision/src/core/l10n/app_strings.dart';
import 'package:agri_vision/src/domain/entity/help_guide.dart';
import 'package:agri_vision/src/ui/view/Help/help_page.dart';

/// Devanagari. A "translation" that is still the English sentence is the
/// failure this looks for — it reads as broken rather than as unsupported,
/// and the farmer this app is for is the one who meets it.
final _hindi = RegExp(r'[ऀ-ॿ]');

void main() {
  final english = helpGuides(AppLanguage.english);
  final hindi = helpGuides(AppLanguage.hindi);

  group('the guides', () {
    test('lead with the one that says what order to do things in', () {
      // Somebody opening Help for the first time is not looking for a
      // reference; they are looking for where to start.
      expect(english.first.id, 'start-here');
      expect(english.first.target, isNull, reason: 'it is the map, not a door');
    });

    test('each has an id of its own', () {
      final ids = english.map((guide) => guide.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('each is written as steps, not as a paragraph', () {
      for (final guide in english) {
        expect(guide.steps.length, greaterThanOrEqualTo(3), reason: guide.id);
        for (final step in guide.steps) {
          expect(step.text.trim(), isNotEmpty, reason: guide.id);
        }
      }
    });

    test('the ones that need hardware say so', () {
      final needsDrone = {
        for (final guide in english) guide.id: guide.needsDrone,
      };
      expect(needsDrone['phone-scan'], isFalse);
      expect(needsDrone['survey'], isTrue);
      expect(needsDrone['spray'], isTrue);
      expect(needsDrone['drone-link'], isTrue);
    });

    test('every one that offers to take you somewhere labels the button', () {
      for (final guide in english.where((g) => g.target != null)) {
        expect(guide.openLabel?.trim(), isNotEmpty, reason: guide.id);
      }
    });
  });

  group('Hindi', () {
    test('the two languages describe the same guides, in the same order', () {
      expect(
        hindi.map((guide) => guide.id).toList(),
        english.map((guide) => guide.id).toList(),
      );
      for (var i = 0; i < english.length; i++) {
        expect(hindi[i].steps.length, english[i].steps.length,
            reason: english[i].id);
      }
    });

    test('every guide is actually translated, not copied', () {
      for (var i = 0; i < hindi.length; i++) {
        final guide = hindi[i];
        expect(guide.title, matches(_hindi), reason: '${guide.id} title');
        expect(guide.summary, matches(_hindi), reason: '${guide.id} summary');
        expect(guide.title, isNot(english[i].title), reason: guide.id);

        for (var s = 0; s < guide.steps.length; s++) {
          expect(
            guide.steps[s].text,
            matches(_hindi),
            reason: '${guide.id} step ${s + 1}',
          );
          final note = guide.steps[s].note;
          if (note != null) {
            expect(note, matches(_hindi), reason: '${guide.id} note ${s + 1}');
          }
        }
      }
    });

    test('a note in one language is a note in the other', () {
      for (var i = 0; i < english.length; i++) {
        for (var s = 0; s < english[i].steps.length; s++) {
          expect(
            hindi[i].steps[s].note != null,
            english[i].steps[s].note != null,
            reason: '${english[i].id} step ${s + 1}',
          );
        }
      }
    });

    testWidgets('the screen itself is in Hindi when the app is', (
      tester,
    ) async {
      await _pumpHelp(tester, language: AppLanguage.hindi);
      expect(find.text(helpGuides(AppLanguage.hindi).first.title), findsOneWidget);
    });

    test('the screen around the guides is translated too', () {
      final en = helpStrings(AppLanguage.english);
      final hi = helpStrings(AppLanguage.hindi);

      for (final pair in <(String, String)>[
        (en.title, hi.title),
        (en.subtitle, hi.subtitle),
        (en.firstTimeTitle, hi.firstTimeTitle),
        (en.firstTimeBody, hi.firstTimeBody),
        (en.showMe, hi.showMe),
        (en.notNow, hi.notNow),
        (en.openDefault, hi.openDefault),
        (en.needsDroneLabel, hi.needsDroneLabel),
      ]) {
        expect(pair.$1.trim(), isNotEmpty);
        expect(pair.$2, matches(_hindi), reason: pair.$1);
      }
    });
  });

  group('the help screen', () {
    testWidgets('opens on the guide that says where to start', (tester) async {
      await _pumpHelp(tester);

      // Unfolded, so the first thing to do is on screen without a tap.
      expect(find.text('Start here — what to do first'), findsOneWidget);
      expect(
        find.textContaining('It is the quickest way to see what the app does'),
        findsOneWidget,
      );

      // The rest are there, folded, in order.
      expect(find.text('Scan a plant with your phone'), findsOneWidget);
      expect(find.text('Connect the drone'), findsOneWidget);
    });

    testWidgets('can be opened straight at one guide', (tester) async {
      await _pumpHelp(tester, guideId: 'spray');

      expect(
        find.textContaining('Fill the tank'),
        findsOneWidget,
        reason: 'the named guide should be the unfolded one',
      );
    });

    testWidgets('marks the guides that need an aircraft', (tester) async {
      await _pumpHelp(tester, guideId: 'drone-link');
      expect(find.text('Needs a drone'), findsWidgets);
    });
  });
}

/// A tall surface: the point of these is what the page contains, and a 600 px
/// test window would leave the later guides unbuilt and "missing".
Future<void> _pumpHelp(
  WidgetTester tester, {
  String? guideId,
  AppLanguage language = AppLanguage.english,
}) async {
  tester.view.physicalSize = const Size(420 * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: language.locale,
      localizationsDelegates: [AppStringsDelegate(language)],
      home: HelpPage(openGuideId: guideId),
    ),
  );
  await tester.pump();
}
