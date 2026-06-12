import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/audio.dart';
import '../ad_libs.dart';
import '../models.dart';

typedef AssetExists = Future<bool> Function(String path);

class CalloutAudioAssetResolver {
  static const _extensions = ['WAV', 'wav', 'mp3', 'm4a'];

  final AssetExists _assetExists;
  final Map<String, String?> _cache = {};

  CalloutAudioAssetResolver({AssetExists? assetExists})
      : _assetExists = assetExists ?? _bundleAssetExists;

  static Future<bool> _bundleAssetExists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> resolve(String targetId) async {
    if (_cache.containsKey(targetId)) return _cache[targetId];

    final base = 'assets/audio/callouts/$targetId';
    for (final extension in _extensions) {
      final path = '$base.$extension';
      if (await _assetExists(path)) {
        _cache[targetId] = path;
        return path;
      }
    }

    _cache[targetId] = null;
    return null;
  }

  String? cached(String targetId) => _cache[targetId];

  void clear() => _cache.clear();
}

class DrillAudioService {
  static const Duration _audioCompletionTimeout = Duration(seconds: 5);

  final AudioFactory _audio;
  final CalloutAudioAssetResolver _assetResolver;

  String? _preparedCueKey;
  String? _preparingCueKey;
  Future<void>? _cuePreparation;
  IAudioPlayer? _cuePlayer;
  IAudioPlayer? _whistlePlayer;
  IAudioPlayer? _adLibPlayer;

  DrillAudioService({
    required AudioFactory audioFactory,
    CalloutAudioAssetResolver? assetResolver,
  })  : _audio = audioFactory,
        _assetResolver = assetResolver ?? CalloutAudioAssetResolver();

  Future<void> resetPlayers() async {
    await disposePlayers();
    _cuePlayer = _audio.createPlayer(debugLabel: 'callout_cue');
    _whistlePlayer = _audio.createPlayer(debugLabel: 'whistle_cue');
    _adLibPlayer = _audio.createPlayer(debugLabel: 'ad_lib_cue');
  }

  Future<void> preloadAudio(List<Callout> selected) async {
    for (final callout in selected) {
      final targetId = callout.audioAssetAlias ?? callout.id;
      await _assetResolver.resolve(targetId);
    }
  }

  Future<void> prepareCuePlayerFor(
    Callout callout,
    DrillConfig config,
  ) async {
    final key = calloutAudioKey(callout, config);
    if (key == null || _preparedCueKey == key || _preparingCueKey == key) {
      return;
    }

    final player =
        _cuePlayer ??= _audio.createPlayer(debugLabel: 'callout_cue');
    _preparingCueKey = key;
    final preparation = setSourceForCallout(player, callout, config);
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

  Future<void> playCallout(
    Callout callout,
    DrillConfig config, {
    bool Function()? shouldAbort,
  }) async {
    final audioKey = calloutAudioKey(callout, config);
    final player =
        _cuePlayer ??= _audio.createPlayer(debugLabel: 'callout_cue');

    try {
      if (audioKey != null &&
          _preparingCueKey == audioKey &&
          _cuePreparation != null) {
        await _cuePreparation;
      }

      if (audioKey == null || _preparedCueKey != audioKey) {
        await setSourceForCallout(player, callout, config);
        _preparedCueKey = audioKey;
      }
      if (shouldAbort?.call() == true) return;

      await _playAndWaitForCompletion(
        player,
        shouldAbort: shouldAbort,
        debugLabel: 'callout ${callout.id}',
      );
    } catch (e) {
      debugPrint('[audio] Failed to play callout "${callout.id}": $e');
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
    final asset = _assetResolver.cached(targetId) ??
        'assets/audio/callouts/$targetId.wav';
    await player.setAsset(asset);
  }

  String? calloutAudioKey(Callout callout, DrillConfig config) {
    final customPath = localAudioPathFor(callout, config);
    if (customPath != null) return 'file:$customPath';
    if (callout.isCustom) return null;

    final targetId = callout.audioAssetAlias ?? callout.id;
    final asset = _assetResolver.cached(targetId) ??
        'assets/audio/callouts/$targetId.wav';
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

    try {
      await _setSourceForAdLib(player, slot, config, isPro: isPro);
      if (shouldAbort?.call() == true) return;
      await player.play();
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

    await player.setAsset(slot.defaultAssetPath);
  }

  Future<bool> playFirstAvailableOnCallout(
    List<String> candidates, {
    bool waitForCompletion = false,
    bool Function()? shouldAbort,
  }) async {
    final player =
        _whistlePlayer ??= _audio.createPlayer(debugLabel: 'whistle_cue');

    for (final asset in candidates) {
      try {
        await player.setAsset(asset);
        if (shouldAbort?.call() == true) return false;
        if (waitForCompletion) {
          await _playAndWaitForCompletion(
            player,
            timeout: const Duration(seconds: 2),
            shouldAbort: shouldAbort,
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

  Future<void> stopCues() async {
    await _cuePlayer?.stop();
    await _adLibPlayer?.stop();
  }

  Future<void> disposePlayers() async {
    final players = <IAudioPlayer?>[_cuePlayer, _whistlePlayer, _adLibPlayer];
    _cuePlayer = null;
    _whistlePlayer = null;
    _adLibPlayer = null;
    _preparedCueKey = null;
    _preparingCueKey = null;
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

  void clearAssetCache() => _assetResolver.clear();

  Future<void> _playAndWaitForCompletion(
    IAudioPlayer player, {
    Duration timeout = _audioCompletionTimeout,
    bool Function()? shouldAbort,
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
      if (shouldAbort?.call() == true) return;

      await completer.future.timeout(
        timeout,
        onTimeout: () {
          if (shouldAbort?.call() != true) {
            debugPrint('[audio] Playback completion timed out for $debugLabel');
          }
        },
      );
    } finally {
      await subscription.cancel();
    }
  }
}
