import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../services/branding_service.dart';

typedef BrandVideo = Future<String?> Function({
  required String inputVideoPath,
  required String assetLogoPath,
  required bool isPremium,
});
typedef FileReadyChecker = Future<bool> Function(String path);

class VideoFinalizationResult {
  final String? videoPath;
  final bool fileReady;

  const VideoFinalizationResult({
    required this.videoPath,
    required this.fileReady,
  });
}

class VideoFinalizationService {
  final BrandVideo _brandVideo;
  final FileReadyChecker? _fileReadyChecker;

  VideoFinalizationService({
    BrandVideo? brandVideo,
    FileReadyChecker? fileReadyChecker,
  })  : _brandVideo = brandVideo ?? BrandingService().applyBranding,
        _fileReadyChecker = fileReadyChecker;

  Future<VideoFinalizationResult> finalizeVideo({
    required String? inputVideoPath,
    required String assetLogoPath,
    required bool isPremium,
  }) async {
    if (inputVideoPath == null || inputVideoPath.isEmpty) {
      return const VideoFinalizationResult(videoPath: null, fileReady: false);
    }

    final isReady = await (_fileReadyChecker?.call(inputVideoPath) ??
        waitForFileReady(inputVideoPath));
    if (!isReady) {
      return const VideoFinalizationResult(videoPath: null, fileReady: false);
    }

    try {
      final brandedPath = await _brandVideo(
        inputVideoPath: inputVideoPath,
        assetLogoPath: assetLogoPath,
        isPremium: isPremium,
      );

      return VideoFinalizationResult(
        videoPath: brandedPath,
        fileReady: true,
      );
    } catch (e) {
      debugPrint('Video processing critical error: $e');
      return const VideoFinalizationResult(videoPath: null, fileReady: true);
    }
  }

  Future<bool> waitForFileReady(
    String path, {
    int maxAttempts = 60,
    Duration pollEvery = const Duration(milliseconds: 500),
    int requiredStableReads = 2,
  }) async {
    final file = File(path);
    var attempts = 0;
    var lastSize = -1;
    var stableReads = 0;

    while (attempts < maxAttempts) {
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0 && len == lastSize) {
          stableReads++;
        } else {
          stableReads = 0;
        }

        if (stableReads >= requiredStableReads) {
          try {
            final raf = await file.open(mode: FileMode.read);
            await raf.close();
            return true;
          } catch (e) {
            debugPrint('File still locked by camera, waiting... $e');
          }
        }
        lastSize = len;
      }
      await Future.delayed(pollEvery);
      attempts++;
    }

    debugPrint('Video file was not ready for branding after 30s: $path');
    return false;
  }
}
