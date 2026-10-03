import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shot_stance_sprawl/features/drill/providers.dart';
import 'package:shot_stance_sprawl/features/social/social.dart';

void main() {
  test('preset timed callout duration ranges resolve inclusively', () {
    const duration = WorkoutPresetTimedCallout(30, 45);

    expect(duration.resolve(const _FixedRandom(0)), 30);
    expect(duration.resolve(const _FixedRandom(15)), 45);
  });

  test('preset timed callout durations only target enabled callouts', () {
    for (final preset in [...allWorkoutPresets, ...overtimeWorkoutPresets]) {
      expect(
        preset.timedCalloutDurations.keys,
        everyElement(isIn(preset.calloutIds)),
        reason: '${preset.titleEn} has a timed duration for a disabled callout',
      );
    }
  });

  test('applying a preset replaces stale standard timed callout durations',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sharedPrefsProvider.future);

    final notifier = container.read(drillConfigProvider.notifier);
    notifier.setCalloutDuration('stance', 45);
    notifier.setCalloutDuration('foot_fire', 45);

    final preset = allWorkoutPresets.firstWhere(
      (preset) => preset.id == 'shot_hunter',
    );
    notifier.applyWorkoutPreset(
      preset,
      totalDurationSeconds: preset.recommendedDurationSeconds,
      minIntervalSeconds: 2,
      maxIntervalSeconds: 4,
    );

    final config = container.read(drillConfigProvider);
    expect(config.enabledCalloutIds, preset.calloutIds.toSet());
    expect(config.calloutOverrideDurations['stance'], 15);
    expect(config.calloutOverrideDurations.containsKey('foot_fire'), isFalse);
    expect(config.activeWorkoutPresetId, 'shot_hunter');
  });

  test('default overtime preset quick-starts Sudden Victory', () {
    expect(defaultOvertimeWorkoutPreset.id, 'overtime_sudden_victory');
    expect(defaultOvertimeWorkoutPreset.recommendedDurationSeconds, 180);
    expect(defaultOvertimeWorkoutPreset.recommendedDifficulty, 9);
  });

  test('preset sharing copy uses neutral workout language', () {
    final preset = allWorkoutPresets.first;
    final english = workoutSharingText(preset, isEs: false);
    final spanish = workoutSharingText(preset, isEs: true);

    expect(english, contains('Snap & Go Workout'));
    expect(english.toLowerCase(), isNot(contains('assignment')));
    expect(spanish.toLowerCase(), isNot(contains('assignment')));
    expect(workoutShareCode(preset), startsWith('SG-'));
  });

  test('daily mission sharing freezes the recommended preset configuration',
      () {
    final preset = allWorkoutPresets.first;
    final snapshot = workoutSnapshotForDailyMission(
      preset,
      random: const _FixedRandom(0),
    );

    expect(snapshot.presetId, preset.id);
    expect(snapshot.durationSeconds, preset.recommendedDurationSeconds);
    expect(snapshot.difficulty, preset.recommendedDifficulty);
    expect(snapshot.enabledCalloutIds, preset.calloutIds);
    expect(
      workoutSourceKeyForDailyMission(preset, DateTime(2026, 8, 10, 23, 59)),
      'mission:2026-08-10:${preset.id}',
    );
  });

  test('applying a free preset can disable recording without shortening it',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sharedPrefsProvider.future);

    final notifier = container.read(drillConfigProvider.notifier);
    notifier.setVideoEnabled(true);

    final preset = allWorkoutPresets.firstWhere(
      (preset) => preset.id == 'shot_hunter',
    );
    notifier.applyWorkoutPreset(
      preset,
      totalDurationSeconds: preset.recommendedDurationSeconds,
      minIntervalSeconds: 2,
      maxIntervalSeconds: 4,
      videoEnabled: false,
    );

    final config = container.read(drillConfigProvider);
    expect(config.videoEnabled, isFalse);
    expect(config.totalDurationSeconds, preset.recommendedDurationSeconds);
    expect(config.totalDurationSeconds, greaterThan(60));
  });
}

class _FixedRandom implements math.Random {
  final int value;

  const _FixedRandom(this.value);

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => value % max;
}
