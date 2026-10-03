import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/audio.dart';
import '../ad_libs.dart';
import '../models.dart';
import '../voice_packs.dart';
import 'drill_audio_coordinator.dart';
import 'drill_audio_diagnostics.dart';

typedef AssetExists = Future<bool> Function(String path);
typedef VoicePackLoader = Future<VoicePack?> Function(String id);

class CalloutAudioAssetResolver {
  static const _extensions = ['wav'];

  final AssetExists _assetExists;
  final VoicePackLoader _voicePackLoader;
  final Map<String, String?> _cache = {};

  CalloutAudioAssetResolver({
    AssetExists? assetExists,
    VoicePackLoader? voicePackLoader,
  })  : _assetExists = assetExists ?? _bundleAssetExists,
        _voicePackLoader = voicePackLoader ?? _loadBundledVoicePack;

  static Future<bool> _bundleAssetExists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<VoicePack?> _loadBundledVoicePack(String id) async {
    final packs = await const VoicePackCatalog().load();
    for (final pack in packs) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  String _cacheKey(String voicePackId, String cueId) => '$voicePackId:$cueId';

  Future<String?> resolve(
    String targetId, {
    String voicePackId = DrillConfig.defaultVoicePackId,
  }) async {
    final key = _cacheKey(voicePackId, targetId);
    if (_cache.containsKey(key)) return _cache[key];

    String? configuredPath;
    if (voicePackId != DrillConfig.defaultVoicePackId) {
      configuredPath =
          (await _voicePackLoader(voicePackId))?.calloutAssets[targetId];
    }
    final base = 'assets/audio/callouts/$targetId';
    for (final extension in _extensions) {
      final path = configuredPath ?? '$base.$extension';
      if (await _assetExists(path)) {
        _cache[key] = path;
        return path;
      }
      if (configuredPath != null) break;
    }

    _cache[key] = null;
    return null;
  }

  Future<String?> resolveAdLib(String voicePackId, String slotId) async {
    if (voicePackId == DrillConfig.defaultVoicePackId) {
      return 'assets/audio/ad_libs/$slotId.wav';
    }
    return (await _voicePackLoader(voicePackId))?.adLibAssets[slotId];
  }

  Future<String?> resolveWhistle(String voicePackId) async {
    if (voicePackId == DrillConfig.defaultVoicePackId) {
      return 'assets/audio/callouts/whistle.wav';
    }
    return (await _voicePackLoader(voicePackId))?.whistleAsset;
  }

  String? cached(
    String targetId, {
    String voicePackId = DrillConfig.defaultVoicePackId,
  }) =>
      _cache[_cacheKey(voicePackId, targetId)];

  bool isKnownMissing(
    String targetId, {
    String voicePackId = DrillConfig.defaultVoicePackId,
  }) {
    final key = _cacheKey(voicePackId, targetId);
    return _cache.containsKey(key) && _cache[key] == null;
  }

  void clear() => _cache.clear();
}

class DrillAudioService {
  static const Duration _audioCompletionTimeout = Duration(seconds: 5);

  final AudioFactory _audio;
  final CalloutAudioAssetResolver _assetResolver;
  final DrillAudioCoordinator _coordinator;
  final DrillAudioDiagnosticSink _diagnostics;

  final Map<String, IAudioPlayer> _preparedCuePlayers = {};
  final Map<String, Future<IAudioPlayer>> _cuePreparations = {};
  IAudioPlayer? _activeCuePlayer;
  IAudioPlayer? _activeWhistlePlayer;
  int _cueGeneration = 0;
  IAudioPlayer? _whistlePlayer;
  IAudioPlayer? _adLibPlayer;

  DrillAudioService({
    required AudioFactory audioFactory,
    CalloutAudioAssetResolver? assetResolver,
    DrillAudioCoordinator? coordinator,
    DrillAudioDiagnosticSink? diagnostics,
  })  : _audio = audioFactory,
        _assetResolver = assetResolver ?? CalloutAudioAssetResolver(),
        _coordinator = coordinator ?? DrillAudioCoordinator(),
        _diagnostics = diagnostics ?? debugDrillAudioDiagnosticSink;

  Future<void> resetPlayers() async {
    await disposePlayers();
    _whistlePlayer = _audio.createPlayer(debugLabel: 'whistle_cue');
    _adLibPlayer = _audio.createPlayer(debugLabel: 'ad_lib_cue');
    await _whistlePlayer!.initialize();
    await _adLibPlayer!.initialize();
  }

