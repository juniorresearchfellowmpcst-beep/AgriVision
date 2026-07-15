import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Obtains a Google ID token to exchange with the backend `/api/auth/google`.
///
/// Client IDs are supplied at build/run time (no secrets in the repo), the same
/// way the API base URL is:
///
///   flutter run -d chrome \
///     --dart-define=GOOGLE_WEB_CLIENT_ID=xxxxx.apps.googleusercontent.com
///
///   flutter run            # Android
///     --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxxx.apps.googleusercontent.com
///
/// See docs/GOOGLE_SIGN_IN_SETUP.md for how to create these in Google Cloud.
class GoogleAuth {
  const GoogleAuth._();

  /// OAuth 2.0 **Web application** client ID — required on web.
  static const String webClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// The web client ID passed as `serverClientId` on Android/iOS so the ID
  /// token's audience matches what the backend verifies (GOOGLE_CLIENT_ID).
  static const String serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Whether sign-in can even be attempted on the current platform.
  static bool get isConfigured =>
      kIsWeb ? webClientId.isNotEmpty : true;

  static GoogleSignIn _client() => GoogleSignIn(
        scopes: const ['email', 'profile'],
        clientId: kIsWeb && webClientId.isNotEmpty ? webClientId : null,
        serverClientId: serverClientId.isNotEmpty ? serverClientId : null,
      );

  /// Runs the Google sign-in flow and returns an ID token.
  ///
  /// Returns null if the user cancels. Throws a message-bearing [Exception] if
  /// Google Sign-In isn't configured or no ID token comes back.
  static Future<String?> obtainIdToken() async {
    if (kIsWeb && webClientId.isEmpty) {
      throw Exception(
        'Google Sign-In is not configured. Pass '
        '--dart-define=GOOGLE_WEB_CLIENT_ID=<your web client id> '
        '(see docs/GOOGLE_SIGN_IN_SETUP.md).',
      );
    }

    final google = _client();
    final account = await google.signIn();
    if (account == null) return null; // user dismissed the picker

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception(
        'Google did not return an ID token. On mobile, set '
        'GOOGLE_SERVER_CLIENT_ID so an ID token is issued.',
      );
    }
    return idToken;
  }

  /// Clear the cached Google session (call on sign-out if desired).
  static Future<void> signOut() async {
    try {
      await _client().signOut();
    } catch (_) {
      // best-effort
    }
  }
}
