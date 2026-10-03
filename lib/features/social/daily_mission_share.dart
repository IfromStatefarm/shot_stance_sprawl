import 'dart:math' as math;

import '../drill/models.dart';
import '../drill/workout_presets.dart';
import 'workout_snapshot.dart';

/// Freezes today's preset into the same portable definition a friend will run.
///
/// Timed callouts are resolved once here so every recipient receives the exact
/// same mission instead of rerolling duration ranges on their device.
WorkoutSnapshot workoutSnapshotForDailyMission(
  WorkoutPreset preset, {
  math.Random? random,
}) {
  final intervalRange = _intervalRangeForDifficulty(
    preset.recommendedDifficulty,
  );
  final timedDurations = preset.resolveTimedCalloutDurations(random: random);
  final config = DrillConfig(
    totalDurationSeconds: preset.recommendedDurationSeconds,
    minIntervalSeconds: intervalRange.$1,
    maxIntervalSeconds: intervalRange.$2,
    enabledCalloutIds: Set<String>.unmodifiable(preset.calloutIds),
    calloutOverrideDurations: Map<String, int>.unmodifiable(timedDurations),
    activeWorkoutPresetId: preset.id,
  );

  return WorkoutSnapshot.fromPreset(
    preset,
    config: config,
    timedCalloutDurations: timedDurations,
  );
}

/// A mission may repeat in the catalog, so the local calendar date is part of
/// its source key. This keeps each day's relay distinct while still allowing
/// the backend to recognize repeat sends for the same mission.
String workoutSourceKeyForDailyMission(
  WorkoutPreset preset,
  DateTime missionDate,
) {
  final localDate = DateTime(
    missionDate.year,
    missionDate.month,
    missionDate.day,
  );
  final date = '${localDate.year.toString().padLeft(4, '0')}-'
      '${localDate.month.toString().padLeft(2, '0')}-'
      '${localDate.day.toString().padLeft(2, '0')}';
  return 'mission:$date:${preset.id}';
}

(double, double) _intervalRangeForDifficulty(int difficulty) {
  if (difficulty <= 3) return (3.0, 5.0);
  if (difficulty <= 6) return (2.0, 4.0);
  if (difficulty <= 8) return (1.0, 2.0);
  return (0.5, 1.5);
}
