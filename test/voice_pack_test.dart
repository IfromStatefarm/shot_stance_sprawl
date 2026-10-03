import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/drill/models.dart';
import 'package:shot_stance_sprawl/features/drill/services/drill_audio_service.dart';
import 'package:shot_stance_sprawl/features/drill/voice_packs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoicePackCatalog', () {
    test('parses every bundled pack and every mapped asset exists', () {
      final manifests = Directory(VoicePackCatalog.manifestDirectory)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith(VoicePackCatalog.manifestSuffix))
          .toList();
      expect(manifests, isNotEmpty);

      for (final manifest in manifests) {
        final path = manifest.path.replaceAll('\\', '/');
        final pack = const VoicePackCatalog().parseManifest(
          manifest.readAsStringSync(),
          manifestPath: path,
        );

        expect(
          pack.calloutAssets.keys.toSet(),
          VoicePackCatalog.requiredCalloutIds,
        );
        expect(
          pack.adLibAssets.keys.toSet(),
          VoicePackCatalog.requiredAdLibIds,
        );
        for (final asset in <String>{
          ...pack.calloutAssets.values,
          ...pack.adLibAssets.values,
          pack.whistleAsset,
        }) {
          expect(File(asset).existsSync(), isTrue, reason: '$asset is missing');
        }
      }
    });

    test('discovers the bundled default pack through Flutter assets', () async {
      final packs = await const VoicePackCatalog().load();

      expect(
        packs.any((pack) => pack.id == DrillConfig.defaultVoicePackId),
        isTrue,
      );
    });

    test('rejects an incomplete pack before it can reach the UI', () {
      expect(
        () => const VoicePackCatalog().parseManifest('''
          {
            "schemaVersion": 1,
            "id": "coach_es",
            "name": "Coach",
            "languageCode": "es",
            "languageName": "Español",
            "callouts": {"callout_shot": "shot.wav"},
            "adLibs": {},
            "whistle": "whistle.wav"
          }
        '''),
        throwsFormatException,
      );
    });
  });

  test('resolver uses the selected pack asset paths', () async {
    const pack = VoicePack(
      id: 'coach_es',
      name: 'Coach',
      languageCode: 'es',
      languageName: 'Español',
      calloutAssets: {
        'callout_shot': 'assets/audio/voice_packs/coach_es_shot.wav',
      },
      adLibAssets: {
        'ad_lib_1': 'assets/audio/voice_packs/coach_es_ad_lib_1.wav',
      },
      whistleAsset: 'assets/audio/voice_packs/coach_es_whistle.wav',
    );
    final resolver = CalloutAudioAssetResolver(
      assetExists: (_) async => true,
      voicePackLoader: (id) async => id == pack.id ? pack : null,
    );

    expect(
      await resolver.resolve(
        'callout_shot',
        voicePackId: 'coach_es',
      ),
      'assets/audio/voice_packs/coach_es_shot.wav',
    );
    expect(
      await resolver.resolveAdLib('coach_es', 'ad_lib_1'),
      'assets/audio/voice_packs/coach_es_ad_lib_1.wav',
    );
    expect(
      await resolver.resolveWhistle('coach_es'),
      'assets/audio/voice_packs/coach_es_whistle.wav',
    );
  });

  test('drill config persists the selected voice pack', () {
    const config = DrillConfig(voicePackId: 'coach_es');
    final restored = DrillConfig.fromJson(config.toJson());

    expect(restored.voicePackId, 'coach_es');
    expect(
      DrillConfig.fromMap(const {}).voicePackId,
      DrillConfig.defaultVoicePackId,
    );
  });
}
