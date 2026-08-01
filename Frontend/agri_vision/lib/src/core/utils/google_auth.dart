import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Obtains a Google ID token to exchange with the backend `/api/auth/google`.
///
/// Client IDs are configured the same way as the API base URL: the value lives
/// in `assets/.env` (loaded at startup in [bootstrap]) and can be overridden
/// for a single run with `--dart-define`.
///
///   assets/.env:
///     GOOGLE_WEB_CLIENT_ID=xxxxx.apps.googleusercontent.com
///
///   one-off override:
///     flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=xxxxx.apps.googleusercontent.com
///
/// One **Web application** client ID covers every platform — it is used
/// directly on web and as the Android/iOS `serverClientId` so the ID token's
/// audience matches what the backend verifies (GOOGLE_CLIENT_ID).
///
/// See docs/GOOGLE_SIGN_IN_SETUP.md for how to create the credential.
class GoogleAuth {
  const GoogleAuth._();

  /// Optional per-run overrides (compile-time), same idea as `API_BASE_URL`.
  static const String _webClientIdOverride =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const String _serverClientIdOverride =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// OAuth 2.0 **Web application** client ID — required on web. Comes from
  /// `assets/.env` (GOOGLE_WEB_CLIENT_ID); a `--dart-define` of the same name
  /// wins when supplied.
  static String get webClientId {
    if (_webClientIdOverride.isNotEmpty) return _webClientIdOverride;
    return dotenv.get('GOOGLE_WEB_CLIENT_ID', fallback: '');
  }

  /// The client ID passed as `serverClientId` on Android/iOS so the ID token's
  /// audience matches what the backend verifies. Defaults to [webClientId],
  /// which is what it should be — set GOOGLE_SERVER_CLIENT_ID only to override.
  static String get serverClientId {
    if (_serverClientIdOverride.isNotEmpty) return _serverClientIdOverride;
    final fromEnv = dotenv.get('GOOGLE_SERVER_CLIENT_ID', fallback: '');
    return fromEnv.isNotEmpty ? fromEnv : webClientId;
  }

  /// Whether sign-in can even be attempted on the current platform.
  static bool get isConfigured =>
      kIsWeb ? webClientId.isNotEmpty : true;

  static GoogleSignIn _client() {
    final web = webClientId;
    final server = serverClientId;
    return GoogleSignIn(
      scopes: const ['email', 'profile'],
      // Web needs the client ID; passing `serverClientId` on web is rejected by
      // google_sign_in_web, so only send it on mobile.
      clientId: kIsWeb && web.isNotEmpty ? web : null,
      serverClientId: !kIsWeb && server.isNotEmpty ? server : null,
    );
  }

  /// Runs the Google sign-in flow and returns an ID token.
  ///
  /// Returns null if the user cancels. Throws a message-bearing [Exception] if
  /// Google Sign-In isn't configured or no ID token comes back.
  static Future<String?> obtainIdToken() async {
    if (kIsWeb && webClientId.isEmpty) {
      throw Exception(
        'Google Sign-In is not configured. Set GOOGLE_WEB_CLIENT_ID in '
        'assets/.env (or pass --dart-define=GOOGLE_WEB_CLIENT_ID=<web client '
        'id>). See docs/GOOGLE_SIGN_IN_SETUP.md.',
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
        'GOOGLE_WEB_CLIENT_ID (used as serverClientId) so an ID token is issued.',
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
