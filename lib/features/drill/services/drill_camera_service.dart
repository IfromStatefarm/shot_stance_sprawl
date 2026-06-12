import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

abstract class DrillCameraControllerAdapter {
  bool get isInitialized;
  bool get isRecordingVideo;

  Future<void> initialize();
  Future<void> startVideoRecording();
  Future<String> stopVideoRecording();
  Future<void> dispose();
}

abstract class DrillCameraGateway {
  Future<bool> requestPermissions();
  Future<DrillCameraControllerAdapter?> createFrontController();
}

class RealCameraControllerAdapter implements DrillCameraControllerAdapter {
  final CameraController controller;

  RealCameraControllerAdapter(this.controller);

  @override
  bool get isInitialized => controller.value.isInitialized;

  @override
  bool get isRecordingVideo => controller.value.isRecordingVideo;

  @override
  Future<void> initialize() => controller.initialize();

  @override
  Future<void> startVideoRecording() => controller.startVideoRecording();

  @override
  Future<String> stopVideoRecording() async {
    final file = await controller.stopVideoRecording();
    return file.path;
  }

  @override
  Future<void> dispose() => controller.dispose();
}

class RealDrillCameraGateway implements DrillCameraGateway {
  @override
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    return statuses[Permission.camera] == PermissionStatus.granted &&
        statuses[Permission.microphone] == PermissionStatus.granted;
  }

  @override
  Future<DrillCameraControllerAdapter?> createFrontController() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return null;

    final front = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    return RealCameraControllerAdapter(
      CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
      ),
    );
  }
}

class DrillCameraService {
  final DrillCameraGateway _gateway;

  DrillCameraControllerAdapter? _controller;
  var _generation = 0;
  var _isStoppingVideo = false;

  DrillCameraService({DrillCameraGateway? gateway})
      : _gateway = gateway ?? RealDrillCameraGateway();

  bool get isStoppingVideo => _isStoppingVideo;

  CameraController? get cameraController {
    final controller = _controller;
    if (controller is RealCameraControllerAdapter) {
      return controller.controller;
    }
    return null;
  }

  bool get hasInitializedCamera => _controller?.isInitialized == true;

  Future<void> initialize({
    int? session,
    required int Function() currentSession,
    required void Function(bool initialized) onInitializedChanged,
  }) async {
    if (_controller?.isInitialized == true) {
      onInitializedChanged(true);
      return;
    }

    final generation = ++_generation;
    final granted = await _gateway.requestPermissions();

    if (_isStale(
      generation: generation,
      session: session,
      currentSession: currentSession,
    )) {
      return;
    }

    if (!granted) {
      onInitializedChanged(false);
      return;
    }

    DrillCameraControllerAdapter? controller;
    try {
      controller = await _gateway.createFrontController();
      if (controller == null) {
        onInitializedChanged(false);
        return;
      }

      if (_isStale(
        generation: generation,
        session: session,
        currentSession: currentSession,
      )) {
        await controller.dispose();
        return;
      }

      await controller.initialize();

      if (_isStale(
        generation: generation,
        session: session,
        currentSession: currentSession,
      )) {
        await controller.dispose();
        return;
      }

      final previousController = _controller;
      _controller = controller;
      if (previousController != null && previousController != controller) {
        await previousController.dispose();
      }
      onInitializedChanged(true);
    } catch (e) {
      await controller?.dispose();
      _controller = null;
      onInitializedChanged(false);
      debugPrint('[camera] Initialize error: $e');
    }
  }

  Future<void> startRecording({
    required void Function(bool isRecording) onRecordingChanged,
  }) async {
    final controller = _controller;
    if (controller != null && controller.isInitialized) {
      try {
        await controller.startVideoRecording();
        onRecordingChanged(true);
      } catch (e) {
        onRecordingChanged(false);
        debugPrint('[camera] Start recording error: $e');
      }
    }
  }

  Future<String?> stopAndSaveVideo({
    required void Function(bool isRecording) onRecordingChanged,
  }) async {
    if (_isStoppingVideo) return null;

    final controller = _controller;
    if (controller == null || !controller.isRecordingVideo) {
      onRecordingChanged(false);
      return null;
    }

    _isStoppingVideo = true;
    try {
      final path = await controller.stopVideoRecording();
      onRecordingChanged(false);
      return path;
    } catch (e) {
      debugPrint('[camera] Error saving video: $e');
      onRecordingChanged(false);
      return null;
    } finally {
      _isStoppingVideo = false;
    }
  }

  Future<void> waitForStopToFinish({
    Duration pollEvery = const Duration(milliseconds: 100),
    int maxAttempts = 50,
  }) async {
    var attempts = 0;
    while (_isStoppingVideo && attempts < maxAttempts) {
      await Future.delayed(pollEvery);
      attempts++;
    }
  }

  Future<void> disposeCamera({
    required void Function(bool initialized) onInitializedChanged,
  }) async {
    _generation++;
    final controller = _controller;
    _controller = null;
    onInitializedChanged(false);

    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> disposeController({
    Duration? delayBeforeDispose,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (delayBeforeDispose != null) {
      await Future.delayed(delayBeforeDispose);
    }

    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose().timeout(timeout);
      } catch (e) {
        debugPrint('[camera] Dispose error: $e');
      }
    }
  }

  bool _isStale({
    required int generation,
    required int? session,
    required int Function() currentSession,
  }) {
    return generation != _generation ||
        (session != null && session != currentSession());
  }
}
