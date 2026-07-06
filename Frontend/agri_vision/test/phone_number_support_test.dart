import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agri_vision/src/utils/phone_number_support.dart';

void main() {
  group('phone number plugin support', () {
    test('disables initialization on Windows', () {
      expect(isPhoneNumberPluginSupported(TargetPlatform.windows), isFalse);
    });

    test('enables initialization on Android and iOS', () {
      expect(isPhoneNumberPluginSupported(TargetPlatform.android), isTrue);
      expect(isPhoneNumberPluginSupported(TargetPlatform.iOS), isTrue);
    });
  });
}
