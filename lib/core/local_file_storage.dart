import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

abstract final class LocalStoragePaths {
  static const recordingsFolderName = 'recordings';
  static const galleryExportsFolderName = 'gallery_exports';

  static Future<Directory> recordingsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(_join(docs.path, recordingsFolderName));
  }

  static Future<File> nextRecordingFile(String baseName) async {
    final dir = await recordingsDirectory();
    var candidate = File(_join(dir.path, baseName));
    var suffix = 2;
    while (await candidate.exists()) {
      candidate = File(
        _join(dir.path, baseName.replaceFirst('.mp4', '_$suffix.mp4')),
      );
      suffix++;
    }
    return candidate;
  }

  static Future<File> galleryExportFile(String fileName) async {
    final dir = await _galleryExportsDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(_join(dir.path, fileName));
  }

  static Future<String> timestampedDocumentAudioPath(String prefix) async {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  static Future<Directory> _galleryExportsDirectory() async {
    final tempDir = await getTemporaryDirectory();
    return Directory(_join(tempDir.path, galleryExportsFolderName));
  }

  static String _join(String parent, String child) {
    return '$parent${Platform.pathSeparator}$child';
  }
}

abstract final class LocalFileStorage {
  static bool isLocalPath(String path) {
    return path.isNotEmpty &&
        !path.startsWith('assets/') &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
  }

  static Future<bool> localFileExists(String? path) async {
    if (path == null || !isLocalPath(path)) return false;
    return File(path).exists();
  }

  static bool localFileExistsSync(String? path) {
    if (path == null || !isLocalPath(path)) return false;
    return File(path).existsSync();
  }

  static Future<void> deleteLocalFileIfExists(
    String path, {
    String? debugLabel,
  }) async {
    if (!isLocalPath(path)) return;
    await deleteFileIfExists(File(path), debugLabel: debugLabel);
  }

  static Future<void> deleteFileIfExists(
    File? file, {
    String? debugLabel,
  }) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      _debugPrint(debugLabel, e);
    }
  }

  static Future<void> deleteDirectoryIfExists(
    Directory directory, {
    bool recursive = false,
    String? debugLabel,
  }) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: recursive);
      }
    } catch (e) {
      _debugPrint(debugLabel, e);
    }
  }

  static void _debugPrint(String? debugLabel, Object error) {
    if (debugLabel == null) return;
    debugPrint('$debugLabel: $error');
  }
}