  Future<void> preloadAudio(
    List<Callout> selected,
    DrillConfig config,
  ) async {
    for (final callout in selected) {
      if (callout.isCustom) continue;
      final targetId = callout.audioAssetAlias ?? callout.id;
      final asset = await _assetResolver.resolve(
        targetId,
        voicePackId: config.voicePackId,
      );
      if (asset == null) {
        _emit(
          DrillAudioDiagnosticType.assetMissing,
          cue: 'callout:${callout.id}',
          detail: targetId,
        );
      }
    }

    final desiredKeys = <String>{};
    for (final callout in selected) {
      final key = calloutAudioKey(callout, config);
      if (key == null) continue;
      desiredKeys.add(key);

      try {
        await _ensureCuePrepared(key, callout, config);
      } catch (e) {
        debugPrint('[audio] Failed to preload callout "${callout.id}": $e');
      }
    }

    final staleKeys = _preparedCuePlayers.keys
        .where((key) => !desiredKeys.contains(key))
        .toList();
    for (final key in staleKeys) {
      final player = _preparedCuePlayers.remove(key);
      if (player != null) {
        await _disposePlayer(player, debugLabel: 'stale callout $key');
      }
    }
  }

  Future<void> prepareCuePlayerFor(
    Callout callout,
    DrillConfig config,
  ) async {
    final key = calloutAudioKey(callout, config);
    if (key == null || _preparedCuePlayers.containsKey(key)) return;

    try {
      await _ensureCuePrepared(key, callout, config);
    } catch (e) {
      debugPrint('[audio] Failed to prepare callout "${callout.id}": $e');
    }
  }

  Future<void> playCallout(
    Callout callout,
    DrillConfig config, {
    bool Function()? shouldAbort,
  }) async {
    final audioKey = calloutAudioKey(callout, config);
    if (audioKey == null) {
      _emit(
        DrillAudioDiagnosticType.playbackFailed,
        cue: 'callout:${callout.id}',
        error: 'no playable audio',
      );
      throw StateError('Callout "${callout.id}" has no playable audio.');
    }
    if (!_preparedCuePlayers.containsKey(audioKey) &&
        !_cuePreparations.containsKey(audioKey)) {
      _emit(
        DrillAudioDiagnosticType.playbackFailed,
        cue: 'callout:${callout.id}',
        error: 'cue was not preloaded',
      );
      throw StateError(
        'Callout "${callout.id}" was not preloaded before playback.',
      );
    }

    _emit(
      DrillAudioDiagnosticType.playbackQueued,
      cue: 'callout:${callout.id}',
    );
    try {
      await _coordinator.run<void>(
        priority: DrillAudioPriority.callout,
        operation: (cancellation) => _playPreparedCalloutWithRetry(
          audioKey: audioKey,
          callout: callout,
          config: config,
          cancellation: cancellation,
          shouldAbort: shouldAbort,
        ),
      );
    } catch (e) {
      debugPrint('[audio] Failed to play callout "${callout.id}": $e');
      rethrow;
    }
  }

  Future<void> _playPreparedCalloutWithRetry({
    required String audioKey,
    required Callout callout,
    required DrillConfig config,
    required DrillAudioCancellation cancellation,
    bool Function()? shouldAbort,
  }) async {
    if (cancellation.isCancelled || shouldAbort?.call() == true) return;

    final preparedPlayer = await _preparedPlayerFor(audioKey);
    if (preparedPlayer == null) {
      throw StateError(
        'Callout "${callout.id}" was not preloaded before playback.',
      );
    }
    var player = preparedPlayer;

    for (var attempt = 0; attempt < 2; attempt++) {
      if (cancellation.isCancelled || shouldAbort?.call() == true) return;

      final attemptPlayer = player;
      _activeCuePlayer = attemptPlayer;
      try {
        await _playAndWaitForCompletion(
          attemptPlayer,
          cancellation: cancellation,
          shouldAbort: shouldAbort,
          debugLabel: 'callout ${callout.id}',
        );
        return;
      } catch (error) {
        if (cancellation.isCancelled || shouldAbort?.call() == true) return;
        if (attempt == 1) rethrow;

        debugPrint(
          '[audio] Rebuilding callout "${callout.id}" after decoder error: '
          '$error',
        );
        _emit(
          DrillAudioDiagnosticType.decoderRetry,
          cue: 'callout:${callout.id}',
          attempt: attempt + 2,
          error: error,
        );
        player = await _recreatePreparedCue(
          key: audioKey,
          failedPlayer: attemptPlayer,
          callout: callout,
          config: config,
        );
      } finally {
        if (identical(_activeCuePlayer, attemptPlayer)) {
          _activeCuePlayer = null;
        }
      }
    }
  }

