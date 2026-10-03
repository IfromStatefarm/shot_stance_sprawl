import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shot_stance_sprawl/core/audio.dart';
import 'package:shot_stance_sprawl/features/drill/ad_libs.dart';
import 'package:shot_stance_sprawl/features/drill/application/callout_scheduler.dart';
import 'package:shot_stance_sprawl/features/drill/intervals.dart';
import 'package:shot_stance_sprawl/features/drill/providers.dart';
import 'package:shot_stance_sprawl/features/drill/services/drill_audio_session_service.dart';
import 'package:shot_stance_sprawl/features/drill/services/drill_audio_diagnostics.dart';
import 'package:shot_stance_sprawl/features/drill/services/drill_audio_service.dart';
import 'package:shot_stance_sprawl/features/drill/services/drill_camera_service.dart';
import 'package:shot_stance_sprawl/features/drill/services/video_finalization_service.dart';
import 'package:shot_stance_sprawl/features/onboarding/onboarding.dart';
import 'package:shot_stance_sprawl/features/onboarding/workout_reminder_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CalloutScheduler', () {
    test('selects enabled callouts and avoids immediate repeats', () {
      final scheduler = CalloutScheduler(random: _CyclingRandom([0, 1]));
      const shot =
          Callout(id: 'shot', nameEn: 'Shot', nameEs: 'Shot', type: 'Movement');
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
      final factory = _FakeAudioFactory();
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async {
          checks++;
          return path == 'assets/audio/callouts/callout_shot.wav';
        },
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
      );
      const callout = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );

      await service.preloadAudio([callout], const DrillConfig());
      await service.preloadAudio([callout], const DrillConfig());
      addTearDown(service.disposePlayers);

      expect(checks, 1);
      expect(factory.players, hasLength(1));
      expect(factory.players.single.sourceChanges, 1);
      expect(
        service.calloutAudioKey(callout, const DrillConfig()),
        'asset:assets/audio/callouts/callout_shot.wav',
      );
    });

    test('delayed source preparation completes before playback starts',
        () async {
      final sourceGate = Completer<void>();
      final diagnostics = <DrillAudioDiagnosticEvent>[];
      final factory = _FakeAudioFactory(
        sourcePreparationGatesByLabel: {'callout:shot': sourceGate},
      );
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async => path.endsWith('.wav'),
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
        diagnostics: diagnostics.add,
      );
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );
      addTearDown(service.disposePlayers);

      final preload = service.preloadAudio([shot], const DrillConfig());
      await _waitUntil(() => factory.labels.containsKey('callout:shot'));
      final player = factory.playerFor('callout:shot');
      await player.whenSourcePreparationStarted.timeout(
        const Duration(seconds: 1),
      );

      final playback = service.playCallout(shot, const DrillConfig());
      await Future<void>.delayed(Duration.zero);
      expect(player.playCalls, 0);

      sourceGate.complete();
      await preload;
      await playback;

      expect(player.sourceChanges, 1);
      expect(player.playCalls, 1);
      expect(
        diagnostics.map((event) => event.type),
        containsAllInOrder([
          DrillAudioDiagnosticType.preparationStarted,
          DrillAudioDiagnosticType.playbackQueued,
          DrillAudioDiagnosticType.preparationCompleted,
          DrillAudioDiagnosticType.playbackStarted,
          DrillAudioDiagnosticType.playbackCompleted,
        ]),
      );
    });

    test('plays prepared callouts without changing their source', () async {
      final factory = _FakeAudioFactory();
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async => path.endsWith('.wav'),
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
      );
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );
      const sprawl = Callout(
        id: 'sprawl',
        nameEn: 'Sprawl',
        nameEs: 'Sprawl',
        type: 'Movement',
        audioAssetAlias: 'callout_sprawl',
      );

      await service.preloadAudio([shot, sprawl], const DrillConfig());
      addTearDown(service.disposePlayers);

      expect(factory.players, hasLength(2));
      final shotPlayer = factory.playerFor('callout:shot');
      final sprawlPlayer = factory.playerFor('callout:sprawl');
      expect(shotPlayer.assetPath, 'assets/audio/callouts/callout_shot.wav');
      expect(
          sprawlPlayer.assetPath, 'assets/audio/callouts/callout_sprawl.wav');
      expect(shotPlayer.sourceChanges, 1);
      expect(sprawlPlayer.sourceChanges, 1);

      await service.playCallout(shot, const DrillConfig());
      await service.playCallout(shot, const DrillConfig());

      expect(factory.players, hasLength(2));
      expect(shotPlayer.sourceChanges, 1);
      expect(shotPlayer.seekCalls, 2);
      expect(shotPlayer.playCalls, 2);
      expect(shotPlayer.stopCalls, 0);
      expect(sprawlPlayer.sourceChanges, 1);
      expect(sprawlPlayer.playCalls, 0);
      expect(sprawlPlayer.stopCalls, 0);
    });

    test('does not load an unprepared source at playback time', () async {
      final factory = _FakeAudioFactory();
      final service = DrillAudioService(audioFactory: factory);
      const callout = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );

      await expectLater(
        service.playCallout(callout, const DrillConfig()),
        throwsA(isA<StateError>()),
      );
      expect(factory.players, isEmpty);
    });

    test('invalid bundled assets are rejected before player creation',
        () async {
      final diagnostics = <DrillAudioDiagnosticEvent>[];
      final factory = _FakeAudioFactory();
      final resolver = CalloutAudioAssetResolver(
        assetExists: (_) async => false,
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
        diagnostics: diagnostics.add,
      );
      const missing = Callout(
        id: 'missing',
        nameEn: 'Missing',
        nameEs: 'Missing',
        type: 'Movement',
        audioAssetAlias: 'callout_missing',
      );
      addTearDown(service.disposePlayers);

      await service.preloadAudio([missing], const DrillConfig());

      expect(factory.players, isEmpty);
      await expectLater(
        service.playCallout(missing, const DrillConfig()),
        throwsA(isA<StateError>()),
      );
      expect(
        diagnostics.where(
          (event) => event.type == DrillAudioDiagnosticType.assetMissing,
        ),
        hasLength(1),
      );
      expect(
        diagnostics.any(
          (event) => event.type == DrillAudioDiagnosticType.playbackFailed,
        ),
        isTrue,
      );
    });

    test('a callout preempts and stops an active ad lib', () async {
      final factory = _FakeAudioFactory(
        manualCompletionLabels: {'ad_lib_cue'},
      );
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async => path.endsWith('.wav'),
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
      );
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );

      await service.resetPlayers();
      await service.preloadAudio([shot], const DrillConfig());
      addTearDown(service.disposePlayers);

      final adLibPlayer = factory.playerFor('ad_lib_cue');
      final adLibPlayback = service.playAdLib(
        AdLibSlots.all.first,
        const DrillConfig(),
        isPro: false,
      );
      await adLibPlayer.whenPlayStarted.timeout(const Duration(seconds: 1));

      await service.playCallout(shot, const DrillConfig());
      await adLibPlayback;

      expect(adLibPlayer.stopCalls, 1);
      expect(factory.playerFor('callout:shot').playCalls, 1);
    });

    test('a long custom ad-lib cannot delay the next callout', () async {
      final directory =
          await Directory.systemTemp.createTemp('snap_go_long_ad_lib_test');
      final customAdLib =
          File('${directory.path}${Platform.pathSeparator}long_coach.m4a');
      await customAdLib.writeAsBytes([1, 2, 3, 4]);
      final diagnostics = <DrillAudioDiagnosticEvent>[];
      final factory = _FakeAudioFactory(
        manualCompletionLabels: {'ad_lib_cue'},
      );
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async => path.endsWith('.wav'),
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
        diagnostics: diagnostics.add,
      );
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );
      final config = DrillConfig(
        customAdLibAudioPaths: {'ad_lib_1': customAdLib.path},
      );
      addTearDown(() async {
        await service.disposePlayers();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      await service.resetPlayers();
      await service.preloadAudio([shot], config);
      final adLibPlayer = factory.playerFor('ad_lib_cue');
      final adLibPlayback = service.playAdLib(
        AdLibSlots.all.first,
        config,
        isPro: true,
      );
      await adLibPlayer.whenPlayStarted.timeout(const Duration(seconds: 1));

      expect(adLibPlayer.deviceFilePath, customAdLib.path);
      await service
          .playCallout(shot, config)
          .timeout(const Duration(seconds: 1));
      await adLibPlayback.timeout(const Duration(seconds: 1));

      expect(adLibPlayer.stopCalls, greaterThanOrEqualTo(1));
      expect(
        diagnostics.any(
          (event) =>
              event.type == DrillAudioDiagnosticType.playbackCancelled &&
              event.cue == 'ad lib ad_lib_1',
        ),
        isTrue,
      );
    });

    test('a whistle preempts and stops an active callout', () async {
      final factory = _FakeAudioFactory(
        manualCompletionLabels: {'callout:shot'},
      );
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async => path.endsWith('.wav'),
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
      );
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );

      await service.resetPlayers();
      await service.preloadAudio([shot], const DrillConfig());
      addTearDown(service.disposePlayers);

      final shotPlayer = factory.playerFor('callout:shot');
      final calloutPlayback = service.playCallout(shot, const DrillConfig());
      await shotPlayer.whenPlayStarted.timeout(const Duration(seconds: 1));

      final played = await service.playFirstAvailableOnCallout(
        ['assets/audio/callouts/whistle.wav'],
      );
      await calloutPlayback;

      expect(played, isTrue);
      expect(shotPlayer.stopCalls, 1);
      expect(factory.playerFor('whistle_cue').playCalls, 1);
    });

    test('rapid callouts remain serialized with only one active cue', () async {
      final factory = _FakeAudioFactory(
        manualCompletionLabels: {'callout:shot', 'callout:sprawl'},
      );
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async => path.endsWith('.wav'),
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
      );
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );
      const sprawl = Callout(
        id: 'sprawl',
        nameEn: 'Sprawl',
        nameEs: 'Sprawl',
        type: 'Movement',
        audioAssetAlias: 'callout_sprawl',
      );

      await service.preloadAudio([shot, sprawl], const DrillConfig());
      addTearDown(service.disposePlayers);
      final shotPlayer = factory.playerFor('callout:shot');
      final sprawlPlayer = factory.playerFor('callout:sprawl');

      final shotPlayback = service.playCallout(shot, const DrillConfig());
      await shotPlayer.whenPlayStarted.timeout(const Duration(seconds: 1));
      final sprawlPlayback = service.playCallout(sprawl, const DrillConfig());
      final secondShotPlayback = service.playCallout(shot, const DrillConfig());
      await Future<void>.delayed(Duration.zero);

      expect(sprawlPlayer.playCalls, 0);
      expect(shotPlayer.playCalls, 1);
      shotPlayer.completePlayback();
      await shotPlayback;
      await sprawlPlayer.whenPlayStarted.timeout(const Duration(seconds: 1));
      expect(shotPlayer.playCalls, 1);
      sprawlPlayer.completePlayback();
      await sprawlPlayback;
      await _waitUntil(() => shotPlayer.playCalls == 2);
      shotPlayer.completePlayback();
      await secondShotPlayback;

      expect(shotPlayer.playCalls, 2);
      expect(sprawlPlayer.playCalls, 1);
    });

    test('recreates a failed decoder and retries the callout once', () async {
      final diagnostics = <DrillAudioDiagnosticEvent>[];
      final factory = _FakeAudioFactory(
        playFailuresByLabel: {'callout:shot': 1},
      );
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async => path.endsWith('.wav'),
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
        diagnostics: diagnostics.add,
      );
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );

      await service.preloadAudio([shot], const DrillConfig());
      addTearDown(service.disposePlayers);
      final failedPlayer = factory.playerFor('callout:shot');

      await service.playCallout(shot, const DrillConfig());

      final recoveredPlayer = factory.playerFor('callout:shot');
      expect(factory.players, hasLength(2));
      expect(failedPlayer.playCalls, 1);
      expect(failedPlayer.disposeCalls, 1);
      expect(recoveredPlayer, isNot(same(failedPlayer)));
      expect(recoveredPlayer.sourceChanges, 1);
      expect(recoveredPlayer.playCalls, 1);
      expect(
        diagnostics.where(
          (event) => event.type == DrillAudioDiagnosticType.decoderRetry,
        ),
        hasLength(1),
      );
      expect(
        diagnostics.any(
          (event) =>
              event.type == DrillAudioDiagnosticType.playbackCompleted &&
              event.cue == 'callout shot',
        ),
        isTrue,
      );
    });

    test('does not retry a callout decoder more than once', () async {
      final factory = _FakeAudioFactory(
        playFailuresByLabel: {'callout:shot': 2},
      );
      final resolver = CalloutAudioAssetResolver(
        assetExists: (path) async => path.endsWith('.wav'),
      );
      final service = DrillAudioService(
        audioFactory: factory,
        assetResolver: resolver,
      );
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );

      await service.preloadAudio([shot], const DrillConfig());
      addTearDown(service.disposePlayers);

      await expectLater(
        service.playCallout(shot, const DrillConfig()),
        throwsA(isA<StateError>()),
      );

      expect(factory.players, hasLength(2));
      expect(factory.players, everyElement(hasPlayCalls(1)));
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

  group('DrillAudioSessionService', () {
    test('uses playback configuration when video is disabled', () {
      final configuration = DrillAudioSessionService.configurationFor(
        videoEnabled: false,
      );

      expect(
        configuration.avAudioSessionCategory,
        AVAudioSessionCategory.playback,
      );
      expect(
        configuration.avAudioSessionMode,
        AVAudioSessionMode.spokenAudio,
      );
    });

    test('uses play-and-record with speaker routing for video', () {
      final configuration = DrillAudioSessionService.configurationFor(
        videoEnabled: true,
      );

      expect(
        configuration.avAudioSessionCategory,
        AVAudioSessionCategory.playAndRecord,
      );
      expect(
        configuration.avAudioSessionMode,
        AVAudioSessionMode.videoRecording,
      );
      expect(
        configuration.avAudioSessionCategoryOptions?.contains(
          AVAudioSessionCategoryOptions.defaultToSpeaker,
        ),
        isTrue,
      );
    });

    test('serializes app-wide configuration and skips duplicates', () async {
      final configurations = <AudioSessionConfiguration>[];
      var speakerRoutes = 0;
      final service = DrillAudioSessionService(
        configure: (configuration) async {
          configurations.add(configuration);
        },
        routeToSpeaker: () async {
          speakerRoutes++;
        },
      );

      await service.configureForDrill(videoEnabled: false);
      await service.configureForDrill(videoEnabled: false);
      await service.configureForDrill(videoEnabled: true, force: true);

      expect(configurations, hasLength(2));
      expect(
        configurations.last.avAudioSessionCategory,
        AVAudioSessionCategory.playAndRecord,
      );
      expect(speakerRoutes, 1);
    });
  });

  group('DrillEngineNotifier playback lifecycle', () {
    test(
      'pause during playback invalidates the cue and resume schedules once',
      () async {
        const shot = Callout(
          id: 'shot',
          nameEn: 'Shot',
          nameEs: 'Shot',
          type: 'Movement',
          audioAssetAlias: 'callout_shot',
        );
        const config = DrillConfig(
          totalDurationSeconds: 30,
          minIntervalSeconds: 2,
          maxIntervalSeconds: 2,
          enabledCalloutIds: {'shot'},
        );
        final audioFactory = _FakeAudioFactory(
          manualCompletionLabels: {'callout:shot'},
        );
        final intervals = _FixedIntervalStrategy(1);
        var playersReadyBeforeSessionConfiguration = false;
        final audioSession = DrillAudioSessionService(
          configure: (_) async {
            playersReadyBeforeSessionConfiguration = audioFactory
                    .players.isNotEmpty &&
                audioFactory.players.every(
                  (player) =>
                      player.initializeCalls > 0 || player.sourceChanges > 0,
                );
          },
        );
        final container = ProviderContainer(
          overrides: [
            audioFactoryProvider.overrideWithValue(audioFactory),
            intervalStrategyProvider.overrideWithValue(intervals),
            drillAudioSessionProvider.overrideWithValue(audioSession),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(drillEngineProvider.notifier);

        await notifier.start(
          config: config,
          allCallouts: const [shot],
          isPro: true,
          playStartWhistle: false,
        );
        expect(playersReadyBeforeSessionConfiguration, isTrue);
        final player = audioFactory.playerFor('callout:shot');
        await player.whenPlayStarted.timeout(const Duration(seconds: 3));

        await notifier.pause();
        expect(container.read(drillEngineProvider).paused, isTrue);
        expect(player.stopCalls, greaterThanOrEqualTo(1));
        expect(container.read(drillEngineProvider).calloutsCompleted, 0);

        await Future.wait([
          notifier.resume(config: config, allCallouts: const [shot]),
          notifier.resume(config: config, allCallouts: const [shot]),
        ]);

        expect(container.read(drillEngineProvider).paused, isFalse);
        expect(intervals.calls, 1);

        await notifier.pause();
      },
    );

    test('repeated pause and resume cycles never duplicate playback', () async {
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );
      const config = DrillConfig(
        totalDurationSeconds: 30,
        minIntervalSeconds: 2,
        maxIntervalSeconds: 2,
        enabledCalloutIds: {'shot'},
      );
      final audioFactory = _FakeAudioFactory(
        manualCompletionLabels: {'callout:shot'},
      );
      final intervals = _FixedIntervalStrategy(0.02);
      final container = ProviderContainer(
        overrides: [
          audioFactoryProvider.overrideWithValue(audioFactory),
          intervalStrategyProvider.overrideWithValue(intervals),
          drillAudioSessionProvider.overrideWithValue(
            DrillAudioSessionService(configure: (_) async {}),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(drillEngineProvider.notifier);

      await notifier.start(
        config: config,
        allCallouts: const [shot],
        isPro: true,
        playStartWhistle: false,
      );
      final player = audioFactory.playerFor('callout:shot');
      await player.whenPlayStarted.timeout(const Duration(seconds: 3));

      for (var cycle = 1; cycle <= 3; cycle++) {
        await notifier.pause();
        expect(container.read(drillEngineProvider).paused, isTrue);

        await notifier.resume(config: config, allCallouts: const [shot]);
        await _waitUntil(() => player.playCalls == cycle + 1);
        expect(container.read(drillEngineProvider).paused, isFalse);
      }

      await notifier.pause();
      expect(container.read(drillEngineProvider).sessionPauseCount, 4);
      expect(player.playCalls, 4);
      expect(intervals.calls, 3);
    });

    test('finish during a callout cancels stale playback immediately',
        () async {
      SharedPreferences.setMockInitialValues({});
      const shot = Callout(
        id: 'shot',
        nameEn: 'Shot',
        nameEs: 'Shot',
        type: 'Movement',
        audioAssetAlias: 'callout_shot',
      );
      const config = DrillConfig(
        totalDurationSeconds: 30,
        minIntervalSeconds: 2,
        maxIntervalSeconds: 2,
        enabledCalloutIds: {'shot'},
      );
      final audioFactory = _FakeAudioFactory(
        manualCompletionLabels: {'callout:shot'},
      );
      final container = ProviderContainer(
        overrides: [
          audioFactoryProvider.overrideWithValue(audioFactory),
          intervalStrategyProvider.overrideWithValue(
            _FixedIntervalStrategy(1),
          ),
          drillAudioSessionProvider.overrideWithValue(
            DrillAudioSessionService(configure: (_) async {}),
          ),
          workoutReminderNotificationsProvider.overrideWithValue(
            _FakeWorkoutReminderNotifications(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(drillEngineProvider.notifier);

      await notifier.start(
        config: config,
        allCallouts: const [shot],
        isPro: true,
        playStartWhistle: false,
      );
      final player = audioFactory.playerFor('callout:shot');
      await player.whenPlayStarted.timeout(const Duration(seconds: 3));

      final finish = notifier.stop();
      await Future<void>.delayed(Duration.zero);
      expect(player.stopCalls, greaterThanOrEqualTo(1));
      expect(container.read(drillEngineProvider).running, isFalse);

      await finish.timeout(const Duration(seconds: 5));
      final state = container.read(drillEngineProvider);
      expect(state.finished, isTrue);
      expect(state.calloutsCompleted, 0);
      expect(player.playCalls, 1);
    });
  });

  group('DrillCameraService', () {
    test('moves through initialize, record, stop, and dispose states',
        () async {
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

Matcher hasPlayCalls(int count) => predicate<_FakeAudioPlayer>(
      (player) => player.playCalls == count,
      'has $count play call(s)',
    );

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed >= timeout) {
      throw TimeoutException('Condition was not met before $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
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
  final players = <_FakeAudioPlayer>[];
  final labels = <String?, _FakeAudioPlayer>{};
  final Set<String> manualCompletionLabels;
  final Map<String, int> _playFailuresByLabel;
  final Map<String, Completer<void>> sourcePreparationGatesByLabel;

  _FakeAudioFactory({
    this.manualCompletionLabels = const {},
    Map<String, int> playFailuresByLabel = const {},
    this.sourcePreparationGatesByLabel = const {},
  }) : _playFailuresByLabel = Map<String, int>.from(playFailuresByLabel);

  @override
  IAudioPlayer createPlayer({String? debugLabel}) {
    final failures = _playFailuresByLabel[debugLabel] ?? 0;
    if (debugLabel != null && failures > 0) {
      _playFailuresByLabel[debugLabel] = failures - 1;
    }
    final player = _FakeAudioPlayer(
      autoComplete: !manualCompletionLabels.contains(debugLabel),
      playFailuresRemaining: failures > 0 ? 1 : 0,
      sourcePreparationGate: sourcePreparationGatesByLabel[debugLabel],
    );
    players.add(player);
    labels[debugLabel] = player;
    return player;
  }

  _FakeAudioPlayer playerFor(String label) => labels[label]!;
}

class _FakeAudioPlayer implements IAudioPlayer {
  final _complete = StreamController<void>.broadcast();
  final Completer<void> _playStarted = Completer<void>();
  final Completer<void> _sourcePreparationStarted = Completer<void>();
  final bool autoComplete;
  final Completer<void>? sourcePreparationGate;
  int playFailuresRemaining;
  String? assetPath;
  String? deviceFilePath;
  var sourceChanges = 0;
  var initializeCalls = 0;
  var playCalls = 0;
  var seekCalls = 0;
  var stopCalls = 0;
  var disposeCalls = 0;

  _FakeAudioPlayer({
    this.autoComplete = true,
    this.playFailuresRemaining = 0,
    this.sourcePreparationGate,
  });

  Future<void> get whenPlayStarted => _playStarted.future;
  Future<void> get whenSourcePreparationStarted =>
      _sourcePreparationStarted.future;

  void completePlayback() => _complete.add(null);

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Stream<void> get onPlayerComplete => _complete.stream;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _complete.close();
  }

  @override
  Future<void> play() async {
    playCalls++;
    if (!_playStarted.isCompleted) _playStarted.complete();
    if (playFailuresRemaining > 0) {
      playFailuresRemaining--;
      throw StateError('simulated decoder failure');
    }
    if (autoComplete) completePlayback();
  }

  @override
  Future<void> seek(Duration duration) async {
    seekCalls++;
  }

  @override
  Future<void> setAsset(String assetPath) async {
    sourceChanges++;
    this.assetPath = assetPath;
    if (!_sourcePreparationStarted.isCompleted) {
      _sourcePreparationStarted.complete();
    }
    await sourcePreparationGate?.future;
  }

  @override
  Future<void> setDeviceFile(String filePath) async {
    sourceChanges++;
    deviceFilePath = filePath;
    if (!_sourcePreparationStarted.isCompleted) {
      _sourcePreparationStarted.complete();
    }
    await sourcePreparationGate?.future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
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

class _FakeWorkoutReminderNotifications extends WorkoutReminderNotifications {
  @override
  Future<void> scheduleAfterWorkoutCompletion({
    required OnboardingProfile profile,
    required DateTime completedAt,
  }) async {}
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
