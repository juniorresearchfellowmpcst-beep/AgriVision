import 'package:flutter/foundation.dart';

bool isPhoneNumberPluginSupported(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}
