part of 'language_cubit.dart';

class LanguageState extends Equatable {
  const LanguageState({
    this.language = AppLanguage.english,
    this.loaded = false,
  });

  final AppLanguage language;

  /// False until the stored choice has been read. The splash screen waits on
  /// this so the first painted frame is already in the right language.
  final bool loaded;

  @override
  List<Object?> get props => [language, loaded];
}