  Future<IAudioPlayer?> _preparedPlayerFor(String key) async {
    final prepared = _preparedCuePlayers[key];
    if (prepared != null) return prepared;
    return _cuePreparations[key];
  }

  Future<IAudioPlayer> _recreatePreparedCue({
    required String key,
    required IAudioPlayer failedPlayer,
    required Callout callout,
    required DrillConfig config,
  }) async {
    if (identical(_preparedCuePlayers[key], failedPlayer)) {
      _preparedCuePlayers.remove(key);
    }
    await _disposePlayer(
      failedPlayer,
      debugLabel: 'failed callout ${callout.id}',
    );
    return _ensureCuePrepared(key, callout, config);
  }

  Future<IAudioPlayer> _ensureCuePrepared(
    String key,
    Callout callout,
    DrillConfig config,
  ) {
    final prepared = _preparedCuePlayers[key];
    if (prepared != null) return Future.value(prepared);

    final pending = _cuePreparations[key];
    if (pending != null) return pending;

    final generation = _cueGeneration;
    late final Future<IAudioPlayer> preparation;
    preparation = _createPreparedCuePlayer(
      key: key,
      callout: callout,
      config: config,
      generation: generation,
    ).whenComplete(() {
      if (identical(_cuePreparations[key], preparation)) {
        _cuePreparations.remove(key);
      }
    });
    _cuePreparations[key] = preparation;
    return preparation;
  }

  Future<IAudioPlayer> _createPreparedCuePlayer({
    required String key,
    required Callout callout,
    required DrillConfig config,
    required int generation,
  }) async {
    final preparationTimer = Stopwatch()..start();
    _emit(
      DrillAudioDiagnosticType.preparationStarted,
      cue: 'callout:${callout.id}',
    );
    final player = _audio.createPlayer(debugLabel: 'callout:${callout.id}');
    try {
      await setSourceForCallout(player, callout, config);
      if (generation != _cueGeneration) {
        throw StateError('Callout preparation was superseded.');
      }
      _preparedCuePlayers[key] = player;
      _emit(
        DrillAudioDiagnosticType.preparationCompleted,
        cue: 'callout:${callout.id}',
        elapsed: preparationTimer.elapsed,
      );
      return player;
    } catch (error) {
      _emit(
        DrillAudioDiagnosticType.preparationFailed,
        cue: 'callout:${callout.id}',
        elapsed: preparationTimer.elapsed,
        error: error,
      );
      await _disposePlayer(player, debugLabel: 'failed callout $key');
      rethrow;
    }
  }

  Future<void> setSourceForCallout(
    IAudioPlayer player,
    Callout callout,
    DrillConfig config,
  ) async {
    final customPath = localAudioPathFor(callout, config);
    if (customPath != null) {
      await player.setDeviceFile(customPath);
      return;
    }

    if (callout.isCustom) {
      throw StateError('Custom callout audio file is unavailable.');
    }

    final targetId = callout.audioAssetAlias ?? callout.id;
    final cachedAsset = _assetResolver.cached(
      targetId,
      voicePackId: config.voicePackId,
    );
    if (cachedAsset == null &&
        _assetResolver.isKnownMissing(
          targetId,
          voicePackId: config.voicePackId,
        )) {
      throw StateError('Bundled callout asset "$targetId" is missing.');
    }
    final asset = cachedAsset ??
        await _assetResolver.resolve(
          targetId,
          voicePackId: config.voicePackId,
        );
    if (asset == null) {
      throw StateError(
        'Voice pack "${config.voicePackId}" has no "$targetId" audio.',
      );
    }
    await player.setAsset(asset);
  }

  String? calloutAudioKey(Callout callout, DrillConfig config) {
    final customPath = localAudioPathFor(callout, config);
    if (customPath != null) return 'file:$customPath';
    if (callout.isCustom) return null;

    final targetId = callout.audioAssetAlias ?? callout.id;
    final cachedAsset = _assetResolver.cached(
      targetId,
      voicePackId: config.voicePackId,
    );
    if (cachedAsset == null &&
        _assetResolver.isKnownMissing(
          targetId,
          voicePackId: config.voicePackId,
        )) {
      return null;
    }
    final asset = cachedAsset ??
        (config.voicePackId == DrillConfig.defaultVoicePackId
            ? 'assets/audio/callouts/$targetId.wav'
            : null);
    if (asset == null) return null;
    return 'asset:$asset';
  }

