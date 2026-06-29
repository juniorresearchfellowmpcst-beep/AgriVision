import 'dart:convert';
import 'dart:typed_data';

class MediaFile {
  final Uint8List bytes;
  final String name;
  final int size;
  final String? extension;
  final String? path;
  final String? mimeType;

  MediaFile({
    required this.bytes,
    required this.name,
    required this.size,
    this.extension,
    this.path,
    this.mimeType,
  });

  /// Convert object to JSON-compatible Map
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'size': size,
      'extension': extension,
      'path': path,
      'mimeType': mimeType,
      'bytes': base64Encode(bytes),
    };
  }

  /// Recreate MediaFile from JSON Map
  factory MediaFile.fromJson(Map<String, dynamic> json) {
    return MediaFile(
      name: json['name'] as String,
      size: json['size'] as int,
      extension: json['extension'] as String?,
      path: json['path'] as String?,
      mimeType: json['mimeType'] as String?,
      bytes: json['bytes'] != null
          ? base64Decode(json['bytes'] as String)
          : Uint8List.fromList([]),
    );
  }

  bool get isImage {
    return mimeType != null && mimeType!.startsWith('image/');
  }

  bool get isVideo {
    return mimeType != null && mimeType!.startsWith('video/');
  }
}
