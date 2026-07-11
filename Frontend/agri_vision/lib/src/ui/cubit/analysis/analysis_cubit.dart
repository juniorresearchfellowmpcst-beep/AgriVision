import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/core/utils/media_picker.dart';
import 'package:agri_vision/src/data/analysis/analysis_service.dart';
import 'package:agri_vision/src/domain/entity/analysis_result.dart';
import 'package:agri_vision/src/domain/entity/media_file.dart';

part 'analysis_cubit_state.dart';

/// Drives the "analyze field images" flow: pick images → configure → upload →
/// show the report + risk zones + action plan.
///
/// Follows the same lightweight pattern as [AuthCubit]: the cubit owns an
/// [AnalysisService] and emits immutable [AnalysisState] snapshots. UI is a pure
/// function of state, so it works the same on mobile, desktop and web.
class AnalysisCubit extends Cubit<AnalysisState> {
  AnalysisCubit({AnalysisService? service})
    : _service = service ?? AnalysisService(),
      super(const AnalysisState());

  final AnalysisService _service;

  /// Open the system file picker and add the chosen images to the selection.
  ///
  /// Newly picked files get a best-guess band from their filename so the
  /// dropdowns start pre-filled; the user can correct any of them.
  Future<void> pickImages() async {
    try {
      final picked = await MediaPicker.pickImages();
      if (picked.isEmpty) return; // user cancelled

      final images = [...state.images, ...picked];
      final fileBand = _autoAssign(state.fileBand, picked);
      emit(
        state.copyWith(
          status: AnalysisStatus.ready,
          images: images,
          fileBand: fileBand,
          errorMessage: '',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: AnalysisStatus.failure,
          errorMessage: 'Could not open image picker: $e',
        ),
      );
    }
  }

  /// Assign [band] to the file named [fileName], keeping the mapping 1:1
  /// (a band can only belong to one file, and vice-versa).
  void assignBand(String fileName, String band) {
    final next = Map<String, String>.from(state.fileBand)
      ..removeWhere((f, b) => b == band) // steal the band from any other file
      ..[fileName] = band;
    emit(state.copyWith(fileBand: next, errorMessage: ''));
  }

  void clearBand(String fileName) {
    final next = Map<String, String>.from(state.fileBand)..remove(fileName);
    emit(state.copyWith(fileBand: next));
  }

  /// Pick the calibration-panel photo(s) (optional, enables true reflectance).
  Future<void> pickPanelImages() async {
    final picked = await MediaPicker.pickImages();
    if (picked.isEmpty) return;
    emit(state.copyWith(panelImages: [...state.panelImages, ...picked]));
  }

  void removeImage(int index) {
    if (index < 0 || index >= state.images.length) return;
    final removed = state.images[index];
    final next = [...state.images]..removeAt(index);
    final fileBand = Map<String, String>.from(state.fileBand)
      ..remove(removed.name);
    emit(
      state.copyWith(
        images: next,
        fileBand: fileBand,
        status: next.isEmpty ? AnalysisStatus.initial : AnalysisStatus.ready,
      ),
    );
  }

  void setCalibrate(bool value) => emit(state.copyWith(calibrate: value));

  /// Upload the selected images and run the analysis.
  Future<void> analyze() async {
    if (state.images.isEmpty) {
      emit(
        state.copyWith(
          status: AnalysisStatus.failure,
          errorMessage: 'Select at least one image first.',
        ),
      );
      return;
    }

    emit(state.copyWith(status: AnalysisStatus.uploading, errorMessage: ''));
    try {
      // Send the explicit band mapping when the user assigned any bands;
      // otherwise let the backend auto-detect from filenames.
      final bandMap = state.bandMap;
      final result = await _service.analyzeImages(
        images: state.images,
        calibrate: state.calibrate,
        panelImages: state.panelImages,
        bandMap: bandMap.isNotEmpty ? bandMap : null,
      );

      if (!result.isOk) {
        emit(
          state.copyWith(
            status: AnalysisStatus.failure,
            errorMessage: result.message.isNotEmpty
                ? result.message
                : 'Analysis failed.',
          ),
        );
        return;
      }

      emit(state.copyWith(status: AnalysisStatus.success, result: result));
    } catch (e) {
      emit(
        state.copyWith(
          status: AnalysisStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Clear everything and start over.
  void reset() => emit(const AnalysisState());

  /// Best-effort band guess for newly picked files, merged into [existing].
  /// Keeps the mapping 1:1 — a band already taken is not guessed again.
  Map<String, String> _autoAssign(
    Map<String, String> existing,
    List<MediaFile> picked,
  ) {
    final next = Map<String, String>.from(existing);
    final taken = next.values.toSet();
    for (final f in picked) {
      if (next.containsKey(f.name)) continue;
      final guess = _guessBand(f.name);
      if (guess != null && !taken.contains(guess)) {
        next[f.name] = guess;
        taken.add(guess);
      }
    }
    return next;
  }

  /// Infer a band key from a filename. Order matters: red-edge before red and
  /// NIR before the rest so substrings don't shadow the more specific match.
  static String? _guessBand(String name) {
    final n = name.toLowerCase();
    if (n.contains('red_edge') ||
        n.contains('rededge') ||
        RegExp(r'(_4|b4|re)').hasMatch(n)) {
      return 'red_edge';
    }
    if (n.contains('nir') || RegExp(r'(_5|b5)').hasMatch(n)) return 'nir';
    if (n.contains('red') || RegExp(r'(_3|b3)').hasMatch(n)) return 'red';
    if (n.contains('green') || RegExp(r'(_2|b2)').hasMatch(n)) return 'green';
    if (n.contains('blue') || RegExp(r'(_1|b1)').hasMatch(n)) return 'blue';
    return null;
  }
}
