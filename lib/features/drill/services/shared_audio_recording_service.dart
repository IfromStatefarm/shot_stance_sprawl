import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

import '../../../core/local_file_storage.dart';

class SharedAudioRecordingService {
  final AudioRecorder _recorder;
  final AudioPlayer _player;

  SharedAudioRecordingService({
    AudioRecorder? recorder,
    AudioPlayer? player,
  })  : _recorder = recorder ?? AudioRecorder(),
        _player = player ?? AudioPlayer();

  void configurePreviewPlayer() {
    unawaited(_player.setPlayerMode(PlayerMode.mediaPlayer));
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
  }

  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  Future<String> timestampedDocumentAudioPath(String prefix) async {
    return LocalStoragePaths.timestampedDocumentAudioPath(prefix);
  }

  Future<void> startDefaultRecording(String path) {
    return _recorder.start(const RecordConfig(), path: path);
  }

  Future<void> startAacRecording(String path) {
    return _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
  }

  Future<String?> stopRecording() {
    return _recorder.stop();
  }

  Future<void> playDeviceFile(String path) {
    return _player.play(DeviceFileSource(path));
  }

  Future<void> playPreviewPath(String path) async {
    await stopPlayer();
    if (path.startsWith('assets/')) {
      await _player.play(AssetSource(path.replaceFirst('assets/', '')));
      return;
    }
    await playDeviceFile(path);
  }

  Future<void> stopPlayer() {
    return _player.stop();
  }

  Future<void> deleteFileIfExists(String path, {String? debugLabel}) async {
    await LocalFileStorage.deleteLocalFileIfExists(
      path,
      debugLabel: debugLabel,
    );
  }

  void dispose() {
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
  }
}
