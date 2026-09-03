import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/ui/widget/advisor/markdown_text.dart';

/// The advisor's answers are Markdown. These check they are *rendered* rather
/// than printed — the failure being that the farmer reads the asterisks
/// instead of the advice.
///
/// The fixtures are real Gemini output captured from this app's own endpoint,
/// not invented samples: whatever the model actually does is what has to
/// survive the renderer.

/// A genuine reply about spraying soybean rust at flowering.
const _realAnswer = '''
Generally, **avoid spraying insecticides during peak flowering** unless there is a severe pest or disease outbreak.

Here is why and how to spray safely if you must:

### Risks of Spraying at Flowering
* **Kills Pollinators:** Honeybees and other beneficial insects pollinating your crop are killed on contact.
* **Poor pod set:** Losing pollinators at flowering costs yield directly.

### If you must spray
1. Spray in the **evening**, after pollinators have left the crop.
2. Use `Hexaconazole 5% EC` at 400 ml per acre in 200 L of water.
3. Do not harvest for *30 days* after spraying.

---

Confirm with your local KVK before applying.
''';

/// The reply when the photo is not usable — note the em dash and the bold
/// lead-in, both of which the renderer has to leave intact.
const _rejectAnswer = '''
The uploaded image does not show an actual crop or plant—it appears to be a solid green and brown graphic.

**What you should do:**
* Take a fresh, clear close-up photo of the affected plant parts.
* Make sure the camera focuses clearly on the specific symptoms.
''';

Future<void> pump(WidgetTester tester, String source) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarkdownText(source, color: AppColors.dark700),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Every character the widget paints.
///
/// Both widget types have to be walked: a `SelectableText` renders through
/// `EditableText`, not `RichText`, so a helper that reads only `RichText` sees
/// the bullet markers and none of the prose — which looks exactly like the
/// renderer having dropped the text.
String rendered(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final w in tester.widgetList(find.byType(Text))) {
    final text = w as Text;
    buffer.writeln(text.data ?? text.textSpan?.toPlainText() ?? '');
  }
  for (final w in tester.widgetList(find.byType(SelectableText))) {
    final text = w as SelectableText;
    buffer.writeln(text.data ?? text.textSpan?.toPlainText() ?? '');
  }
  return buffer.toString();
}

void main() {
  group('markers are consumed, not shown', () {
    testWidgets('no stray asterisks survive a real answer', (tester) async {
      await pump(tester, _realAnswer);
      final text = rendered(tester);

      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('###')));
      expect(text, isNot(contains('`')));
      // The words themselves are all still there.
      expect(text, contains('avoid spraying insecticides during peak flowering'));
      expect(text, contains('Risks of Spraying at Flowering'));
      expect(text, contains('Hexaconazole 5% EC'));
      expect(text, contains('Kills Pollinators'));
    });

    testWidgets('a bold lead-in keeps its colon and its text', (tester) async {
      await pump(tester, _rejectAnswer);
      final text = rendered(tester);

      expect(text, contains('What you should do:'));
      expect(text, isNot(contains('**What you should do:**')));
      // An em dash inside a sentence must not be mistaken for a rule.
      expect(text, contains('plant—it appears'));
    });
  });

  group('block structure', () {
    testWidgets('bullets get a marker and numbers keep their own', (
      tester,
    ) async {
      await pump(tester, _realAnswer);
      final text = rendered(tester);

      expect(text, contains('•'));
      expect(text, contains('1.'));
      expect(text, contains('2.'));
      expect(text, contains('3.'));
    });

    testWidgets('a horizontal rule becomes a line, not three dashes', (
      tester,
    ) async {
      await pump(tester, _realAnswer);
      expect(rendered(tester), isNot(contains('---')));
    });

    testWidgets('a fenced code block keeps its line breaks', (tester) async {
      await pump(tester, '''
Run this:

```
curl -X POST localhost:5000/api/spray/stop
echo done
```
''');
      final text = rendered(tester);
      expect(text, contains('curl -X POST localhost:5000/api/spray/stop'));
      expect(text, contains('echo done'));
      expect(text, isNot(contains('```')));
    });

    testWidgets('an unterminated fence still shows its text', (tester) async {
      // A truncated answer is a reason to show less formatting, never to
      // silently drop the words.
      await pump(tester, 'Try:\n\n```\nflask db upgrade');
      expect(rendered(tester), contains('flask db upgrade'));
    });
  });

  group('robustness', () {
    testWidgets('plain prose renders unchanged', (tester) async {
      const plain = 'Spray in the evening when the bees have gone.';
      await pump(tester, plain);
      expect(rendered(tester), contains(plain));
    });

    testWidgets('a lone asterisk is not treated as emphasis', (tester) async {
      await pump(tester, 'Use 400 ml * 2 acres of product.');
      expect(rendered(tester), contains('400 ml * 2 acres'));
    });

    testWidgets('empty input renders nothing rather than throwing', (
      tester,
    ) async {
      await pump(tester, '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hindi markdown renders with its markers consumed', (
      tester,
    ) async {
      await pump(tester, '**शाम को छिड़काव करें।**\n\n* मधुमक्खियों को बचाएँ');
      final text = rendered(tester);
      expect(text, contains('शाम को छिड़काव करें।'));
      expect(text, isNot(contains('**')));
      expect(text, contains('•'));
    });

    testWidgets('a long answer does not overflow a narrow phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pump(tester, _realAnswer);
      expect(tester.takeException(), isNull);
    });
  });
}
