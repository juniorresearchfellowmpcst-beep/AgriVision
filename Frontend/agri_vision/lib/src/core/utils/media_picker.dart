import 'package:file_picker/file_picker.dart';

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
  /// Returns an empty list if the user cancels the picker.
  static Future<List<MediaFile>> pickImages({bool allowMultiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      withData: true,
      type: FileType.custom,
      allowedExtensions: imageExtensions,
    );

    if (result == null) return [];

    final files = <MediaFile>[];
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue; // skip anything we couldn't read
      files.add(
        MediaFile(
          bytes: bytes,
          name: f.name,
          size: f.size,
          extension: f.extension,
          path: f.path,
          mimeType: _mimeFor(f.extension),
        ),
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
