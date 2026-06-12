import 'package:audioplayers/audioplayers.dart';

abstract class IAudioPlayer {
  Future<void> setAsset(String assetPath);
  Future<void> setDeviceFile(String filePath);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
  Future<void> seek(Duration duration);
  Stream<void> get onPlayerComplete;
}

abstract class AudioFactory {
  IAudioPlayer createPlayer({String? debugLabel});
}

class RealAudioFactory implements AudioFactory {
  @override
  IAudioPlayer createPlayer({String? debugLabel}) {
    final player = AudioPlayer();
    final ready = Future.wait([
      player.setPlayerMode(PlayerMode.mediaPlayer),
      player.setReleaseMode(ReleaseMode.stop),
      player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            usageType: AndroidUsageType.media,
            contentType: AndroidContentType.speech,
          ),
        ),
      ),
    ]);
    return _AudioplayersWrapper(player, ready);
  }
}

class _AudioplayersWrapper implements IAudioPlayer {
  final AudioPlayer _inner;
  final Future<void> _ready;
  _AudioplayersWrapper(this._inner, this._ready);

  @override
  Future<void> setAsset(String assetPath) async {
    await _ready;
    await _inner.stop();
    await _inner.setSource(
      AssetSource(assetPath.replaceFirst('assets/', '')),
    );
  }

  @override
  Future<void> setDeviceFile(String filePath) async {
    await _ready;
    await _inner.stop();
    await _inner.setSource(DeviceFileSource(filePath));
  }

  @override
  Future<void> play() async {
    await _ready;
    await _inner.resume();
  }

  @override
  Future<void> stop() async {
    await _ready;
    await _inner.stop();
  }

  @override
  Future<void> dispose() async => await _inner.dispose();

  @override
  Future<void> seek(Duration duration) async {
    await _ready;
    await _inner.seek(duration);
  }

  @override
  Stream<void> get onPlayerComplete => _inner.onPlayerComplete;
}
