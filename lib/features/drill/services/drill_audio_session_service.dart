import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

typedef ConfigureAudioSession = Future<void> Function(
  AudioSessionConfiguration configuration,
);
typedef RouteAudioToSpeaker = Future<void> Function();

/// Owns the single app-wide audio-session configuration used by a drill.
///
/// Audio plugins can change the native session while they initialize, so this
/// service is called only after the camera and cue players are ready. Forced
/// configuration is used after recording starts or stops because the camera
/// plugin may have changed the native session at those boundaries.
class DrillAudioSessionService {
  final ConfigureAudioSession _configure;
  final RouteAudioToSpeaker _routeToSpeaker;

  Future<void> _configurationTail = Future.value();
  bool? _configuredForVideo;

  DrillAudioSessionService({
    ConfigureAudioSession? configure,
    RouteAudioToSpeaker? routeToSpeaker,
  })  : _configure = configure ?? _configurePlatformSession,
        _routeToSpeaker = routeToSpeaker ?? _routePlatformAudioToSpeaker;

  Future<void> configureForDrill({
    required bool videoEnabled,
    bool force = false,
  }) async {
    if (!force && _configuredForVideo == videoEnabled) return;

    final configuration = configurationFor(videoEnabled: videoEnabled);
    final operation = _configurationTail.then((_) async {
      await _configure(configuration);
      if (videoEnabled) {
        await _routeToSpeaker();
      }
    });
    _configurationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );

    await operation;
    _configuredForVideo = videoEnabled;
  }

  static AudioSessionConfiguration configurationFor({
    required bool videoEnabled,
  }) {
    if (videoEnabled) {
      return AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.videoRecording,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      );
    }

    return const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    );
  }

  static Future<void> _configurePlatformSession(
    AudioSessionConfiguration configuration,
  ) async {
    final session = await AudioSession.instance;
    await session.configure(configuration);
  }

  static Future<void> _routePlatformAudioToSpeaker() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await AndroidAudioManager().setSpeakerphoneOn(true);
    }
  }
}