  String? localAudioPathFor(Callout callout, DrillConfig config) {
    final path = config.customAudioPaths[callout.id] ?? callout.audioUrl;
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return null;
    return File(path).existsSync() ? path : null;
  }

  Future<void> playAdLib(
    AdLibSlot slot,
    DrillConfig config, {
    required bool isPro,
    bool Function()? shouldAbort,
  }) async {
    final player =
        _adLibPlayer ??= _audio.createPlayer(debugLabel: 'ad_lib_cue');

    _emit(
      DrillAudioDiagnosticType.playbackQueued,
      cue: 'ad-lib:${slot.id}',
    );
    try {
      await _coordinator.run<void>(
        priority: DrillAudioPriority.adLib,
        preemptLowerPriorities: false,
        operation: (cancellation) async {
          if (cancellation.isCancelled || shouldAbort?.call() == true) return;
          await _setSourceForAdLib(player, slot, config, isPro: isPro);
          if (cancellation.isCancelled || shouldAbort?.call() == true) return;
          await _playAndWaitForCompletion(
            player,
            cancellation: cancellation,
            shouldAbort: shouldAbort,
            debugLabel: 'ad lib ${slot.id}',
          );
        },
      );
    } catch (e) {
      debugPrint('[audio] Failed to play ad lib "${slot.id}": $e');
    }
  }

  Future<void> _setSourceForAdLib(
    IAudioPlayer player,
    AdLibSlot slot,
    DrillConfig config, {
    required bool isPro,
  }) async {
    final customPath = slot.customPath(config, isPro: isPro);
    if (customPath != null &&
        !customPath.startsWith('http://') &&
        !customPath.startsWith('https://') &&
        File(customPath).existsSync()) {
      await player.setDeviceFile(customPath);
      return;
    }

    final asset = await _assetResolver.resolveAdLib(
          config.voicePackId,
          slot.id,
        ) ??
        slot.defaultAssetPath;
    await player.setAsset(asset);
  }

  Future<bool> playWhistle(
    DrillConfig config, {
    bool Function()? shouldAbort,
  }) async {
    final selected = await _assetResolver.resolveWhistle(config.voicePackId);
    return playFirstAvailableOnCallout(
      [
        if (selected != null && selected.isNotEmpty) selected,
        if (selected != 'assets/audio/callouts/whistle.wav')
          'assets/audio/callouts/whistle.wav',
      ],
      shouldAbort: shouldAbort,
    );
  }

  Future<bool> playFirstAvailableOnCallout(
    List<String> candidates, {
    bool Function()? shouldAbort,
  }) async {
    final player =
        _whistlePlayer ??= _audio.createPlayer(debugLabel: 'whistle_cue');

    _emit(
      DrillAudioDiagnosticType.playbackQueued,
      cue: 'whistle',
    );
    final played = await _coordinator.run<bool>(
      priority: DrillAudioPriority.whistle,
      operation: (cancellation) async {
        for (final asset in candidates) {
          if (cancellation.isCancelled || shouldAbort?.call() == true) {
            return false;
          }
          try {
            await player.setAsset(asset);
            if (cancellation.isCancelled || shouldAbort?.call() == true) {
              return false;
            }
            _activeWhistlePlayer = player;
            await _playAndWaitForCompletion(
              player,
              timeout: const Duration(seconds: 2),
              cancellation: cancellation,
              shouldAbort: shouldAbort,
              debugLabel: asset,
            );
            return !cancellation.isCancelled;
          } catch (e) {
            if (cancellation.isCancelled) return false;
            debugPrint('[audio] Failed to play cue "$asset": $e');
          } finally {
            if (identical(_activeWhistlePlayer, player)) {
              _activeWhistlePlayer = null;
            }
          }
        }
        return false;
      },
    );
    return played ?? false;
  }

  Future<void> stopCues() async {
    _emit(DrillAudioDiagnosticType.stopRequested, cue: 'all');
    _coordinator.cancelAll();
    final activePlayers = <IAudioPlayer>{
      if (_activeWhistlePlayer != null) _activeWhistlePlayer!,
      if (_activeCuePlayer != null) _activeCuePlayer!,
      if (_adLibPlayer != null) _adLibPlayer!,
    };
    for (final player in activePlayers) {
      try {
        await player.stop();
      } catch (e) {
        debugPrint('[audio] Error stopping active cue: $e');
      }
    }
  }

