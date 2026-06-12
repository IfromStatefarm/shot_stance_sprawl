import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio.dart';
import '../../badges/badge_engine.dart';
import '../../badges/badge_models.dart';
import '../../badges/badge_progress_provider.dart';
import '../../onboarding/onboarding.dart';
import '../../onboarding/workout_reminder_notifications.dart';
import '../ad_libs.dart';
import '../intervals.dart';
import '../models.dart';
import '../recording_policy.dart';
import '../services/drill_audio_service.dart';
import '../services/drill_camera_service.dart';
import '../training_progress_provider.dart';
import 'callout_scheduler.dart';
import 'drill_session_controller.dart';
import 'drill_timer_controller.dart';

final audioFactoryProvider = Provider<AudioFactory>((_) => RealAudioFactory());
final intervalStrategyProvider =
    Provider<IntervalStrategy>((_) => UniformIntervalStrategy());

const Object _drillStateUnset = Object();

class DrillState {
  final bool running;
  final bool paused;
  final bool finished;
  final Duration elapsed;
  final Duration total;
  final Callout? lastCallout;
  final Duration? holdRemaining;
  final bool cameraInitialized;
  final bool isRecording;
  final int calloutsCompleted;
  final Map<String, int> sessionCalloutCounts;
  final int sessionStanceSeconds;
  final Map<String, int> sessionTimedSecondsByCallout;
  final Map<String, int> sessionFullMinuteCallouts;
  final int sessionPauseCount;
  final bool isPro;
  final String? videoPath;

  int get elapsedSeconds => elapsed.inSeconds;
  int get totalSeconds => total.inSeconds;

  DrillState({
    this.running = false,
    this.paused = false,
    this.finished = false,
    this.elapsed = Duration.zero,
    this.total = Duration.zero,
    this.lastCallout,
    this.holdRemaining,
    this.cameraInitialized = false,
    this.isRecording = false,
    this.calloutsCompleted = 0,
    this.sessionCalloutCounts = const {},
    this.sessionStanceSeconds = 0,
    this.sessionTimedSecondsByCallout = const {},
    this.sessionFullMinuteCallouts = const {},
    this.sessionPauseCount = 0,
    this.isPro = false,
    this.videoPath,
  });

  DrillState copyWith({
    bool? running,
    bool? paused,
    bool? finished,
    Duration? elapsed,
    Duration? total,
    Object? lastCallout = _drillStateUnset,
    Object? holdRemaining = _drillStateUnset,
    bool? cameraInitialized,
    bool? isRecording,
    int? calloutsCompleted,
    Map<String, int>? sessionCalloutCounts,
    int? sessionStanceSeconds,
    Map<String, int>? sessionTimedSecondsByCallout,
    Map<String, int>? sessionFullMinuteCallouts,
    int? sessionPauseCount,
    bool? isPro,
    Object? videoPath = _drillStateUnset,
  }) {
    return DrillState(
      running: running ?? this.running,
      paused: paused ?? this.paused,
      finished: finished ?? this.finished,
      elapsed: elapsed ?? this.elapsed,
      total: total ?? this.total,
      lastCallout: identical(lastCallout, _drillStateUnset)
          ? this.lastCallout
          : lastCallout as Callout?,
      holdRemaining: identical(holdRemaining, _drillStateUnset)
          ? this.holdRemaining
          : holdRemaining as Duration?,
      cameraInitialized: cameraInitialized ?? this.cameraInitialized,
      isRecording: isRecording ?? this.isRecording,
      calloutsCompleted: calloutsCompleted ?? this.calloutsCompleted,
      sessionCalloutCounts: sessionCalloutCounts ?? this.sessionCalloutCounts,
      sessionStanceSeconds: sessionStanceSeconds ?? this.sessionStanceSeconds,
      sessionTimedSecondsByCallout:
          sessionTimedSecondsByCallout ?? this.sessionTimedSecondsByCallout,
      sessionFullMinuteCallouts:
          sessionFullMinuteCallouts ?? this.sessionFullMinuteCallouts,
      sessionPauseCount: sessionPauseCount ?? this.sessionPauseCount,
      isPro: isPro ?? this.isPro,
      videoPath: identical(videoPath, _drillStateUnset)
          ? this.videoPath
          : videoPath as String?,
    );
  }

  static DrillState idle(Duration total) => DrillState(
      running: false, paused: false, elapsed: Duration.zero, total: total);
}

