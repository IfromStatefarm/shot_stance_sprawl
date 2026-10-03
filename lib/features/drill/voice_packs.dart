import 'dart:convert';

import 'package:flutter/services.dart';

import 'models.dart';

class VoicePackCatalog {
  static const manifestDirectory = 'assets/audio/voice_packs/';
  static const manifestSuffix = '_manifest.json';
  static const requiredCalloutIds = <String>{
    'callout_shot',
    'callout_sprawl',
    'callout_stance',
    'callout_circle',
    'callout_down_block',
    'callout_fake',
    'callout_level_change',
    'callout_snap_down',
    'callout_high_knees',
    'callout_foot_fire',
    'callout_hand_fight',
  };
  static const requiredAdLibIds = <String>{
    'ad_lib_1',
    'ad_lib_2',
    'ad_lib_3',
    'ad_lib_4',
    'ad_lib_5',
  };

  const VoicePackCatalog();

  Future<List<VoicePack>> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(assets);
    final manifestPaths = manifest
        .listAssets()
        .where(
          (path) =>
              path.startsWith(manifestDirectory) &&
              path.endsWith(manifestSuffix),
        )
        .toList()
      ..sort();
    final bundledAssets = manifest.listAssets().toSet();

    final packs = <VoicePack>[];
    final packIds = <String>{};
    for (final path in manifestPaths) {
      final source = await assets.loadString(path);
      final pack = parseManifest(source, manifestPath: path);
      if (!packIds.add(pack.id)) {
        throw FormatException('Duplicate voice pack id "${pack.id}".');
      }
      for (final asset in _assetsFor(pack)) {
        if (!bundledAssets.contains(asset)) {
          throw FormatException('$path references an unbundled asset: $asset');
        }
      }
      packs.add(pack);
    }

    packs.sort((a, b) {
      final language = a.languageName.compareTo(b.languageName);
      return language != 0 ? language : a.name.compareTo(b.name);
    });
    return packs;
  }

  VoicePack parseManifest(
    String source, {
    String manifestPath = 'voice pack manifest',
  }) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$manifestPath must contain a JSON object.');
    }
    if (decoded['schemaVersion'] != 1) {
      throw FormatException('$manifestPath has an unsupported schemaVersion.');
    }

    final id = decoded['id'] as String? ?? '';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
      throw FormatException(
        '$manifestPath id must use lowercase letters, numbers, and underscores.',
      );
    }

    final pack = VoicePack.fromMap(id, decoded);
    if (pack.name.trim().isEmpty ||
        pack.languageCode.trim().isEmpty ||
        pack.languageName.trim().isEmpty) {
      throw FormatException('$manifestPath is missing pack metadata.');
    }
    final missingCallouts = requiredCalloutIds.difference(
      pack.calloutAssets.keys.toSet(),
    );
    final missingAdLibs = requiredAdLibIds.difference(
      pack.adLibAssets.keys.toSet(),
    );
    if (missingCallouts.isNotEmpty || missingAdLibs.isNotEmpty) {
      throw FormatException(
        '$manifestPath is incomplete. Missing callouts: '
        '${missingCallouts.join(', ')}; missing ad libs: '
        '${missingAdLibs.join(', ')}.',
      );
    }
    if (pack.whistleAsset.isEmpty) {
      throw FormatException('$manifestPath must define whistle audio.');
    }
    for (final asset in _assetsFor(pack)) {
      if (!asset.toLowerCase().endsWith('.wav')) {
        throw FormatException('$manifestPath audio must use WAV files: $asset');
      }
    }
    return pack;
  }

  Iterable<String> _assetsFor(VoicePack pack) sync* {
    yield* pack.calloutAssets.values;
    yield* pack.adLibAssets.values;
    yield pack.whistleAsset;
  }
}
