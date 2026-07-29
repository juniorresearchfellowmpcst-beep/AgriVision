import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/credentials/credential_service.dart';
import 'package:agri_vision/src/domain/entity/profile_entity.dart';

part 'credentials_cubit_state.dart';

/// The pilot's licences, certificates and clearances (Profile screen).
///
/// A fresh account comes back with the required paperwork listed but blank —
/// that is what an unfinished profile honestly looks like, and the screen
/// prompts the operator to fill each row in. Expiry status is whatever the
/// server says; the app never recomputes it, so a licence that lapses
/// overnight is red the next time the screen loads.
class CredentialsCubit extends Cubit<CredentialsState> {
  CredentialsCubit({CredentialService? service})
    : _service = service ?? CredentialService(),
      super(const CredentialsState());

  final CredentialService _service;

  Future<void> load({bool refresh = false}) async {
    if (state.status == CredentialsStatus.loading) return;
    if (state.status == CredentialsStatus.success && !refresh) return;

    emit(state.copyWith(status: CredentialsStatus.loading, errorMessage: ''));
    try {
      final (credentials, expiring, expired) =
          await _service.fetchCredentials();
      emit(
        state.copyWith(
          status: CredentialsStatus.success,
          credentials: credentials,
          expiringCount: expiring,
          expiredCount: expired,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: CredentialsStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Fill in or correct one credential. Throws with a readable message so the
  /// edit sheet can show it without closing.
  Future<void> update({
    required int id,
    String? identifier,
    String? issuer,
    DateTime? expiresOn,
    bool clearExpiry = false,
  }) async {
    await _service.updateCredential(
      id: id,
      identifier: identifier,
      issuer: issuer,
      expiresOn: expiresOn,
      clearExpiry: clearExpiry,
    );
    await load(refresh: true);
  }

  Future<void> add({
    required String label,
    String kind = 'other',
    String? identifier,
    DateTime? expiresOn,
  }) async {
    await _service.addCredential(
      label: label,
      kind: kind,
      identifier: identifier,
      expiresOn: expiresOn,
    );
    await load(refresh: true);
  }

  Future<void> remove(int id) async {
    await _service.deleteCredential(id);
    await load(refresh: true);
  }
}
