import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agri_vision/src/core/networks/api_config.dart';
import 'package:agri_vision/src/ui/view/Legal/legal_document_page.dart';

/// The Play Store requirements that live in the app itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a release build never ships pointed at the phone itself', () {
    // assets/.env is bundled into the app, so whatever a developer last
    // pointed it at ships with it. On a phone 127.0.0.1 is the phone, and
    // 10.0.2.2 exists only inside the emulator.
    test('device-local addresses are recognised', () {
      for (final url in [
        'http://127.0.0.1:5000',
        'http://localhost:5000',
        'http://10.0.2.2:5000',
        'http://0.0.0.0:5000',
        'http://[::1]:5000',
        '',
        'not a url',
      ]) {
        expect(ApiConfig.isDeviceLocal(url), isTrue, reason: url);
      }
    });

    test('addresses a phone can actually reach are left alone', () {
      // A ground station on the field's own network is a real release setup.
      for (final url in [
        'https://agrivision-production-ae8e.up.railway.app',
        'http://192.168.1.3:5000',
        'http://10.0.0.5:5000',
      ]) {
        expect(ApiConfig.isDeviceLocal(url), isFalse, reason: url);
      }
    });

    test('the fallback is the deployed, encrypted backend', () {
      expect(ApiConfig.productionBaseUrl, startsWith('https://'));
      expect(ApiConfig.isDeviceLocal(ApiConfig.productionBaseUrl), isFalse);
    });
  });

  group('the privacy policy and terms', () {
    for (final name in ['privacy_policy.md', 'terms.md']) {
      test('the bundled $name is the one the backend serves', () {
        // One document, two copies: the web page Google reviews and the page
        // a farmer reads in the app must say the same thing.
        String read(String path) =>
            File(path).readAsStringSync().replaceAll('\r\n', '\n');
        expect(
          read('assets/legal/$name'),
          read('../../backend/my_flask_app/app/legal/$name'),
          reason: 'copy backend/my_flask_app/app/legal/$name to assets/legal/',
        );
      });
    }

    test('both are declared as app assets', () async {
      for (final document in LegalDocument.values) {
        expect(await rootBundle.loadString(document.asset), isNotEmpty);
      }
    });

    test('the policy covers what Play asks about', () {
      final policy = File('assets/legal/privacy_policy.md').readAsStringSync();
      for (final required in [
        'Delete account',
        '/account/delete',
        'Google Gemini',
        'location',
        'do not sell',
      ]) {
        expect(policy, contains(required), reason: required);
      }
    });

    testWidgets('the policy opens and reads as text, not markup', (
      tester,
    ) async {
      final text = await tester.runAsync(
        () => rootBundle.loadString(LegalDocument.privacy.asset),
      );
      expect(text, isNotNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: LegalDocumentPage(document: LegalDocument.privacy),
        ),
      );
      // The asset is read with real file I/O, which never completes on the
      // test's fake clock -- so `pumpAndSettle` waits forever on the loading
      // spinner. Let the read finish in real time, then rebuild with the text.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('AgriVision Privacy Policy'), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
    });
  });
}
