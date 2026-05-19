import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart' hide AVAudioSessionCategory, AVAudioSessionOptions;

abstract class IAudioPlayer {
  Future<void> setAsset(String assetPath);
  Future<void> setDeviceFile(String filePath); // ADDED: For custom voice recordings
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
  Future<void> seek(Duration duration);
  
  // NEW: Stream to detect when audio finishes playing
  Stream<void> get onPlayerComplete; 
}

abstract class AudioFactory {
  IAudioPlayer createPlayer({String? debugLabel});
}

class RealAudioFactory implements AudioFactory {
  @override
  IAudioPlayer createPlayer({String? debugLabel}) {
    final player = AudioPlayer();
    player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: [
          AVAudioSessionOptions.mixWithOthers,
          AVAudioSessionOptions.defaultToSpeaker,
        ],
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ));

    // CRITICAL FIX: Force low latency mode to prevent audio lag when the camera is hogging system resources.
    player.setPlayerMode(PlayerMode.lowLatency);
    return _AudioplayersWrapper(player);
  }
}

class _AudioplayersWrapper implements IAudioPlayer {
  final AudioPlayer _inner;
  _AudioplayersWrapper(this._inner);

  @override
  Future<void> setAsset(String assetPath) async => 
      await _inner.setSource(AssetSource(assetPath.replaceFirst('assets/', '')));

  @override
  Future<void> setDeviceFile(String filePath) async => 
      await _inner.setSource(DeviceFileSource(filePath));

  @override
  Future<void> play() async => await _inner.resume();

  @override
  Future<void> stop() async => await _inner.stop();

  @override
  Future<void> dispose() async => await _inner.dispose();
  
  @override
  Future<void> seek(Duration duration) async => await _inner.seek(duration);

  // NEW: Listen to the underlying native completion event
  @override
  Stream<void> get onPlayerComplete => _inner.onPlayerComplete;
}