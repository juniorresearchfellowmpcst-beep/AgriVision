import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/entity/media_file.dart';

/// Thin wrapper around `file_picker` that returns the app's [MediaFile] model.
///
/// Always requests the file bytes (`withData: true`) so the result is uniform
/// across mobile / desktop / web and can be posted straight through [ApiClient]
/// as multipart, exactly like image uploads elsewhere in the app.
class MediaPicker {
  const MediaPicker._();

  /// Multispectral captures are typically TIFF, but we also accept common
  /// raster formats so the user can try the analyzer with ordinary photos.
  static const List<String> imageExtensions = [
    'tif',
    'tiff',
    'png',
    'jpg',
    'jpeg',
  ];

  /// Let the user pick one or more image files from their system.
  ///
  /// Returns an empty list if the user cancels the picker. Throws with a clear
  /// message if files were chosen but none could be read into memory.
  ///
  /// Web note: on web there is no filesystem path, so bytes are the only source
  /// of data. `withData: true` makes file_picker read the bytes for us on every
  /// platform, which is exactly what the multipart upload needs.
  static Future<List<MediaFile>> pickImages({bool allowMultiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      withData: true, // required on web; path is always null there
      type: FileType.custom,
      allowedExtensions: imageExtensions,
    );

    // Null result OR no files == the user dismissed the picker.
    if (result == null || result.files.isEmpty) return [];

    final files = <MediaFile>[];
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue; // couldn't read this one
      files.add(
        MediaFile(
          bytes: bytes,
          name: f.name,
          size: f.size,
          extension: f.extension,
          // IMPORTANT: on web `PlatformFile.path` is a getter that *throws*
          // (not just null), so it must never be accessed there. We rely on
          // bytes for the upload, so path is only useful on native platforms.
          path: kIsWeb ? null : f.path,
          mimeType: _mimeFor(f.extension),
        ),
      );
    }

    // Files were selected but none produced bytes — surface it instead of
    // silently doing nothing (mostly a web / very-large-file situation).
    if (files.isEmpty) {
      throw Exception(
        'The selected file(s) could not be read. On web, very large files may '
        'fail to load into memory — try smaller exports.',
      );
    }
    return files;
  }

  static String? _mimeFor(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return null;
    }
  }
}