  Future<void> disposePlayers() async {
    _coordinator.cancelAll();
    _cueGeneration++;
    final players = <IAudioPlayer>{
      ..._preparedCuePlayers.values,
      if (_activeCuePlayer != null) _activeCuePlayer!,
      if (_activeWhistlePlayer != null) _activeWhistlePlayer!,
      if (_whistlePlayer != null) _whistlePlayer!,
      if (_adLibPlayer != null) _adLibPlayer!,
    };
    _preparedCuePlayers.clear();
    _cuePreparations.clear();
    _activeCuePlayer = null;
    _activeWhistlePlayer = null;
    _whistlePlayer = null;
    _adLibPlayer = null;

    for (final player in players) {
      await _disposePlayer(player);
    }
  }

  void clearAssetCache() => _assetResolver.clear();

  Future<void> _disposePlayer(
    IAudioPlayer player, {
    String debugLabel = 'player',
  }) async {
    try {
      await player.stop();
      await player.dispose();
    } catch (e) {
      debugPrint('[audio] Error disposing $debugLabel: $e');
    }
  }

  Future<void> _playAndWaitForCompletion(
    IAudioPlayer player, {
    Duration timeout = _audioCompletionTimeout,
    DrillAudioCancellation? cancellation,
    bool Function()? shouldAbort,
    String debugLabel = 'cue',
  }) async {
    final playbackTimer = Stopwatch()..start();
    var terminalEventEmitted = false;
    void emitTerminal(
      DrillAudioDiagnosticType type, {
      Object? error,
    }) {
      if (terminalEventEmitted) return;
      terminalEventEmitted = true;
      _emit(
        type,
        cue: debugLabel,
        elapsed: playbackTimer.elapsed,
        error: error,
      );
    }

    final completer = Completer<void>();
    late final StreamSubscription<void> subscription;

    subscription = player.onPlayerComplete.listen(
      (_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    try {
      _emit(
        DrillAudioDiagnosticType.playbackStarted,
        cue: debugLabel,
      );
      try {
        await player.seek(Duration.zero);
      } catch (_) {
        // Some platform decoders reject seek-before-play; playing still works.
      }
      if (cancellation?.isCancelled == true || shouldAbort?.call() == true) {
        emitTerminal(DrillAudioDiagnosticType.playbackCancelled);
        return;
      }
      await player.play();
      if (cancellation?.isCancelled == true || shouldAbort?.call() == true) {
        await player.stop();
        emitTerminal(DrillAudioDiagnosticType.playbackCancelled);
        return;
      }

      final outcomes = <Future<_PlaybackOutcome>>[
        completer.future.then((_) => _PlaybackOutcome.completed),
        if (cancellation != null)
          cancellation.whenCancelled.then((_) => _PlaybackOutcome.cancelled),
      ];
      final outcome = await Future.any(outcomes).timeout(
        timeout,
        onTimeout: () => _PlaybackOutcome.timedOut,
      );
      if (outcome == _PlaybackOutcome.completed) {
        emitTerminal(DrillAudioDiagnosticType.playbackCompleted);
        return;
      }

      if (outcome == _PlaybackOutcome.timedOut && shouldAbort?.call() != true) {
        debugPrint('[audio] Playback completion timed out for $debugLabel');
      }
      await player.stop();
      if (outcome == _PlaybackOutcome.timedOut) {
        final error = TimeoutException(
          'Playback completion timed out for $debugLabel',
          timeout,
        );
        emitTerminal(
          DrillAudioDiagnosticType.playbackFailed,
          error: error,
        );
        throw error;
      }
      emitTerminal(DrillAudioDiagnosticType.playbackCancelled);
    } catch (error) {
      emitTerminal(
        DrillAudioDiagnosticType.playbackFailed,
        error: error,
      );
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }

  void _emit(
    DrillAudioDiagnosticType type, {
    required String cue,
    Duration? elapsed,
    int? attempt,
    Object? error,
    String? detail,
  }) {
    try {
      _diagnostics(
        DrillAudioDiagnosticEvent(
          type: type,
          cue: cue,
          elapsed: elapsed,
          attempt: attempt,
          error: error,
          detail: detail,
        ),
      );
    } catch (diagnosticError) {
      debugPrint('[audio] Diagnostic sink failed: $diagnosticError');
    }
  }
}

enum _PlaybackOutcome {
  completed,
  cancelled,
  timedOut,
}
