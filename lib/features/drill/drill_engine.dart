import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/audio.dart';
import 'ad_libs.dart';
import 'intervals.dart';
import 'models.dart';
import 'providers.dart';
import 'recording_policy.dart';

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
  static int _globalSessionId = 0;
  static bool _isGlobalFinishing = false;

  static const Duration _firstCalloutDelay = Duration(milliseconds: 1500);
  static const Duration _audioCompletionTimeout = Duration(seconds: 5);
  static CameraController? _cameraController;

  bool _isStoppingVideo = false;
  bool _isStarting = false;
  int _cameraGeneration = 0;

  CameraController? get cameraController => _cameraController;

  final _stopwatch = Stopwatch();
  Timer? _ticker, _nextTimer, _holdTimer;

  final Map<String, String> _assetForId = {};
  String? _lastCalloutId;
  String? _preparedCueKey;
  String? _preparingCueKey;
  String? _preparedStartKey;
  Future<void>? _cuePreparation;
  bool _finishing = false;
  IAudioPlayer? _cuePlayer;
  IAudioPlayer? _whistlePlayer;
  IAudioPlayer? _adLibPlayer;

  AudioFactory get _audio => ref.read(audioFactoryProvider);
  IntervalStrategy get _intervals => ref.read(intervalStrategyProvider);

  @override
  DrillState build() {
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
    final generation = ++_cameraGeneration;
    await _initializeCamera(session: null, cameraGeneration: generation);
  }

  Future<void> disposeCamera() async {
    _cameraGeneration++;
    final controller = _cameraController;
    _cameraController = null;
    state = state.copyWith(cameraInitialized: false);

    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> warmUpForStart({
    required DrillConfig config,
    required List<Callout> allCallouts,
    required bool isPro,
  }) async {
    if (_isStarting || state.running) return;

    final effectiveConfig = RecordingPolicy.effectiveConfig(
      config: config,
      isPro: isPro,
    );
    final preparationKey = _preparationKey(
      config: effectiveConfig,
      allCallouts: allCallouts,
      isPro: isPro,
    );

    if (_preparedStartKey == preparationKey &&
        (_cuePreparation == null || _preparingCueKey == _preparedCueKey)) {
      return;
    }

    await _resetAudioPlayers();
    _assetForId.clear();
    _lastCalloutId = null;
    _nextCalloutToPlay = null;

    final bool alreadyReady =
        _cameraController != null && _cameraController!.value.isInitialized;
    if (effectiveConfig.videoEnabled && !alreadyReady) {
      final cameraGeneration = ++_cameraGeneration;
      await _initializeCamera(
        session: null,
        cameraGeneration: cameraGeneration,
      );
    }

    final selected = _selectedCalloutsFor(effectiveConfig, allCallouts);
    await _preloadAudio(selected);
    if (selected.isNotEmpty) {
      _nextCalloutToPlay = _pickRandomCallout(selected);
      await _prepareCuePlayerFor(_nextCalloutToPlay!, effectiveConfig);
    }

    _preparedStartKey = preparationKey;
  }

  Future<void> start({
    required DrillConfig config,
    required List<Callout> allCallouts,
    required bool isPro,
    bool playStartWhistle = true,
  }) async {
    if (_isStarting) return;
    _isStarting = true;

    try {
      if (_isGlobalFinishing) return;

      _globalSessionId++;
      final thisSession = _globalSessionId;
      final effectiveConfig = RecordingPolicy.effectiveConfig(
        config: config,
        isPro: isPro,
      );
      final preparationKey = _preparationKey(
        config: effectiveConfig,
        allCallouts: allCallouts,
        isPro: isPro,
      );
      final usePreparedStart = _preparedStartKey == preparationKey;
      final selected = _selectedCalloutsFor(effectiveConfig, allCallouts);

      _cancelTimers();

      if (!usePreparedStart) {
        await _resetAudioPlayers();
        _assetForId.clear();
        _nextCalloutToPlay = null;
      }

      _finishing = false;
      _isStoppingVideo = false;
      _lastCalloutId = null;

      final bool alreadyReady =
          _cameraController != null && _cameraController!.value.isInitialized;

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
        cameraInitialized: alreadyReady,
        isRecording: false,
      );

      if (effectiveConfig.videoEnabled && !alreadyReady) {
        final cameraGeneration = ++_cameraGeneration;
        await _initializeCamera(
          session: thisSession,
          cameraGeneration: cameraGeneration,
        );
        if (thisSession != _globalSessionId || state.finished) return;
      }

      if (!usePreparedStart) {
        await _preloadAudio(selected);
      }
      if (selected.isNotEmpty && _nextCalloutToPlay == null) {
        _nextCalloutToPlay = _pickRandomCallout(selected);
      }
      if (selected.isNotEmpty) {
        await _prepareCuePlayerFor(_nextCalloutToPlay!, effectiveConfig);
      }
      if (thisSession != _globalSessionId || state.finished) return;
      _preparedStartKey = null;

      if (playStartWhistle) {
        await _playFirstAvailableOnCallout([
          'assets/audio/callouts/whistle_start.wav',
          'assets/audio/callouts/whistle_start.mp3',
        ], thisSession);
        await Future.delayed(const Duration(milliseconds: 1600));
      }

      if (thisSession != _globalSessionId || state.finished) return;

      if (effectiveConfig.videoEnabled && state.cameraInitialized) {
        await _startRecording();
      }

      _stopwatch
        ..reset()
        ..start();

      _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (thisSession != _globalSessionId || _finishing) {
          timer.cancel();
          return;
        }

        final elapsed = _stopwatch.elapsed;
        final cappedElapsed = elapsed >= state.total ? state.total : elapsed;

        state = state.copyWith(running: true, elapsed: cappedElapsed);

        if (cappedElapsed >= state.total && !_isStoppingVideo) {
          timer.cancel();
          unawaited(_finish(playEndWhistle: true, session: thisSession));
          return;
        }
      });

      _nextTimer = Timer(_firstCalloutDelay, () {
        if (thisSession == _globalSessionId && !state.finished) {
          _fire(selected, effectiveConfig, thisSession);
        }
      });
    } catch (e) {
      debugPrint('[drill] CRITICAL START ERROR: $e');
    } finally {
      _isStarting = false;
    }
  }

  void pause() {
    if (state.finished || state.paused) return;
    _cancelTimers(keepTicker: true);
    _stopwatch.stop();
    state = state.copyWith(paused: true);
  }

  void resume(
      {required DrillConfig config, required List<Callout> allCallouts}) {
    if (state.finished || !state.paused) return;
    _stopwatch.start();
    final selected = allCallouts
        .where((c) => config.enabledCalloutIds.contains(c.id))
        .toList();

    _scheduleNext(
      _nextCalloutDelay(config),
      config,
      selected,
      _globalSessionId,
    );
    state = state.copyWith(paused: false);
  }

  Future<void> stop() async {
    await _finish(playEndWhistle: false);
  }

  Future<void> _fire(
      List<Callout> selected, DrillConfig cfg, int session) async {
    if (session != _globalSessionId || state.finished || selected.isEmpty) {
      return;
    }
    _adLibTimer?.cancel();

    final pending = _nextCalloutToPlay;
    final next =
        pending != null && selected.any((callout) => callout.id == pending.id)
            ? pending
            : _pickRandomCallout(selected);
    _nextCalloutToPlay = null;
    _lastCalloutId = next.id;

    unawaited(HapticFeedback.lightImpact());
    state = state.copyWith(lastCallout: next, holdRemaining: null);

    await _playCallout(next, session, cfg);

    if (session != _globalSessionId || state.finished) return;
    final newCount = state.calloutsCompleted + 1;

    final overrideDuration = cfg.calloutOverrideDurations[next.id];
    final effectiveDuration = overrideDuration ?? next.defaultDurationSeconds;

    final delay = _nextCalloutDelay(cfg);

    if (next.type == 'Duration' && effectiveDuration > 0) {
      final hold = Duration(seconds: effectiveDuration);

      state = state.copyWith(
        holdRemaining: hold,
        calloutsCompleted: newCount,
      );

      _scheduleAdLibForHold(hold, cfg, session);

      _holdTimer?.cancel();
      _holdTimer = Timer(hold, () {
        if (session == _globalSessionId && !state.finished) {
          state = state.copyWith(holdRemaining: null);
          _scheduleNext(delay, cfg, selected, session);
        }
      });
    } else {
      state = state.copyWith(
        holdRemaining: null,
        calloutsCompleted: newCount,
      );
      _adLibTimer?.cancel();
      _scheduleNext(delay, cfg, selected, session);
    }
  }

  void _scheduleNext(double delaySeconds, DrillConfig cfg,
      List<Callout> selected, int session) {
    _nextTimer?.cancel();

    _nextCalloutToPlay = _pickRandomCallout(selected);
    unawaited(_prepareCuePlayerFor(_nextCalloutToPlay!, cfg));

    _nextTimer = Timer(
      Duration(milliseconds: (delaySeconds * 1000).round()),
      () {
        if (session == _globalSessionId && !state.finished) {
          _fire(selected, cfg, session);
        }
      },
    );
  }

  double _nextCalloutDelay(DrillConfig config) {
    return _isGableMode(config)
        ? 0
        : _intervals.next(
            config.minIntervalSeconds,
            config.maxIntervalSeconds,
          );
  }

  bool _isGableMode(DrillConfig config) {
    return (config.minIntervalSeconds - 0.5).abs() < 0.1 &&
        (config.maxIntervalSeconds - 1.5).abs() < 0.1;
  }

  Future<void> _finish({bool playEndWhistle = true, int? session}) async {
    if (session != null && session != _globalSessionId) return;
    if (_isGlobalFinishing || state.finished) return;

    _finishing = true;
    _isGlobalFinishing = true;

    try {
      _cancelTimers();
      _stopwatch.stop();

      //  Synchronize Stop Lock
      // If the ticker already triggered _stopAndSaveVideo (due to the 60s limit),
      // we must wait for it to finish rather than skipping it.
      if (_isStoppingVideo) {
        int attempts = 0;
        while (_isStoppingVideo && attempts < 50) {
          // Max 5 seconds waiting
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
      } else if (state.isRecording) {
        try {
          await _stopAndSaveVideo().timeout(const Duration(seconds: 5));
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

      // FIX: Increase Disposal Delay
      // Increase delay drastically to give the native Android MediaRecorder
      // time to write the MP4 "moov" atom metadata to disk before destruction.
      await Future.delayed(const Duration(milliseconds: 1500));

      final controller = _cameraController;
      _cameraController = null;
      if (controller != null) {
        try {
          await controller.dispose().timeout(const Duration(seconds: 2));
        } catch (e) {
          debugPrint('[camera] Dispose error: $e');
        }
      }

      state = state.copyWith(
        finished: true,
        holdRemaining: null,
        cameraInitialized: false,
        isRecording: false,
      );

      await _cuePlayer?.stop();
      await _adLibPlayer?.stop();

      if (playEndWhistle) {
        await _playFirstAvailableOnCallout([
          'assets/audio/callouts/whistle_end.wav',
          'assets/audio/callouts/whistle_end.mp3',
        ], _globalSessionId, waitForCompletion: true, allowFinished: true);
      }
    } finally {
      await _disposeInternal();
      _isGlobalFinishing = false;
    }
  }

  Future<void> _initializeCamera({
    int? session,
    required int cameraGeneration,
  }) async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      state = state.copyWith(cameraInitialized: true);
      return;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (cameraGeneration != _cameraGeneration ||
        (session != null && session != _globalSessionId)) {
      return;
    }

    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted) {
      state = state.copyWith(cameraInitialized: false);
      return;
    }

    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        state = state.copyWith(cameraInitialized: false);
        return;
      }

      if (cameraGeneration != _cameraGeneration ||
          (session != null && session != _globalSessionId)) {
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      if (cameraGeneration != _cameraGeneration ||
          (session != null && session != _globalSessionId)) {
        await controller.dispose();
        return;
      }

      final previousController = _cameraController;
      _cameraController = controller;
      if (previousController != null && previousController != controller) {
        await previousController.dispose();
      }
      state = state.copyWith(cameraInitialized: true);
    } catch (e) {
      await controller?.dispose();
      state = state.copyWith(cameraInitialized: false);
      _cameraController = null;
    }
  }

  Future<void> _startRecording() async {
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      try {
        await controller.startVideoRecording();
        state = state.copyWith(isRecording: true);
      } catch (e) {
        state = state.copyWith(isRecording: false);
      }
    }
  }

  Future<void> _stopAndSaveVideo() async {
    if (_isStoppingVideo) return;

    final controller = _cameraController;
    if (controller == null || !controller.value.isRecordingVideo) {
      state = state.copyWith(isRecording: false);
      return;
    }

    _isStoppingVideo = true;
    try {
      final file = await controller.stopVideoRecording();
      state = state.copyWith(videoPath: file.path, isRecording: false);
    } catch (e) {
      debugPrint('[camera] Error saving video: $e');
      state = state.copyWith(isRecording: false);
    } finally {
      _isStoppingVideo = false;
    }
  }

  Callout? _nextCalloutToPlay;
  Timer? _adLibTimer;

  void _scheduleAdLibForHold(
    Duration hold,
    DrillConfig config,
    int session,
  ) {
    _adLibTimer?.cancel();

    if (!config.adLibsEnabled || hold.inSeconds <= 15) return;

    final slots = AdLibSlots.unlocked(isPro: state.isPro);
    if (slots.isEmpty) return;

    final delay = Duration(
      milliseconds: (hold.inMilliseconds * 0.65).round(),
    );

    _adLibTimer = Timer(delay, () {
      if (session != _globalSessionId || state.finished || state.paused) {
        return;
      }
      final slot = slots[math.Random().nextInt(slots.length)];
      unawaited(_playAdLib(slot, config, session));
    });
  }

  Future<void> _playCallout(Callout c, int session, DrillConfig config) async {
    if (session != _globalSessionId) return;
    final audioKey = _calloutAudioKey(c, config);
    final player =
        _cuePlayer ??= _audio.createPlayer(debugLabel: 'callout_cue');

    try {
      if (audioKey != null &&
          _preparingCueKey == audioKey &&
          _cuePreparation != null) {
        await _cuePreparation;
      }

      if (audioKey == null || _preparedCueKey != audioKey) {
        await _setSourceForCallout(player, c, config);
        _preparedCueKey = audioKey;
      }
      if (session == _globalSessionId && !state.finished) {
        await _playAndWaitForCompletion(
          player,
          session,
          debugLabel: 'callout ${c.id}',
        );
      }
    } catch (e) {
      debugPrint('[audio] Failed to play callout "${c.id}": $e');
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  Future<void> _setSourceForCallout(
    IAudioPlayer player,
    Callout c,
    DrillConfig config,
  ) async {
    final customPath = _localAudioPathFor(c, config);
    if (customPath != null) {
      await player.setDeviceFile(customPath);
      return;
    }

    if (c.isCustom) {
      throw StateError('Custom callout audio file is unavailable.');
    }

    final targetId = c.audioAssetAlias ?? c.id;
    final asset =
        _assetForId[targetId] ?? 'assets/audio/callouts/$targetId.wav';
    await player.setAsset(asset);
  }

  Future<void> _prepareCuePlayerFor(
    Callout callout,
    DrillConfig config,
  ) async {
    final key = _calloutAudioKey(callout, config);
    if (key == null || _preparedCueKey == key || _preparingCueKey == key) {
      return;
    }

    final player =
        _cuePlayer ??= _audio.createPlayer(debugLabel: 'callout_cue');
    _preparingCueKey = key;
    final preparation = _setSourceForCallout(player, callout, config);
    _cuePreparation = preparation;

    try {
      await preparation;
      if (_preparingCueKey == key) {
        _preparedCueKey = key;
      }
    } catch (e) {
      if (_preparingCueKey == key) {
        _preparedCueKey = null;
      }
      debugPrint('[audio] Failed to prepare callout "${callout.id}": $e');
    } finally {
      if (_preparingCueKey == key) {
        _preparingCueKey = null;
      }
      if (identical(_cuePreparation, preparation)) {
        _cuePreparation = null;
      }
    }
  }

  String? _calloutAudioKey(Callout c, DrillConfig config) {
    final customPath = _localAudioPathFor(c, config);
    if (customPath != null) return 'file:$customPath';
    if (c.isCustom) return null;

    final targetId = c.audioAssetAlias ?? c.id;
    final asset =
        _assetForId[targetId] ?? 'assets/audio/callouts/$targetId.wav';
    return 'asset:$asset';
  }

  List<Callout> _selectedCalloutsFor(
    DrillConfig config,
    List<Callout> allCallouts,
  ) {
    return allCallouts
        .where((c) => config.enabledCalloutIds.contains(c.id))
        .toList();
  }

  String _preparationKey({
    required DrillConfig config,
    required List<Callout> allCallouts,
    required bool isPro,
  }) {
    final enabledIds = config.enabledCalloutIds.toList()..sort();
    final customPaths = config.customAudioPaths.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final selectedAudio = _selectedCalloutsFor(config, allCallouts)
        .map(
          (c) => [
            c.id,
            c.audioAssetAlias ?? '',
            config.customAudioPaths[c.id] ?? c.audioUrl ?? '',
          ].join(':'),
        )
        .join('|');

    return [
      isPro ? 'pro' : 'free',
      config.videoEnabled ? 'video' : 'no-video',
      config.totalDurationSeconds,
      config.minIntervalSeconds,
      config.maxIntervalSeconds,
      config.adLibsEnabled,
      enabledIds.join(','),
      customPaths.map((e) => '${e.key}:${e.value}').join('|'),
      selectedAudio,
    ].join(';');
  }

  Future<void> _playAdLib(
    AdLibSlot slot,
    DrillConfig config,
    int session,
  ) async {
    if (session != _globalSessionId || state.finished) return;
    final player =
        _adLibPlayer ??= _audio.createPlayer(debugLabel: 'ad_lib_cue');

    try {
      await _setSourceForAdLib(player, slot, config);
      if (session == _globalSessionId && !state.finished && !state.paused) {
        await player.play();
      }
    } catch (e) {
      debugPrint('[audio] Failed to play ad lib "${slot.id}": $e');
    }
  }

  Future<void> _setSourceForAdLib(
    IAudioPlayer player,
    AdLibSlot slot,
    DrillConfig config,
  ) async {
    final customPath = slot.customPath(config, isPro: state.isPro);
    if (customPath != null &&
        !customPath.startsWith('http://') &&
        !customPath.startsWith('https://') &&
        File(customPath).existsSync()) {
      await player.setDeviceFile(customPath);
      return;
    }

    await player.setAsset(slot.defaultAssetPath);
  }

  Future<void> _playAndWaitForCompletion(
    IAudioPlayer player,
    int session, {
    Duration timeout = _audioCompletionTimeout,
    bool allowFinished = false,
    String debugLabel = 'cue',
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<void> subscription;

    subscription = player.onPlayerComplete.listen(
      (_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      try {
        await player.seek(Duration.zero);
      } catch (_) {
        // Some platform decoders reject seek-before-play; playing still works.
      }
      await player.play();
      if (session != _globalSessionId || (!allowFinished && state.finished)) {
        return;
      }

      await completer.future.timeout(
        timeout,
        onTimeout: () {
          if (session == _globalSessionId &&
              (allowFinished || !state.finished)) {
            debugPrint('[audio] Playback completion timed out for $debugLabel');
          }
        },
      );
    } finally {
      await subscription.cancel();
    }
  }

  String? _localAudioPathFor(Callout c, DrillConfig config) {
    final path = config.customAudioPaths[c.id] ?? c.audioUrl;
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return null;
    return File(path).existsSync() ? path : null;
  }

  Future<bool> _playFirstAvailableOnCallout(
    List<String> candidates,
    int session, {
    bool waitForCompletion = false,
    bool allowFinished = false,
  }) async {
    final player =
        _whistlePlayer ??= _audio.createPlayer(debugLabel: 'whistle_cue');

    for (final asset in candidates) {
      try {
        await player.setAsset(asset);
        if (session != _globalSessionId || (!allowFinished && state.finished)) {
          return false;
        }
        if (waitForCompletion) {
          await _playAndWaitForCompletion(
            player,
            session,
            timeout: const Duration(seconds: 2),
            allowFinished: allowFinished,
            debugLabel: asset,
          );
        } else {
          await player.play();
        }
        return true;
      } catch (e) {
        debugPrint('[audio] Failed to play cue "$asset": $e');
      }
    }
    return false;
  }

  Future<void> _preloadAudio(List<Callout> selected) async {
    Future<bool> assetExists(String path) async {
      try {
        await rootBundle.load(path);
        return true;
      } catch (_) {
        return false;
      }
    }

    for (final c in selected) {
      final targetId = c.audioAssetAlias ?? c.id;
      final base = 'assets/audio/callouts/$targetId';
      String? found;

      // '$base.WAV' to match the uppercase extensions in assets folder
      for (final path in <String>[
        '$base.WAV',
        '$base.wav',
        '$base.mp3',
        '$base.m4a'
      ]) {
        if (await assetExists(path)) {
          found = path;
          break;
        }
      }

      if (found != null) _assetForId[targetId] = found;
    }
  }

  void _cancelTimers({bool keepTicker = false}) {
    _nextTimer?.cancel();
    _nextTimer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _adLibTimer?.cancel();
    _adLibTimer = null;
    if (!keepTicker) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _disposeInternal() async {
    _cancelTimers();
    await _disposeAudioPlayers();
    _assetForId.clear();
  }

  Future<void> _resetAudioPlayers() async {
    await _disposeAudioPlayers();
    _preparedCueKey = null;
    _preparingCueKey = null;
    _preparedStartKey = null;
    _cuePreparation = null;
    _cuePlayer = _audio.createPlayer(debugLabel: 'callout_cue');
    _whistlePlayer = _audio.createPlayer(debugLabel: 'whistle_cue');
    _adLibPlayer = _audio.createPlayer(debugLabel: 'ad_lib_cue');
  }

  Future<void> _disposeAudioPlayers() async {
    final players = <IAudioPlayer?>[_cuePlayer, _whistlePlayer, _adLibPlayer];
    _cuePlayer = null;
    _whistlePlayer = null;
    _adLibPlayer = null;
    _preparedCueKey = null;
    _preparingCueKey = null;
    _preparedStartKey = null;
    _cuePreparation = null;

    for (final player in players.whereType<IAudioPlayer>()) {
      try {
        await player.stop();
        await player.dispose();
      } catch (e) {
        debugPrint('[audio] Error disposing player: $e');
      }
    }
  }

  Callout _pickRandomCallout(List<Callout> options) {
    if (options.length <= 1) return options.first;
    final rng = math.Random();
    Callout pick;
    int guard = 0;
    do {
      pick = options[rng.nextInt(options.length)];
      guard++;
    } while (pick.id == _lastCalloutId && guard < 10);
    return pick;
  }
}
