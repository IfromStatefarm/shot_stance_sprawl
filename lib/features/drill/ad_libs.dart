import 'models.dart';

class AdLibSlot {
  final String id;
  final int number;
  final String label;
  final String defaultAssetPath;

  const AdLibSlot({
    required this.id,
    required this.number,
    required this.label,
    required this.defaultAssetPath,
  });

  bool isUnlocked({required bool isPro}) => isPro || number == 1;
  bool canCustomize({required bool isPro}) => isPro;

  String? customPath(DrillConfig config, {required bool isPro}) {
    if (!canCustomize(isPro: isPro)) return null;

    final path = config.customAdLibAudioPaths[id];
    if (path == null || path.isEmpty) return null;
    return path;
  }

  String activePath(DrillConfig config, {required bool isPro}) =>
      customPath(config, isPro: isPro) ?? defaultAssetPath;
}

class AdLibSlots {
  static const all = <AdLibSlot>[
    AdLibSlot(
      id: 'ad_lib_1',
      number: 1,
      label: 'Ad Lib 1',
      defaultAssetPath: 'assets/audio/ad_libs/Ad_lib1.mp3',
    ),
    AdLibSlot(
      id: 'ad_lib_2',
      number: 2,
      label: 'Ad Lib 2',
      defaultAssetPath: 'assets/audio/ad_libs/Ad_lib2.mp3',
    ),
    AdLibSlot(
      id: 'ad_lib_3',
      number: 3,
      label: 'Ad Lib 3',
      defaultAssetPath: 'assets/audio/ad_libs/Ad_lib3.mp3',
    ),
    AdLibSlot(
      id: 'ad_lib_4',
      number: 4,
      label: 'Ad Lib 4',
      defaultAssetPath: 'assets/audio/ad_libs/Ad_lib4.mp3',
    ),
    AdLibSlot(
      id: 'ad_lib_5',
      number: 5,
      label: 'Ad Lib 5',
      defaultAssetPath: 'assets/audio/ad_libs/Ad_lib5.mp3',
    ),
  ];

  static List<AdLibSlot> unlocked({required bool isPro}) {
    return all.where((slot) => slot.isUnlocked(isPro: isPro)).toList();
  }
}
