import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agri_vision/src/core/l10n/app_language.dart';

part 'language_cubit_state.dart';

/// The app's language, and the one place it is remembered.
///
/// Stored on the device rather than server-side, unlike the notification
/// toggles. Language is a property of the person holding *this* phone: a
/// shared ground-station handset passed between an operator and a farmer
/// should not have its language follow whoever last signed in, and the setting
/// has to work before anybody signs in at all.
class LanguageCubit extends Cubit<LanguageState> {
  LanguageCubit() : super(const LanguageState());

  static const String _storageKey = 'app_language';

  /// Read the stored choice. Called once at startup, before the first frame,
  /// so the app never paints English and then flips to Hindi.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (isClosed) return;
      emit(
        LanguageState(
          language: AppLanguage.fromCode(stored),
          loaded: true,
        ),
      );
    } catch (_) {
      // A preferences failure must not stop the app starting. English is the
      // safe fallback: it is what the drone screens are in regardless.
      if (isClosed) return;
      emit(const LanguageState(loaded: true));
    }
  }

  Future<void> select(AppLanguage language) async {
    if (language == state.language) return;
    emit(LanguageState(language: language, loaded: true));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, language.code);
    } catch (_) {
      // The change is already applied in memory; losing only the persistence
      // means it resets next launch, which is far better than refusing to
      // switch at all.
    }
  }
}
