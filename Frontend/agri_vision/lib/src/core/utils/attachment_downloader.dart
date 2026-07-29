import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Saves bytes the backend produced (an exported field report, for now) to
/// wherever the user keeps their files.
///
/// Built on [FilePicker.saveFile] rather than a storage plugin so no new
/// dependency or platform permission is needed: the OS's own save dialog picks
/// the destination, which also means we never write somewhere the user didn't
/// choose. On web the browser downloads the file and there is no path to
/// return, so [DownloadOutcome.savedToBrowser] reports that case distinctly
/// instead of looking like a cancellation.
class AttachmentDownloader {
  AttachmentDownloader._();

  /// Present the save dialog for [bytes] under [fileName].
  static Future<DownloadOutcome> save({
    required String fileName,
    required Uint8List bytes,
    String dialogTitle = 'Save file',
  }) async {
    if (bytes.isEmpty) {
      return const DownloadOutcome.failed('The file came back empty.');
    }

    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: bytes,
        // Constraining to the actual extension makes the OS suggest the right
        // app to open it with afterwards.
        type: FileType.custom,
        allowedExtensions: [_extensionOf(fileName)],
      );

      if (kIsWeb) {
        // The browser has already downloaded it; saveFile returns no path.
        return DownloadOutcome.savedToBrowser(fileName);
      }
      if (path == null || path.isEmpty) {
        return const DownloadOutcome.cancelled();
      }
      return DownloadOutcome.saved(path);
    } catch (e) {
      return DownloadOutcome.failed(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'bin';
    return fileName.substring(dot + 1).toLowerCase();
  }
}

/// What happened to a save attempt — distinct cases so the UI can say
/// something true rather than a generic "done".
class DownloadOutcome {
  const DownloadOutcome._(this.status, {this.path, this.error});

  const DownloadOutcome.cancelled() : this._(DownloadStatus.cancelled);
  const DownloadOutcome.failed(String message)
    : this._(DownloadStatus.failed, error: message);
  const DownloadOutcome.saved(String path)
    : this._(DownloadStatus.saved, path: path);
  const DownloadOutcome.savedToBrowser(String fileName)
    : this._(DownloadStatus.savedToBrowser, path: fileName);

  final DownloadStatus status;

  /// Where it landed — a full path on desktop/mobile, the file name on web.
  final String? path;

  final String? error;

  bool get isSaved =>
      status == DownloadStatus.saved || status == DownloadStatus.savedToBrowser;

  /// A message the UI can show verbatim.
  String get message => switch (status) {
    DownloadStatus.saved => 'Saved to $path',
    DownloadStatus.savedToBrowser => 'Downloaded $path',
    DownloadStatus.cancelled => 'Save cancelled.',
    DownloadStatus.failed => 'Could not save the file: ${error ?? 'unknown error'}',
  };
}

enum DownloadStatus { saved, savedToBrowser, cancelled, failed }
