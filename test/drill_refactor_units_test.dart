import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/core/audio.dart';
import 'package:shot_stance_sprawl/features/drill/application/callout_scheduler.dart';
import 'package:shot_stance_sprawl/features/drill/intervals.dart';
import 'package:shot_stance_sprawl/features/drill/models.dart';
import 'package:shot_stance_sprawl/features/drill/services/drill_audio_service.dart';
import 'package:shot_stance_sprawl/features/drill/services/drill_camera_service.dart';
import 'package:shot_stance_sprawl/features/drill/services/video_finalization_service.dart';

void main() {
  group('CalloutScheduler', () {
    test('selects enabled callouts and avoids immediate repeats', () {
      final scheduler = CalloutScheduler(random: _CyclingRandom([0, 1]));
      const shot = Callout(id: 'shot', nameEn: 'Shot', nameEs: 'Shot', type: 'Movement');
      const sprawl = Callout(
        id: 'sprawl',
        nameEn: 'Sprawl',
        nameEs: 'Sprawl',
        type: 'Movement',
      );
      const disabled = Callout(
        id: 'stance',
        nameEn: 'Stance',
        nameEs: 'Stance',
        type: 'Duration',
      );
      const config = DrillConfig(enabledCalloutIds: {'shot', 'sprawl'});

      final selected = scheduler.selectedCalloutsFor(
        config,
        [shot, sprawl, disabled],
      );
      final picked = scheduler.pickCallout(selected, lastCalloutId: 'shot');

      expect(selected, [shot, sprawl]);
      expect(picked.id, 'sprawl');
    });

    test('returns zero delay for Gable mode and delegates other intervals', () {
      final intervals = _FixedIntervalStrategy(2.75);
      final scheduler = CalloutScheduler(intervalStrategy: intervals);

      expect(
        scheduler.nextCalloutDelay(
          const DrillConfig(minIntervalSeconds: 0.5, maxIntervalSeconds: 1.5),
        ),
        0,
      );
      expect(
        scheduler.nextCalloutDelay(
          const DrillConfig(minIntervalSeconds: 2.0, maxIntervalSeconds: 4.0),
        ),
        2.75,
      );
      expect(intervals.calls, 1);
    });
  });

  group('DrillAudioService', () {
    test('caches callout audio asset resolution', () async {
      var checks = 0;
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async {
          checks++;
          return path == 'assets/audio/callouts/Shot.WAV';
        },
      );
      final service = DrillAudioService(
        audioFactory: _FakeAudioFactory(),
        assetResolver: resolver,
      );
      const callout = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'Shot',
      );

      await service.preloadAudio([callout]);
      await service.preloadAudio([callout]);

      expect(checks, 1);
      expect(
        service.calloutAudioKey(callout, const DrillConfig()),
        'asset:assets/audio/callouts/Shot.WAV',
      );
    });

    test('uses local custom audio paths when the file exists', () async {
      final dir = await Directory.systemTemp.createTemp('snap_go_audio_test');
      final file = File('${dir.path}${Platform.pathSeparator}coach.m4a');
      await file.writeAsBytes([1, 2, 3]);
      final service = DrillAudioService(audioFactory: _FakeAudioFactory());
      const callout = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
      );

      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      expect(
        service.calloutAudioKey(
          callout,
          DrillConfig(customAudioPaths: {'shot': file.path}),
        ),
        'file:${file.path}',
      );
    });
  });

  group('DrillCameraService', () {
    test('moves through initialize, record, stop, and dispose states', () async {
      final controller = _FakeCameraController();
      final service = DrillCameraService(
        gateway: _FakeCameraGateway(controller),
      );
      var initialized = false;
      var recording = false;

      await service.initialize(
        currentSession: () => 1,
        onInitializedChanged: (value) => initialized = value,
      );
      await service.startRecording(
        onRecordingChanged: (value) => recording = value,
      );
      final path = await service.stopAndSaveVideo(
        onRecordingChanged: (value) => recording = value,
      );
      await service.disposeCamera(
        onInitializedChanged: (value) => initialized = value,
      );

      expect(initialized, isFalse);
      expect(recording, isFalse);
      expect(path, 'video.mp4');
      expect(controller.initialized, isTrue);
      expect(controller.disposed, isTrue);
    });
  });

  group('VideoFinalizationService', () {
    test('brands a ready video and returns the branded path', () async {
      final service = VideoFinalizationService(
        fileReadyChecker: (_) async => true,
        brandVideo: ({
          required assetLogoPath,
          required inputVideoPath,
          required isPremium,
        }) async =>
            'branded-$inputVideoPath',
      );

      final result = await service.finalizeVideo(
        inputVideoPath: 'raw.mp4',
        assetLogoPath: 'logo.png',
        isPremium: false,
      );

      expect(result.fileReady, isTrue);
      expect(result.videoPath, 'branded-raw.mp4');
    });

    test('returns null when the video never becomes ready', () async {
      final service = VideoFinalizationService(
        fileReadyChecker: (_) async => false,
        brandVideo: ({
          required assetLogoPath,
          required inputVideoPath,
          required isPremium,
        }) async =>
            fail('Branding should not run when the file is not ready.'),
      );

      final result = await service.finalizeVideo(
        inputVideoPath: 'raw.mp4',
        assetLogoPath: 'logo.png',
        isPremium: false,
      );

      expect(result.fileReady, isFalse);
      expect(result.videoPath, isNull);
    });
  });
}

class _CyclingRandom implements math.Random {
  final List<int> values;
  var _index = 0;

  _CyclingRandom(this.values);

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) {
    final value = values[_index % values.length];
    _index++;
    return value % max;
  }
}

class _FixedIntervalStrategy implements IntervalStrategy {
  final double value;
  var calls = 0;

  _FixedIntervalStrategy(this.value);

  @override
  double next(double minSeconds, double maxSeconds) {
    calls++;
    return value;
  }
}

class _FakeAudioFactory implements AudioFactory {
  @override
  IAudioPlayer createPlayer({String? debugLabel}) => _FakeAudioPlayer();
}

class _FakeAudioPlayer implements IAudioPlayer {
  final _complete = StreamController<void>.broadcast();

  @override
  Stream<void> get onPlayerComplete => _complete.stream;

  @override
  Future<void> dispose() async {
    await _complete.close();
  }

  @override
  Future<void> play() async {
    _complete.add(null);
  }

  @override
  Future<void> seek(Duration duration) async {}

  @override
  Future<void> setAsset(String assetPath) async {}

  @override
  Future<void> setDeviceFile(String filePath) async {}

  @override
  Future<void> stop() async {}
}

class _FakeCameraGateway implements DrillCameraGateway {
  final _FakeCameraController controller;

  _FakeCameraGateway(this.controller);

  @override
  Future<DrillCameraControllerAdapter?> createFrontController() async {
    return controller;
  }

  @override
  Future<bool> requestPermissions() async => true;
}

class _FakeCameraController implements DrillCameraControllerAdapter {
  var initialized = false;
  var recording = false;
  var disposed = false;

  @override
  bool get isInitialized => initialized;

  @override
  bool get isRecordingVideo => recording;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> startVideoRecording() async {
    recording = true;
  }

  @override
  Future<String> stopVideoRecording() async {
    recording = false;
    return 'video.mp4';
  }
}