class DrillEngineNotifier extends Notifier<DrillState>
    with WidgetsBindingObserver {
  static const Duration _firstCalloutDelay = Duration(milliseconds: 1500);

  late final DrillSessionController _sessions;
  late final DrillTimerController _timers;
  late final CalloutScheduler _scheduler;
  late final DrillAudioService _audioService;
  late final DrillCameraService _cameraService;

  CameraController? get cameraController => _cameraService.cameraController;

  String? _lastCalloutId;
  String? _preparedStartKey;
  Callout? _nextCalloutToPlay;
  DrillConfig? _activeConfig;
  List<Callout> _activeAllCallouts = const [];

  @override
  DrillState build() {
    _sessions = DrillSessionController();
    _timers = DrillTimerController();
    _scheduler = CalloutScheduler(
      intervalStrategy: ref.read(intervalStrategyProvider),
    );
    _audioService = DrillAudioService(
      audioFactory: ref.read(audioFactoryProvider),
    );
    _cameraService = DrillCameraService();

    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _disposeInternal();
    });
    return DrillState.idle(const Duration(minutes: 5));
  }

  // Handle Memory Leaks if app is backgrounded
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (this.state.running && !this.state.finished) {
        stop(); // Safely shut down camera and save
      }
    }
  }

  Future<void> preloadCamera() async {
    await _cameraService.initialize(
      session: null,
      currentSession: () => _sessions.currentSession,
      onInitializedChanged: (initialized) {
        state = state.copyWith(cameraInitialized: initialized);
      },
    );
  }

  Future<void> disposeCamera() async {
    await _cameraService.disposeCamera(
      onInitializedChanged: (initialized) {
        state = state.copyWith(cameraInitialized: initialized);
      },
    );
  }

  Future<void> warmUpForStart({
    required DrillConfig config,
    required List<Callout> allCallouts,
    required bool isPro,
  }) async {
    if (_sessions.isStarting || state.running) return;

    final effectiveConfig = RecordingPolicy.effectiveConfig(
      config: config,
      isPro: isPro,
    );
    final preparationKey = _scheduler.preparationKey(
      config: effectiveConfig,
      allCallouts: allCallouts,
      isPro: isPro,
    );

    if (_preparedStartKey == preparationKey) {
      return;
    }

    await _audioService.resetPlayers();
    _lastCalloutId = null;
    _nextCalloutToPlay = null;

    final bool alreadyReady = _cameraService.hasInitializedCamera;
    if (effectiveConfig.videoEnabled && !alreadyReady) {
      await _cameraService.initialize(
        session: null,
        currentSession: () => _sessions.currentSession,
        onInitializedChanged: (initialized) {
          state = state.copyWith(cameraInitialized: initialized);
        },
      );
    }

    final selected = _scheduler.selectedCalloutsFor(
      effectiveConfig,
      allCallouts,
    );
    await _audioService.preloadAudio(selected);
    if (selected.isNotEmpty) {
      _nextCalloutToPlay = _scheduler.pickCallout(
        selected,
        lastCalloutId: _lastCalloutId,
      );
      await _audioService.prepareCuePlayerFor(
        _nextCalloutToPlay!,
        effectiveConfig,
      );
    }

    _preparedStartKey = preparationKey;
  }

  Future<void> start({
    required DrillConfig config,
    required List<Callout> allCallouts,
    required bool isPro,
    bool playStartWhistle = true,
  }) async {
    if (!_sessions.beginStartGuard()) return;

    try {
      if (_sessions.isGlobalFinishing) return;

      final thisSession = _sessions.startNewSession();
      final effectiveConfig = RecordingPolicy.effectiveConfig(
        config: config,
        isPro: isPro,
      );
      final preparationKey = _scheduler.preparationKey(
        config: effectiveConfig,
        allCallouts: allCallouts,
        isPro: isPro,
      );
      final usePreparedStart = _preparedStartKey == preparationKey;
      final selected = _scheduler.selectedCalloutsFor(
        effectiveConfig,
        allCallouts,
      );
      _activeConfig = effectiveConfig;
      _activeAllCallouts = List<Callout>.unmodifiable(allCallouts);

      _timers.cancel();

      if (!usePreparedStart) {
        await _audioService.resetPlayers();
        _nextCalloutToPlay = null;
      }

      _lastCalloutId = null;

      final bool alreadyReady = _cameraService.hasInitializedCamera;

      state = state.copyWith(
        running: true,
        paused: false,
        finished: false,
        elapsed: Duration.zero,
        total: Duration(seconds: effectiveConfig.totalDurationSeconds),
        isPro: isPro,
        videoPath: null,
        lastCallout: null,
        holdRemaining: null,
        calloutsCompleted: 0,
        sessionCalloutCounts: const {},
        sessionStanceSeconds: 0,
        sessionTimedSecondsByCallout: const {},
        sessionFullMinuteCallouts: const {},
        sessionPauseCount: 0,
        cameraInitialized: alreadyReady,
        isRecording: false,
      );

      if (effectiveConfig.videoEnabled && !alreadyReady) {
        await _cameraService.initialize(
          session: thisSession,
          currentSession: () => _sessions.currentSession,
          onInitializedChanged: (initialized) {
            state = state.copyWith(cameraInitialized: initialized);
          },
        );
        if (!_sessions.isCurrent(thisSession) || state.finished) return;
      }

      if (!usePreparedStart) {
        await _audioService.preloadAudio(selected);
      }
      if (selected.isNotEmpty && _nextCalloutToPlay == null) {
        _nextCalloutToPlay = _scheduler.pickCallout(
          selected,
          lastCalloutId: _lastCalloutId,
        );
      }
      if (selected.isNotEmpty) {
        await _audioService.prepareCuePlayerFor(
          _nextCalloutToPlay!,
          effectiveConfig,
        );
      }
      if (!_sessions.isCurrent(thisSession) || state.finished) return;
      _preparedStartKey = null;

      if (playStartWhistle) {
        await _audioService.playFirstAvailableOnCallout([
          'assets/audio/callouts/whistle_start.wav',
          'assets/audio/callouts/whistle_start.mp3',
        ],
            shouldAbort: () =>
                !_sessions.isCurrent(thisSession) || state.finished);
        await Future.delayed(const Duration(milliseconds: 1600));
      }

      if (!_sessions.isCurrent(thisSession) || state.finished) return;

      if (effectiveConfig.videoEnabled && state.cameraInitialized) {
        await _cameraService.startRecording(
          onRecordingChanged: (isRecording) {
            state = state.copyWith(isRecording: isRecording);
          },
        );
      }

      _timers.resetAndStart();
      _timers.startTicker(
        session: thisSession,
        currentSession: () => _sessions.currentSession,
        isFinishing: () => _sessions.isFinishing,
        total: state.total,
        onTick: (elapsed) {
          state = state.copyWith(running: true, elapsed: elapsed);
        },
        onComplete: () {
          if (!_cameraService.isStoppingVideo) {
            unawaited(_finish(playEndWhistle: true, session: thisSession));
          }
        },
      );

      _timers.scheduleNext(_firstCalloutDelay, () {
        if (_sessions.isCurrent(thisSession) && !state.finished) {
          _fire(selected, effectiveConfig, thisSession);
        }
      });
    } catch (e) {
      debugPrint('[drill] CRITICAL START ERROR: $e');
    } finally {
      _sessions.endStartGuard();
    }
  }

  void pause() {
    if (state.finished || state.paused) return;
    _timers.cancel(keepTicker: true);
    _timers.stop();
    state = state.copyWith(
      paused: true,
      sessionPauseCount: state.sessionPauseCount + 1,
    );
  }

  void resume(
      {required DrillConfig config, required List<Callout> allCallouts}) {
    if (state.finished || !state.paused) return;
    _timers.start();
    final selected = _scheduler.selectedCalloutsFor(config, allCallouts);

    _scheduleNext(
      _scheduler.nextCalloutDelay(config),
      config,
      selected,
      _sessions.currentSession,
    );
    state = state.copyWith(paused: false);
  }

  Future<void> stop() async {
    await _finish(playEndWhistle: false);
  }

  Future<void> _fire(
      List<Callout> selected, DrillConfig cfg, int session) async {
    if (!_sessions.isCurrent(session) || state.finished || selected.isEmpty) {
      return;
    }
    _timers.cancelAdLib();

    final pending = _nextCalloutToPlay;
    final next =
        pending != null && selected.any((callout) => callout.id == pending.id)
            ? pending
            : _scheduler.pickCallout(
                selected,
                lastCalloutId: _lastCalloutId,
              );
    _nextCalloutToPlay = null;
    _lastCalloutId = next.id;

    unawaited(HapticFeedback.lightImpact());
    state = state.copyWith(lastCallout: next, holdRemaining: null);

    try {
      await _audioService.playCallout(
        next,
        cfg,
        shouldAbort: () => !_sessions.isCurrent(session) || state.finished,
      );
    } catch (_) {
      unawaited(HapticFeedback.mediumImpact());
    }

    if (!_sessions.isCurrent(session) || state.finished) return;
    final newCount = state.calloutsCompleted + 1;

    final overrideDuration = cfg.calloutOverrideDurations[next.id];
    final effectiveDuration = overrideDuration ?? next.defaultDurationSeconds;
    final nextSessionCalloutCounts =
        Map<String, int>.from(state.sessionCalloutCounts);
    nextSessionCalloutCounts[next.id] =
        (nextSessionCalloutCounts[next.id] ?? 0) + 1;
    final nextSessionStanceSeconds = state.sessionStanceSeconds +
        (next.id == 'stance' ? effectiveDuration : 0);
    final nextSessionTimedSecondsByCallout =
        Map<String, int>.from(state.sessionTimedSecondsByCallout);
    final nextSessionFullMinuteCallouts =
        Map<String, int>.from(state.sessionFullMinuteCallouts);
    if (next.type == 'Duration' && effectiveDuration > 0) {
      nextSessionTimedSecondsByCallout[next.id] =
          (nextSessionTimedSecondsByCallout[next.id] ?? 0) + effectiveDuration;
      if (effectiveDuration >= 60) {
        nextSessionFullMinuteCallouts[next.id] =
            (nextSessionFullMinuteCallouts[next.id] ?? 0) + 1;
      }
    }

    final delay = _scheduler.nextCalloutDelay(cfg);

    if (next.type == 'Duration' && effectiveDuration > 0) {
      final hold = Duration(seconds: effectiveDuration);

      state = state.copyWith(
        holdRemaining: hold,
        calloutsCompleted: newCount,
        sessionCalloutCounts: nextSessionCalloutCounts,
        sessionStanceSeconds: nextSessionStanceSeconds,
        sessionTimedSecondsByCallout: nextSessionTimedSecondsByCallout,
        sessionFullMinuteCallouts: nextSessionFullMinuteCallouts,
      );

      _scheduleAdLibForHold(hold, cfg, session);

      _timers.scheduleHold(hold, () {
        if (_sessions.isCurrent(session) && !state.finished) {
          state = state.copyWith(holdRemaining: null);
          _scheduleNext(delay, cfg, selected, session);
        }
      });
    } else {
      state = state.copyWith(
        holdRemaining: null,
        calloutsCompleted: newCount,
        sessionCalloutCounts: nextSessionCalloutCounts,
        sessionStanceSeconds: nextSessionStanceSeconds,
        sessionTimedSecondsByCallout: nextSessionTimedSecondsByCallout,
        sessionFullMinuteCallouts: nextSessionFullMinuteCallouts,
      );
      _timers.cancelAdLib();
      _scheduleNext(delay, cfg, selected, session);
    }
  }

  void _scheduleNext(double delaySeconds, DrillConfig cfg,
      List<Callout> selected, int session) {
    if (selected.isEmpty) return;

    _nextCalloutToPlay = _scheduler.pickCallout(
      selected,
      lastCalloutId: _lastCalloutId,
    );
    unawaited(_audioService.prepareCuePlayerFor(_nextCalloutToPlay!, cfg));

    _timers.scheduleNext(
      Duration(milliseconds: (delaySeconds * 1000).round()),
      () {
        if (_sessions.isCurrent(session) && !state.finished) {
          _fire(selected, cfg, session);
        }
      },
    );
  }

  Future<void> _finish({bool playEndWhistle = true, int? session}) async {
    if (session != null && !_sessions.isCurrent(session)) return;
    if (state.finished) return;
    if (!_sessions.beginFinish(session: session)) return;

    try {
      _timers.cancel();
      _timers.stop();

      //  Synchronize Stop Lock
      // If the ticker already triggered _stopAndSaveVideo (due to the 60s limit),
      // we must wait for it to finish rather than skipping it.
      if (_cameraService.isStoppingVideo) {
        await _cameraService.waitForStopToFinish();
      } else if (state.isRecording) {
        try {
          final videoPath = await _cameraService.stopAndSaveVideo(
            onRecordingChanged: (isRecording) {
              state = state.copyWith(isRecording: isRecording);
            },
          ).timeout(const Duration(seconds: 5));
          if (videoPath != null) {
            state = state.copyWith(videoPath: videoPath);
          }
        } on TimeoutException catch (e) {
          debugPrint('[camera] Timed out saving video: $e');
          state = state.copyWith(isRecording: false);
        } catch (e) {
          debugPrint('[camera] Error while stopping video: $e');
          state = state.copyWith(isRecording: false);
        }
      }

      state = state.copyWith(
        cameraInitialized: false,
        running: false,
        paused: false,
        isRecording: false,
      );

      final completedAt = DateTime.now();
      final config = _activeConfig;
      final allCallouts = _activeAllCallouts;
      final usedCustomCallouts = config == null
          ? false
          : allCallouts.any(
              (callout) =>
                  callout.isCustom &&
                  config.enabledCalloutIds.contains(callout.id),
            );

      unawaited(
        ref.read(trainingProgressProvider.notifier).addSession(
              callouts: state.sessionCalloutCounts,
              stanceSeconds: state.sessionStanceSeconds,
              at: completedAt,
            ),
      );
      await ref.read(badgeProgressProvider.notifier).recordWorkout(
            WorkoutBadgeInput(
              completedAt: completedAt,
              duration: state.elapsed,
              calloutCounts: state.sessionCalloutCounts,
              timedSecondsByCallout: state.sessionTimedSecondsByCallout,
              fullMinuteCallouts: state.sessionFullMinuteCallouts,
              enabledCalloutIds: config?.enabledCalloutIds ?? const {},
              difficultyScore: config == null
                  ? 3
                  : BadgeEngine.difficultyScoreFor(
                      minIntervalSeconds: config.minIntervalSeconds,
                      maxIntervalSeconds: config.maxIntervalSeconds,
                    ),
              hadPause: state.sessionPauseCount > 0,
              usedCustomCallouts: usedCustomCallouts,
              usedRecording: config?.videoEnabled ?? false,
              isPro: state.isPro,
              workoutPresetId: config?.activeWorkoutPresetId,
              seasonTargetDate:
                  ref.read(badgeProgressProvider).stats.seasonTargetDate,
            ),
          );
      final reminderProfile = await ref
          .read(onboardingProvider.notifier)
          .recordWorkoutCompleted(completedAt);
      unawaited(
        ref
            .read(workoutReminderNotificationsProvider)
            .scheduleAfterWorkoutCompletion(
              profile: reminderProfile,
              completedAt: completedAt,
            ),
      );

      // FIX: Increase Disposal Delay
      // Increase delay drastically to give the native Android MediaRecorder
      // time to write the MP4 "moov" atom metadata to disk before destruction.
      await _cameraService.disposeController(
        delayBeforeDispose: const Duration(milliseconds: 1500),
      );

      state = state.copyWith(
        finished: true,
        holdRemaining: null,
        cameraInitialized: false,
        isRecording: false,
      );

      await _audioService.stopCues();

      if (playEndWhistle) {
        await _audioService.playFirstAvailableOnCallout([
          'assets/audio/callouts/whistle_end.wav',
          'assets/audio/callouts/whistle_end.mp3',
        ], waitForCompletion: true);
      }
    } finally {
      await _disposeInternal();
      _sessions.endFinish();
    }
  }

  void _scheduleAdLibForHold(
    Duration hold,
    DrillConfig config,
    int session,
  ) {
    _timers.cancelAdLib();

    if (!config.adLibsEnabled || hold.inSeconds <= 15) return;

    final slots = AdLibSlots.unlocked(isPro: state.isPro);
    if (slots.isEmpty) return;

    final delay = Duration(
      milliseconds: (hold.inMilliseconds * 0.65).round(),
    );

    _timers.scheduleAdLib(delay, () {
      if (!_sessions.isCurrent(session) || state.finished || state.paused) {
        return;
      }
      final slot = _scheduler.pickOne(slots);
      unawaited(
        _audioService.playAdLib(
          slot,
          config,
          isPro: state.isPro,
          shouldAbort: () =>
              !_sessions.isCurrent(session) || state.finished || state.paused,
        ),
      );
    });
  }

  Future<void> _disposeInternal() async {
    _timers.cancel();
    await _audioService.disposePlayers();
    _preparedStartKey = null;
    _nextCalloutToPlay = null;
    _activeConfig = null;
    _activeAllCallouts = const [];
  }
}
