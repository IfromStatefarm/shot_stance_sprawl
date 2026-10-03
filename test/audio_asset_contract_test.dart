import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _expectedAudioAssets = <String>{
  'assets/audio/ad_libs/ad_lib_1.wav',
  'assets/audio/ad_libs/ad_lib_2.wav',
  'assets/audio/ad_libs/ad_lib_3.wav',
  'assets/audio/ad_libs/ad_lib_4.wav',
  'assets/audio/ad_libs/ad_lib_5.wav',
  'assets/audio/callouts/callout_circle.wav',
  'assets/audio/callouts/callout_down_block.wav',
  'assets/audio/callouts/callout_fake.wav',
  'assets/audio/callouts/callout_foot_fire.wav',
  'assets/audio/callouts/callout_hand_fight.wav',
  'assets/audio/callouts/callout_high_knees.wav',
  'assets/audio/callouts/callout_level_change.wav',
  'assets/audio/callouts/callout_shot.wav',
  'assets/audio/callouts/callout_snap_down.wav',
  'assets/audio/callouts/callout_sprawl.wav',
  'assets/audio/callouts/callout_stance.wav',
  'assets/audio/callouts/whistle.wav',
};

void main() {
  test('every committed .wav has a RIFF/WAVE header and is not MP3 data', () {
    final wavFiles = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.wav'))
        .toList();

    expect(wavFiles, isNotEmpty);
    for (final file in wavFiles) {
      final bytes = file.readAsBytesSync();
      final label = file.path.replaceAll('\\', '/');

      expect(bytes.length, greaterThanOrEqualTo(12),
          reason: '$label is too short to contain a WAV header');
      expect(_hasMp3Signature(bytes), isFalse,
          reason: '$label contains MP3 data disguised with a .wav extension');
      expect(_hasRiffWaveHeader(bytes), isTrue,
          reason: '$label must start with RIFF and declare WAVE');
    }
  });

  test('asset-header guard rejects common MP3 signatures', () {
    expect(
      _hasMp3Signature(Uint8List.fromList('ID3fake'.codeUnits)),
      isTrue,
    );
    expect(
      _hasMp3Signature(Uint8List.fromList([0xff, 0xfb, 0x90, 0x64])),
      isTrue,
    );
    expect(
      _hasRiffWaveHeader(
        Uint8List.fromList([
          ...'RIFF'.codeUnits,
          0,
          0,
          0,
          0,
          ...'WAVE'.codeUnits,
        ]),
      ),
      isTrue,
    );
  });

  test('bundled drill audio uses the normalized WAV contract', () {
    final files = Directory('assets/audio')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.wav'))
        .toList();
    final paths = files.map((file) => file.path.replaceAll('\\', '/')).toSet();

    expect(paths, containsAll(_expectedAudioAssets));

    for (final file in files) {
      final wav = _readWav(file);
      final label = file.path.replaceAll('\\', '/');

      expect(wav.audioFormat, 1, reason: '$label must use PCM encoding');
      expect(wav.channels, 1, reason: '$label must be mono');
      expect(wav.sampleRate, 44100, reason: '$label must use 44.1 kHz');
      expect(wav.bitsPerSample, 16, reason: '$label must use 16-bit samples');
      expect(wav.duration.inMilliseconds, inInclusiveRange(200, 2000),
          reason: '$label should be an edge-trimmed short cue');

      final peakRatio = wav.peakAmplitude / 32768;
      final peakDb = 20 * math.log(peakRatio) / math.ln10;
      expect(peakDb, inInclusiveRange(-3.2, -2.8),
          reason: '$label should be peak-normalized to -3 dBFS');
      expect(wav.firstSample.abs(), lessThanOrEqualTo(32),
          reason: '$label should fade in cleanly');
      expect(wav.lastSample.abs(), lessThanOrEqualTo(32),
          reason: '$label should fade out cleanly');
    }
  });
}

bool _hasRiffWaveHeader(Uint8List bytes) {
  if (bytes.length < 12) return false;
  return String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE';
}

bool _hasMp3Signature(Uint8List bytes) {
  if (bytes.length >= 3 && String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3') {
    return true;
  }
  return bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
}

_WavInfo _readWav(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  String chunkId(int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));

  expect(bytes.length, greaterThanOrEqualTo(44),
      reason: '${file.path} is too short');
  expect(chunkId(0), 'RIFF', reason: '${file.path} has a mismatched file type');
  expect(chunkId(8), 'WAVE', reason: '${file.path} is not a WAV file');

  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? sampleDataOffset;
  int? sampleDataLength;
  var offset = 12;

  while (offset + 8 <= bytes.length) {
    final id = chunkId(offset);
    final size = data.getUint32(offset + 4, Endian.little);
    final contentOffset = offset + 8;
    expect(contentOffset + size, lessThanOrEqualTo(bytes.length),
        reason: '${file.path} contains a truncated $id chunk');

    if (id == 'fmt ') {
      expect(size, greaterThanOrEqualTo(16));
      audioFormat = data.getUint16(contentOffset, Endian.little);
      channels = data.getUint16(contentOffset + 2, Endian.little);
      sampleRate = data.getUint32(contentOffset + 4, Endian.little);
      bitsPerSample = data.getUint16(contentOffset + 14, Endian.little);
    } else if (id == 'data') {
      sampleDataOffset = contentOffset;
      sampleDataLength = size;
    }

    offset = contentOffset + size + (size.isOdd ? 1 : 0);
  }

  expect(audioFormat, isNotNull, reason: '${file.path} has no format chunk');
  expect(sampleDataOffset, isNotNull,
      reason: '${file.path} has no sample data');
  expect(sampleDataLength, isNotNull,
      reason: '${file.path} has no sample data');
  final format = audioFormat!;
  final channelCount = channels!;
  final rate = sampleRate!;
  final sampleBits = bitsPerSample!;
  final samplesOffset = sampleDataOffset!;
  final samplesLength = sampleDataLength!;
  expect(samplesLength, greaterThan(0), reason: '${file.path} is silent');
  expect(samplesLength % 2, 0, reason: '${file.path} has a partial sample');

  var peak = 0;
  var firstSample = 0;
  var lastSample = 0;
  for (var position = samplesOffset;
      position < samplesOffset + samplesLength;
      position += 2) {
    final sample = data.getInt16(position, Endian.little);
    if (position == samplesOffset) firstSample = sample;
    lastSample = sample;
    peak = math.max(peak, sample.abs());
  }

  final bytesPerSecond = rate * channelCount * (sampleBits ~/ 8);
  return _WavInfo(
    audioFormat: format,
    channels: channelCount,
    sampleRate: rate,
    bitsPerSample: sampleBits,
    duration: Duration(
      microseconds:
          (samplesLength * Duration.microsecondsPerSecond) ~/ bytesPerSecond,
    ),
    peakAmplitude: peak,
    firstSample: firstSample,
    lastSample: lastSample,
  );
}

class _WavInfo {
  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final Duration duration;
  final int peakAmplitude;
  final int firstSample;
  final int lastSample;

  const _WavInfo({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.duration,
    required this.peakAmplitude,
    required this.firstSample,
    required this.lastSample,
  });
}
