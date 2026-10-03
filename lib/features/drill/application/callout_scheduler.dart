import 'dart:math' as math;

import '../intervals.dart';
import '../models.dart';

class CalloutScheduler {
  final math.Random _random;
  final IntervalStrategy _intervals;

  CalloutScheduler({
    math.Random? random,
    IntervalStrategy? intervalStrategy,
  })  : _random = random ?? math.Random(),
        _intervals = intervalStrategy ?? UniformIntervalStrategy();

  List<Callout> selectedCalloutsFor(
    DrillConfig config,
    List<Callout> allCallouts,
  ) {
    return allCallouts
        .where((callout) => config.enabledCalloutIds.contains(callout.id))
        .toList();
  }

  double nextCalloutDelay(DrillConfig config) {
    return isGableMode(config)
        ? 0
        : _intervals.next(
            config.minIntervalSeconds,
            config.maxIntervalSeconds,
          );
  }

  bool isGableMode(DrillConfig config) {
    return (config.minIntervalSeconds - 0.5).abs() < 0.1 &&
        (config.maxIntervalSeconds - 1.5).abs() < 0.1;
  }

  Callout pickCallout(
    List<Callout> options, {
    String? lastCalloutId,
  }) {
    if (options.isEmpty) {
      throw ArgumentError.value(options, 'options', 'Cannot be empty.');
    }
    if (options.length == 1) return options.first;

    Callout pick;
    var guard = 0;
    do {
      pick = options[_random.nextInt(options.length)];
      guard++;
    } while (pick.id == lastCalloutId && guard < 10);

    return pick;
  }

  T pickOne<T>(List<T> options) {
    if (options.isEmpty) {
      throw ArgumentError.value(options, 'options', 'Cannot be empty.');
    }
    if (options.length == 1) return options.first;
    return options[_random.nextInt(options.length)];
  }

  String preparationKey({
    required DrillConfig config,
    required List<Callout> allCallouts,
    required bool isPro,
  }) {
    final enabledIds = config.enabledCalloutIds.toList()..sort();
    final customPaths = config.customAudioPaths.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final selectedAudio = selectedCalloutsFor(config, allCallouts)
        .map(
          (callout) => [
            callout.id,
            callout.audioAssetAlias ?? '',
            config.customAudioPaths[callout.id] ?? callout.audioUrl ?? '',
          ].join(':'),
        )
        .join('|');

    return [
      isPro ? 'pro' : 'free',
      config.videoEnabled ? 'video' : 'no-video',
      config.totalDurationSeconds,
      config.minIntervalSeconds,
      config.maxIntervalSeconds,
      config.adLibsEnabled,
      config.voicePackId,
      enabledIds.join(','),
      customPaths.map((entry) => '${entry.key}:${entry.value}').join('|'),
      selectedAudio,
    ].join(';');
  }
}
