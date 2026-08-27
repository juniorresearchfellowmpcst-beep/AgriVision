import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// App logging.
///
/// Two levels of caution, both about a release build:
///
///   * **Chatter is dropped.** Info and success lines exist to follow a flow
///     at a desk. In release they are noise in logcat, and the ones that log
///     requests can carry a URL with a token or a camera password in it.
///     Warnings and errors survive, because those are what a bug report needs.
///   * **Colour codes are debug-only.** The ANSI escapes make a terminal
///     readable and make a device log unreadable.
class Logger {
  const Logger._();

  /// Info — development only.
  static void i(Object msg, {String tag = ''}) {
    if (kReleaseMode) return;
    _print(_paint(msg, '\x1B[34m'), tag);
  }

  /// Success — development only.
  static void s(Object msg, {String tag = ''}) {
    if (kReleaseMode) return;
    _print(_paint(msg, '\x1B[32m'), tag);
  }

  /// Warning — kept in release.
  static void w(Object msg, {String tag = ''}) {
    _print(_paint(msg, '\x1B[33m'), tag, level: 900);
  }

  /// Error — kept in release.
  static void e(Object msg, {String tag = ''}) {
    _print(_paint(msg, '\x1B[31m'), tag, level: 1000);
  }

  static String _paint(Object msg, String colour) =>
      kReleaseMode ? '$msg' : '$colour$msg\x1B[0m';

  static void _print(String msg, String? tag, {int level = 800}) {
    developer.log(msg, name: tag ?? '', level: level);
  }
}
