import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/core/l10n/app_language.dart';
import 'package:agri_vision/src/data/advisor/advisor_service.dart';
import 'package:agri_vision/src/domain/entity/advisor_entity.dart';
import 'package:agri_vision/src/domain/entity/media_file.dart';

part 'advisor_cubit_state.dart';

/// Drives the "More information" conversation.
///
/// Created per screen rather than app-scoped, and that is the point: one
/// conversation is about one scan. Carrying it across to a different field
/// would let the advisor answer about the wrong crop, which is a worse failure
/// than making the farmer ask again.
class AdvisorCubit extends Cubit<AdvisorState> {
  AdvisorCubit({AdvisorService? service})
    : _service = service ?? AdvisorService(),
      super(const AdvisorState());

  final AdvisorService _service;

  /// Point the conversation at one scan.
  ///
  /// [context] is the app's own diagnosis, sent with every question so the
  /// advisor builds on the CNN's answer rather than silently replacing it.
  /// [image] is a photo the phone holds; the ids name one the server already
  /// has, so nothing is re-uploaded over a field connection.
  Future<void> open({
    Map<String, dynamic>? context,
    MediaFile? image,
    int? frameId,
    int? scanId,
    int? diseaseScanId,
    int? runId,
    String? subject,
    AppLanguage language = AppLanguage.english,
  }) async {
    emit(
      state.copyWith(
        status: AdvisorStatus.loading,
        context: context,
        image: image,
        frameId: frameId,
        scanId: scanId,
        diseaseScanId: diseaseScanId,
        runId: runId,
        subject: subject,
        language: language,
      ),
    );

    final availability = await _service.availability();
    if (isClosed) return;

    if (!availability.available) {
      emit(
        state.copyWith(
          status: AdvisorStatus.unavailable,
          availability: availability,
        ),
      );
      return;
    }

    // Starter questions, so the chat does not open on a blank box in the sun.
    final suggestions = await _service.suggestions(context, language: language);
    if (isClosed) return;

    emit(
      state.copyWith(
        status: AdvisorStatus.ready,
        availability: availability,
        suggestions: suggestions,
      ),
    );
  }

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || state.isAsking) return;

    // The photo rides on the first question only. After that the model has
    // already seen it, and re-sending it every turn would make each follow-up
    // as slow and expensive as the first.
    final sendImage = !state.imageSent;

    final history = List<AdvisorMessage>.from(state.messages);
    final asked = AdvisorMessage(
      role: 'user',
      text: trimmed,
      hasImage: sendImage && state.image != null,
    );
    final pending = AdvisorMessage(role: 'model', text: '', pending: true);

    emit(
      state.copyWith(
        status: AdvisorStatus.asking,
        messages: [...history, asked, pending],
        // Once a question has been asked, the starter chips have done their
        // job and taking the space back matters more than keeping them.
        suggestions: const [],
      ),
    );

    try {
      final answer = await _service.ask(
        question: trimmed,
        image: sendImage ? state.image : null,
        context: state.context,
        history: history,
        frameId: sendImage ? state.frameId : null,
        scanId: state.scanId,
        diseaseScanId: state.diseaseScanId,
        runId: state.runId,
        language: state.language,
      );
      if (isClosed) return;

      emit(
        state.copyWith(
          status: AdvisorStatus.ready,
          imageSent: state.imageSent || sendImage,
          messages: [
            ...history,
            asked,
            AdvisorMessage(role: 'model', text: answer),
          ],
        ),
      );
    } catch (e) {
      if (isClosed) return;
      // The failed turn stays on screen carrying its reason. Dropping it would
      // leave the farmer looking at their own question with no explanation.
      emit(
        state.copyWith(
          status: AdvisorStatus.ready,
          messages: [
            ...history,
            asked,
            AdvisorMessage(
              role: 'model',
              text: '',
              error: e.toString().replaceFirst('Exception: ', ''),
            ),
          ],
        ),
      );
    }
  }

  /// Retry the last question after a failure.
  Future<void> retryLast() async {
    final messages = state.messages;
    if (messages.isEmpty) return;
    final lastUser = messages.lastWhere(
      (message) => message.isUser,
      orElse: () => AdvisorMessage(role: 'user', text: ''),
    );
    if (lastUser.text.isEmpty) return;

    // Drop the failed answer *and* the question, so ask() re-adds both rather
    // than stacking a duplicate under the original.
    final trimmed = List<AdvisorMessage>.from(messages);
    while (trimmed.isNotEmpty && !(trimmed.last.isUser)) {
      trimmed.removeLast();
    }
    if (trimmed.isNotEmpty) trimmed.removeLast();

    emit(state.copyWith(messages: trimmed));
    await ask(lastUser.text);
  }

  void clear() => emit(
    state.copyWith(messages: const [], status: AdvisorStatus.ready),
  );
}
