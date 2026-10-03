import 'dart:math' as math;

import 'package:flutter/foundation.dart';

part 'data/workout_preset_catalog.dart';

enum WorkoutPresetCategory {
  quick,
  offense,
  defense,
  handfight,
  conditioning,
  matchPrep,
  beginner,
}

extension WorkoutPresetCategoryText on WorkoutPresetCategory {
  String label({required bool isEs}) {
    switch (this) {
      case WorkoutPresetCategory.quick:
        return isEs ? 'Rapidos' : 'Quick';
      case WorkoutPresetCategory.offense:
        return isEs ? 'Ataque' : 'Offense';
      case WorkoutPresetCategory.defense:
        return isEs ? 'Defensa' : 'Defense';
      case WorkoutPresetCategory.handfight:
        return isEs ? 'Manos' : 'Handfight';
      case WorkoutPresetCategory.conditioning:
        return isEs ? 'Condicion' : 'Conditioning';
      case WorkoutPresetCategory.matchPrep:
        return isEs ? 'Combate' : 'Match Prep';
      case WorkoutPresetCategory.beginner:
        return isEs ? 'Principiante' : 'Beginner';
    }
  }
}

@immutable
class WorkoutPreset {
  final String id;
  final String titleEn;
  final String titleEs;
  final WorkoutPresetCategory category;
  final List<String> calloutIds;
  final int minMinutes;
  final int maxMinutes;
  final int minDifficulty;
  final int maxDifficulty;
  final String purposeEn;
  final String purposeEs;
  final bool featured;
  final Map<String, WorkoutPresetTimedCallout> timedCalloutDurations;

  const WorkoutPreset({
    required this.id,
    required this.titleEn,
    required this.titleEs,
    required this.category,
    required this.calloutIds,
    required this.minMinutes,
    required this.maxMinutes,
    required this.minDifficulty,
    required this.maxDifficulty,
    required this.purposeEn,
    required this.purposeEs,
    this.featured = false,
    this.timedCalloutDurations = const {},
  });

  String title({required bool isEs}) => isEs ? titleEs : titleEn;

  String purpose({required bool isEs}) => isEs ? purposeEs : purposeEn;

  int get recommendedMinutes {
    final rounded = ((minMinutes + maxMinutes) / 2).round();
    return rounded.clamp(minMinutes, maxMinutes).toInt();
  }

  int get recommendedDurationSeconds => recommendedMinutes * 60;

  int get recommendedDifficulty {
    final rounded = ((minDifficulty + maxDifficulty) / 2).round();
    return rounded.clamp(minDifficulty, maxDifficulty).toInt();
  }

  String durationLabel({required bool isEs}) {
    if (minMinutes == maxMinutes) return '$minMinutes min';
    return '$minMinutes-$maxMinutes min';
  }

  String difficultyLabel({required bool isEs}) {
    if (minDifficulty == maxDifficulty) return '$minDifficulty';
    return '$minDifficulty-$maxDifficulty';
  }

  String calloutListLabel({required bool isEs}) {
    return calloutIds.map((id) => calloutNameForId(id, isEs: isEs)).join(', ');
  }

  Map<String, int> resolveTimedCalloutDurations({math.Random? random}) {
    final source = random ?? math.Random();
    return timedCalloutDurations.map(
      (id, duration) => MapEntry(id, duration.resolve(source)),
    );
  }
}

@immutable
class WorkoutPresetTimedCallout {
  final int minSeconds;
  final int maxSeconds;

  const WorkoutPresetTimedCallout(this.minSeconds, [int? maxSeconds])
      : maxSeconds = maxSeconds ?? minSeconds,
        assert(minSeconds > 0),
        assert((maxSeconds ?? minSeconds) >= minSeconds);

  int resolve(math.Random random) {
    if (minSeconds == maxSeconds) return minSeconds;
    return minSeconds + random.nextInt(maxSeconds - minSeconds + 1);
  }
}

String workoutShareCode(WorkoutPreset preset) {
  final idPart = preset.id.replaceAll('_', '-').toUpperCase();
  return 'SG-$idPart-${preset.recommendedMinutes}M-D${preset.recommendedDifficulty}';
}

String workoutSharingText(
  WorkoutPreset preset, {
  required bool isEs,
}) {
  final code = workoutShareCode(preset);
  if (isEs) {
    return [
      'Snap & Go Workout',
      'Codigo: $code',
      'Workout: ${preset.title(isEs: true)}',
      'Duracion: ${preset.durationLabel(isEs: true)}',
      'Dificultad: ${preset.difficultyLabel(isEs: true)}',
      'Movimientos: ${preset.calloutListLabel(isEs: true)}',
      '',
      'Abre Snap & Go, toca Workouts y prueba este workout.',
    ].join('\n');
  }

  return [
    'Snap & Go Workout',
    'Code: $code',
    'Workout: ${preset.title(isEs: false)}',
    'Duration: ${preset.durationLabel(isEs: false)}',
    'Difficulty: ${preset.difficultyLabel(isEs: false)}',
    'Moves: ${preset.calloutListLabel(isEs: false)}',
    '',
    'Open Snap & Go, tap Workouts, and try this workout.',
  ].join('\n');
}

String calloutNameForId(String id, {required bool isEs}) {
  switch (id) {
    case 'stance':
      return isEs ? 'Postura' : 'Stance';
    case 'circle':
      return isEs ? 'Circulo' : 'Circle';
    case 'fake':
      return isEs ? 'Finta' : 'Fake';
    case 'level_change':
      return isEs ? 'Cambio de nivel' : 'Level change';
    case 'shot':
      return isEs ? 'Tiro' : 'Shot';
    case 'snap_down':
      return isEs ? 'Jalon' : 'Snap down';
    case 'sprawl':
      return 'Sprawl';
    case 'down_block':
      return isEs ? 'Bloqueo abajo' : 'Down block';
    case 'hand_fight':
      return isEs ? 'Manos' : 'Handfight';
    case 'foot_fire':
      return isEs ? 'Pies rapidos' : 'Foot fire';
    case 'high_knees':
      return isEs ? 'Rodillas altas' : 'High knees';
    default:
      return id;
  }
}

WorkoutPreset workoutPresetForDate(DateTime date) {
  return allWorkoutPresets[_dailyPresetIndex(date)];
}

List<WorkoutPreset> workoutPresetsForCategory(WorkoutPresetCategory category) {
  return allWorkoutPresets
      .where((preset) => preset.category == category)
      .toList(growable: false);
}

final featuredWorkoutPresets = allWorkoutPresets
    .where((preset) => preset.featured)
    .toList(growable: false);

int _dailyPresetIndex(DateTime date) {
  final today = DateTime(date.year, date.month, date.day);
  final length = allWorkoutPresets.length;
  var index = _stableDateHash(today) % length;

  final yesterday = today.subtract(const Duration(days: 1));
  final previousIndex = _stableDateHash(yesterday) % length;
  if (index == previousIndex) {
    index = (index + 1) % length;
  }

  return index;
}

int _stableDateHash(DateTime date) {
  var hash = 5381;
  hash = ((hash << 5) + hash) ^ date.year;
  hash = ((hash << 5) + hash) ^ date.month;
  hash = ((hash << 5) + hash) ^ date.day;
  return hash.abs();
}
