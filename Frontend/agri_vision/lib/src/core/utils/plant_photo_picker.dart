import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../../domain/entity/media_file.dart';

/// Thin wrapper around `image_picker` for the plant-disease scanner.
///
/// Unlike [MediaPicker] (which uses `file_picker` for multi-file band uploads),
/// this returns a *single* photo taken with the **camera** or chosen from the
/// **gallery**, as the app's [MediaFile] model — so it posts straight through
/// as multipart just like every other image upload in the app.
class PlantPhotoPicker {
  const PlantPhotoPicker._();

  static final ImagePicker _picker = ImagePicker();

  /// Take a photo with the device camera. Returns `null` if the user cancels.
  static Future<MediaFile?> capture() =>
      _pick(ImageSource.camera);

  /// Pick an existing photo from the gallery. Returns `null` if cancelled.
  static Future<MediaFile?> fromGallery() =>
      _pick(ImageSource.gallery);

  static Future<MediaFile?> _pick(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      // Downscale on-device: disease screening only needs a clear leaf, and a
      // smaller image uploads far faster over a phone connection.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) return null; // user cancelled

    final bytes = await picked.readAsBytes();
    return MediaFile(
      bytes: bytes,
      name: picked.name.isNotEmpty ? picked.name : 'leaf.jpg',
      size: bytes.length,
      extension: _extensionOf(picked.name),
      // On web there is no filesystem path; rely on bytes for the upload.
      path: kIsWeb ? null : picked.path,
      mimeType: picked.mimeType ?? _mimeFor(_extensionOf(picked.name)),
    );
  }

  static String? _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toLowerCase();
  }

  static String? _mimeFor(String? extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
