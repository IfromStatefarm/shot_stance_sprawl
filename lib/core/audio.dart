import 'package:audioplayers/audioplayers.dart';

abstract class IAudioPlayer {
  Future<void> initialize();
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
  Future<void> _initializationTail = Future.value();

  @override
  IAudioPlayer createPlayer({String? debugLabel}) {
    final player = AudioPlayer();
    final ready = _initializationTail.then((_) async {
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setReleaseMode(ReleaseMode.stop);
    });
    _initializationTail = ready.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return _AudioplayersWrapper(player, ready);
  }
}

class _AudioplayersWrapper implements IAudioPlayer {
  final AudioPlayer _inner;
  final Future<void> _ready;
  _AudioplayersWrapper(this._inner, this._ready);

  @override
  Future<void> initialize() => _ready;

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
