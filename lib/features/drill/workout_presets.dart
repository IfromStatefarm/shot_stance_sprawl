import 'dart:math' as math;

import 'package:flutter/foundation.dart';

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

String coachAssignmentCode(WorkoutPreset preset) {
  final idPart = preset.id.replaceAll('_', '-').toUpperCase();
  return 'SG-$idPart-${preset.recommendedMinutes}M-D${preset.recommendedDifficulty}';
}

String coachAssignmentText(
  WorkoutPreset preset, {
  required bool isEs,
}) {
  final code = coachAssignmentCode(preset);
  if (isEs) {
    return [
      'Snap & Go Coach Assignment',
      'Codigo: $code',
      'Workout: ${preset.title(isEs: true)}',
      'Duracion: ${preset.durationLabel(isEs: true)}',
      'Dificultad: ${preset.difficultyLabel(isEs: true)}',
      'Movimientos: ${preset.calloutListLabel(isEs: true)}',
      '',
      'Abre Snap & Go, toca Workouts, y corre este assignment.',
    ].join('\n');
  }

  return [
    'Snap & Go Coach Assignment',
    'Code: $code',
    'Workout: ${preset.title(isEs: false)}',
    'Duration: ${preset.durationLabel(isEs: false)}',
    'Difficulty: ${preset.difficultyLabel(isEs: false)}',
    'Moves: ${preset.calloutListLabel(isEs: false)}',
    '',
    'Open Snap & Go, tap Workouts, and run this assignment.',
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

const overtimeWorkoutPresets = <WorkoutPreset>[
  WorkoutPreset(
    id: 'overtime_sudden_victory',
    titleEn: 'Sudden Victory',
    titleEs: 'Victoria Subita',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'shot', 'sprawl', 'circle'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Full neutral-position overtime pace.',
    purposeEs: 'Ritmo de tiempo extra en posicion neutral.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_last_takedown_wins',
    titleEn: 'Last Takedown Wins',
    titleEs: 'Ultimo Derribe Gana',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'fake', 'level_change', 'shot'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Offensive push when the match is tied.',
    purposeEs: 'Empuje ofensivo cuando el combate esta empatado.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_no_easy_two',
    titleEn: 'No Easy Two',
    titleEs: 'Nada Facil',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'sprawl', 'down_block', 'circle'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Defensive wall when protecting a lead.',
    purposeEs: 'Muro defensivo para proteger la ventaja.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_third_period_legs',
    titleEn: 'Third Period Legs',
    titleEs: 'Piernas del Tercer Periodo',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'high_knees', 'foot_fire', 'sprawl'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 9,
    maxDifficulty: 10,
    purposeEn: 'Hard conditioning under fatigue.',
    purposeEs: 'Condicion dura bajo fatiga.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'high_knees': WorkoutPresetTimedCallout(15),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_gas_tank_check',
    titleEn: 'Gas Tank Check',
    titleEs: 'Prueba del Tanque',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['high_knees', 'foot_fire', 'stance', 'circle'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Tests whether the wrestler can keep moving tired.',
    purposeEs: 'Prueba si puedes seguir moviendote cansado.',
    timedCalloutDurations: {
      'high_knees': WorkoutPresetTimedCallout(15),
      'foot_fire': WorkoutPresetTimedCallout(15),
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_sprawl_storm',
    titleEn: 'Sprawl Storm',
    titleEs: 'Tormenta de Sprawl',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'sprawl', 'circle', 'down_block'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 9,
    maxDifficulty: 10,
    purposeEn: 'Fast defensive reactions.',
    purposeEs: 'Reacciones defensivas rapidas.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
    },
  ),
  WorkoutPreset(
    id: 'overtime_heavy_hands_overtime',
    titleEn: 'Heavy Hands Overtime',
    titleEs: 'Manos Pesadas Extra',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['hand_fight', 'snap_down', 'circle', 'level_change'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Handfight pressure and snap-down attacks.',
    purposeEs: 'Presion de manos y ataques con snap down.',
    timedCalloutDurations: {
      'hand_fight': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_snap_and_attack',
    titleEn: 'Snap & Attack',
    titleEs: 'Snap y Ataca',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['hand_fight', 'snap_down', 'fake', 'shot'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Creates offense from hand control.',
    purposeEs: 'Crea ataque desde control de manos.',
    timedCalloutDurations: {
      'hand_fight': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_motion_mayhem',
    titleEn: 'Motion Mayhem',
    titleEs: 'Caos de Movimiento',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'circle', 'fake', 'level_change'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 9,
    maxDifficulty: 10,
    purposeEn: 'Fast motion, setups, and level changes.',
    purposeEs: 'Movimiento rapido, setups y cambios de nivel.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
    },
  ),
  WorkoutPreset(
    id: 'overtime_chain_shot_sprint',
    titleEn: 'Chain Shot Sprint',
    titleEs: 'Sprint de Tiros',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['fake', 'level_change', 'shot', 'circle'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Forces repeated attacks and quick resets.',
    purposeEs: 'Fuerza ataques repetidos y resets rapidos.',
  ),
  WorkoutPreset(
    id: 'overtime_defense_to_reattack',
    titleEn: 'Defense to Re-Attack',
    titleEs: 'Defensa a Contraataque',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['sprawl', 'circle', 'level_change', 'shot'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Teaches defense into offense.',
    purposeEs: 'Convierte defensa en ataque.',
  ),
  WorkoutPreset(
    id: 'overtime_final_whistle',
    titleEn: 'Final Whistle',
    titleEs: 'Silbato Final',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'shot', 'sprawl', 'high_knees', 'foot_fire'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 10,
    maxDifficulty: 10,
    purposeEn: 'Hardest all-around overtime finisher.',
    purposeEs: 'Finalizador completo de tiempo extra.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
      'high_knees': WorkoutPresetTimedCallout(15),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_one_more_shot',
    titleEn: 'One More Shot',
    titleEs: 'Un Tiro Mas',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'fake', 'level_change', 'shot'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 9,
    maxDifficulty: 10,
    purposeEn: 'Aggressive scoring mindset.',
    purposeEs: 'Mentalidad agresiva para anotar.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
    },
  ),
  WorkoutPreset(
    id: 'overtime_brick_wall_finish',
    titleEn: 'Brick Wall Finish',
    titleEs: 'Final de Muro',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['sprawl', 'down_block', 'circle', 'stance'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 9,
    maxDifficulty: 10,
    purposeEn: 'Defensive toughness finisher.',
    purposeEs: 'Finalizador de dureza defensiva.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
    },
  ),
  WorkoutPreset(
    id: 'overtime_mat_return_mindset',
    titleEn: 'Mat Return Mindset',
    titleEs: 'Mentalidad de Regreso',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['hand_fight', 'snap_down', 'sprawl', 'circle'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Pressure, snaps, and recovery.',
    purposeEs: 'Presion, snaps y recuperacion.',
    timedCalloutDurations: {
      'hand_fight': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_burn_the_clock',
    titleEn: 'Burn the Clock',
    titleEs: 'Quema el Reloj',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'circle', 'hand_fight', 'down_block'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 7,
    maxDifficulty: 9,
    purposeEn: 'Controlled hard pace for protecting a lead.',
    purposeEs: 'Ritmo duro controlado para proteger ventaja.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(30),
      'hand_fight': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'overtime_chaos_period',
    titleEn: 'Chaos Period',
    titleEs: 'Periodo de Caos',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: [
      'stance',
      'fake',
      'shot',
      'sprawl',
      'circle',
      'down_block',
      'high_knees',
      'foot_fire',
    ],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 10,
    maxDifficulty: 10,
    purposeEn: 'Maximum random match-style chaos.',
    purposeEs: 'Maximo caos estilo combate.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
      'high_knees': WorkoutPresetTimedCallout(15),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'overtime_score_now',
    titleEn: 'Score Now',
    titleEs: 'Anota Ahora',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['fake', 'level_change', 'shot', 'snap_down'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Pure scoring pressure.',
    purposeEs: 'Presion pura para anotar.',
  ),
  WorkoutPreset(
    id: 'overtime_dont_get_scored_on',
    titleEn: "Don't Get Scored On",
    titleEs: 'No Te Anoten',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'sprawl', 'down_block', 'circle'],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 9,
    maxDifficulty: 10,
    purposeEn: 'Survive and defend hard.',
    purposeEs: 'Sobrevive y defiende duro.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
    },
  ),
  WorkoutPreset(
    id: 'overtime_state_champ_overtime',
    titleEn: 'State Champ Overtime',
    titleEs: 'Tiempo Extra de Campeon',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: [
      'stance',
      'fake',
      'level_change',
      'shot',
      'sprawl',
      'down_block',
      'circle',
      'hand_fight',
    ],
    minMinutes: 3,
    maxMinutes: 3,
    minDifficulty: 10,
    maxDifficulty: 10,
    purposeEn: 'Full 3-minute state finals overtime simulation.',
    purposeEs: 'Simulacion completa de final estatal en tiempo extra.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'hand_fight': WorkoutPresetTimedCallout(15),
    },
  ),
];

final defaultOvertimeWorkoutPreset = overtimeWorkoutPresets.first;

const allWorkoutPresets = <WorkoutPreset>[
  WorkoutPreset(
    id: 'daily_mat_warmup',
    titleEn: 'Daily Mat Warmup',
    titleEs: 'Calentamiento Diario',
    category: WorkoutPresetCategory.beginner,
    calloutIds: ['stance', 'circle', 'fake', 'level_change'],
    minMinutes: 3,
    maxMinutes: 5,
    minDifficulty: 3,
    maxDifficulty: 5,
    purposeEn: 'Basic daily movement and warmup.',
    purposeEs: 'Movimiento basico y calentamiento diario.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'beginner_shadow_drill',
    titleEn: 'Beginner Shadow Drill',
    titleEs: 'Drill Sombra Inicial',
    category: WorkoutPresetCategory.beginner,
    calloutIds: ['stance', 'circle', 'fake'],
    minMinutes: 1,
    maxMinutes: 3,
    minDifficulty: 1,
    maxDifficulty: 3,
    purposeEn: 'Easy entry-level motion drill.',
    purposeEs: 'Movimiento facil para empezar.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'first_whistle_drill',
    titleEn: 'First Whistle Drill',
    titleEs: 'Primer Silbato',
    category: WorkoutPresetCategory.quick,
    calloutIds: ['stance', 'level_change', 'shot'],
    minMinutes: 2,
    maxMinutes: 4,
    minDifficulty: 3,
    maxDifficulty: 5,
    purposeEn: 'Gets wrestlers ready to move, fake, and attack.',
    purposeEs: 'Prepara al luchador para moverse, fintar y atacar.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'shot_hunter',
    titleEn: 'Shot Hunter',
    titleEs: 'Cazador de Tiros',
    category: WorkoutPresetCategory.offense,
    calloutIds: ['stance', 'fake', 'level_change', 'shot'],
    minMinutes: 3,
    maxMinutes: 7,
    minDifficulty: 4,
    maxDifficulty: 7,
    purposeEn: 'Offensive attack rhythm.',
    purposeEs: 'Ritmo ofensivo de ataque.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'chain_attack_drill',
    titleEn: 'Chain Attack Drill',
    titleEs: 'Ataque en Cadena',
    category: WorkoutPresetCategory.offense,
    calloutIds: ['fake', 'level_change', 'shot', 'snap_down'],
    minMinutes: 4,
    maxMinutes: 8,
    minDifficulty: 5,
    maxDifficulty: 8,
    purposeEn: 'Creates action before attacking.',
    purposeEs: 'Crea accion antes de atacar.',
  ),
  WorkoutPreset(
    id: 'motion_creates_attacks',
    titleEn: 'Motion Creates Attacks',
    titleEs: 'Movimiento Crea Ataques',
    category: WorkoutPresetCategory.offense,
    calloutIds: ['stance', 'circle', 'fake', 'level_change', 'shot'],
    minMinutes: 4,
    maxMinutes: 8,
    minDifficulty: 4,
    maxDifficulty: 7,
    purposeEn: 'Builds movement before offense.',
    purposeEs: 'Construye movimiento antes del ataque.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'defensive_wall',
    titleEn: 'Defensive Wall',
    titleEs: 'Muro Defensivo',
    category: WorkoutPresetCategory.defense,
    calloutIds: ['stance', 'sprawl', 'down_block', 'circle'],
    minMinutes: 3,
    maxMinutes: 7,
    minDifficulty: 4,
    maxDifficulty: 8,
    purposeEn: 'Defensive reactions and recovery.',
    purposeEs: 'Reacciones defensivas y recuperacion.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'no_easy_takedowns',
    titleEn: 'No Easy Takedowns',
    titleEs: 'Nada Facil',
    category: WorkoutPresetCategory.defense,
    calloutIds: ['sprawl', 'down_block', 'circle', 'stance'],
    minMinutes: 5,
    maxMinutes: 10,
    minDifficulty: 6,
    maxDifficulty: 9,
    purposeEn: 'Hard defensive conditioning.',
    purposeEs: 'Condicion defensiva fuerte.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
    },
  ),
  WorkoutPreset(
    id: 'sprawl_recover',
    titleEn: 'Sprawl & Recover',
    titleEs: 'Sprawl y Recupera',
    category: WorkoutPresetCategory.defense,
    calloutIds: ['stance', 'sprawl', 'circle'],
    minMinutes: 2,
    maxMinutes: 6,
    minDifficulty: 4,
    maxDifficulty: 8,
    purposeEn: 'Sprawl, recover, move again.',
    purposeEs: 'Sprawl, recupera y vuelve a moverte.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'down_block_discipline',
    titleEn: 'Down Block Discipline',
    titleEs: 'Disciplina de Bloqueo',
    category: WorkoutPresetCategory.defense,
    calloutIds: ['stance', 'down_block', 'circle', 'fake'],
    minMinutes: 3,
    maxMinutes: 6,
    minDifficulty: 4,
    maxDifficulty: 7,
    purposeEn: 'Front-leg defense and staying active.',
    purposeEs: 'Defensa de pierna delantera y movimiento activo.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'heavy_hands',
    titleEn: 'Heavy Hands',
    titleEs: 'Manos Pesadas',
    category: WorkoutPresetCategory.handfight,
    calloutIds: ['hand_fight', 'snap_down', 'circle', 'fake'],
    minMinutes: 3,
    maxMinutes: 8,
    minDifficulty: 4,
    maxDifficulty: 8,
    purposeEn: 'Handfighting, pressure, and head control.',
    purposeEs: 'Manos, presion y control de cabeza.',
    featured: true,
    timedCalloutDurations: {
      'hand_fight': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'front_headlock_finder',
    titleEn: 'Front Headlock Finder',
    titleEs: 'Busca Front Headlock',
    category: WorkoutPresetCategory.handfight,
    calloutIds: ['hand_fight', 'snap_down', 'circle', 'sprawl'],
    minMinutes: 4,
    maxMinutes: 8,
    minDifficulty: 5,
    maxDifficulty: 8,
    purposeEn: 'Snap down pressure and defensive transition.',
    purposeEs: 'Presion de snap down y transicion defensiva.',
    timedCalloutDurations: {
      'hand_fight': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'collar_tie_crusher',
    titleEn: 'Collar Tie Crusher',
    titleEs: 'Collar Tie Crusher',
    category: WorkoutPresetCategory.handfight,
    calloutIds: ['hand_fight', 'snap_down', 'fake', 'level_change'],
    minMinutes: 4,
    maxMinutes: 8,
    minDifficulty: 5,
    maxDifficulty: 8,
    purposeEn: 'Hand control into attacks.',
    purposeEs: 'Control de manos hacia ataques.',
    timedCalloutDurations: {
      'hand_fight': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'fast_feet',
    titleEn: 'Fast Feet',
    titleEs: 'Pies Rapidos',
    category: WorkoutPresetCategory.conditioning,
    calloutIds: ['foot_fire', 'stance', 'circle', 'level_change'],
    minMinutes: 2,
    maxMinutes: 5,
    minDifficulty: 5,
    maxDifficulty: 9,
    purposeEn: 'Foot speed and stance discipline.',
    purposeEs: 'Velocidad de pies y disciplina de postura.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'conditioning_king',
    titleEn: 'Conditioning King',
    titleEs: 'Rey de Condicion',
    category: WorkoutPresetCategory.conditioning,
    calloutIds: ['high_knees', 'foot_fire', 'stance', 'sprawl'],
    minMinutes: 5,
    maxMinutes: 12,
    minDifficulty: 6,
    maxDifficulty: 10,
    purposeEn: 'Hard conditioning.',
    purposeEs: 'Condicionamiento fuerte.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'high_knees': WorkoutPresetTimedCallout(30),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'gas_tank_builder',
    titleEn: 'Gas Tank Builder',
    titleEs: 'Construye el Tanque',
    category: WorkoutPresetCategory.conditioning,
    calloutIds: ['high_knees', 'foot_fire', 'stance', 'circle', 'sprawl'],
    minMinutes: 6,
    maxMinutes: 12,
    minDifficulty: 6,
    maxDifficulty: 10,
    purposeEn: 'Wrestling endurance.',
    purposeEs: 'Resistencia de lucha.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(30),
      'high_knees': WorkoutPresetTimedCallout(45),
      'foot_fire': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'third_period_legs',
    titleEn: 'Third Period Legs',
    titleEs: 'Piernas del Tercer Periodo',
    category: WorkoutPresetCategory.conditioning,
    calloutIds: ['stance', 'high_knees', 'foot_fire', 'sprawl', 'circle'],
    minMinutes: 5,
    maxMinutes: 10,
    minDifficulty: 7,
    maxDifficulty: 10,
    purposeEn: 'Late-match fatigue training.',
    purposeEs: 'Entrenamiento bajo fatiga al final del combate.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(30),
      'high_knees': WorkoutPresetTimedCallout(45),
      'foot_fire': WorkoutPresetTimedCallout(45),
    },
  ),
  WorkoutPreset(
    id: 'overtime_ready',
    titleEn: 'Overtime Ready',
    titleEs: 'Listo Para Tiempo Extra',
    category: WorkoutPresetCategory.conditioning,
    calloutIds: [
      'stance',
      'circle',
      'sprawl',
      'shot',
      'high_knees',
      'foot_fire'
    ],
    minMinutes: 6,
    maxMinutes: 12,
    minDifficulty: 7,
    maxDifficulty: 10,
    purposeEn: 'Toughness under fatigue.',
    purposeEs: 'Fortaleza bajo fatiga.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'high_knees': WorkoutPresetTimedCallout(30),
      'foot_fire': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'state_champ_routine',
    titleEn: 'State Champ Routine',
    titleEs: 'Rutina de Campeon Estatal',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: [
      'stance',
      'fake',
      'level_change',
      'shot',
      'sprawl',
      'down_block',
      'circle',
      'snap_down',
    ],
    minMinutes: 8,
    maxMinutes: 15,
    minDifficulty: 7,
    maxDifficulty: 10,
    purposeEn: 'Full wrestling mix.',
    purposeEs: 'Mezcla completa de lucha.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'complete_wrestler',
    titleEn: 'Complete Wrestler',
    titleEs: 'Luchador Completo',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: [
      'stance',
      'fake',
      'level_change',
      'shot',
      'sprawl',
      'down_block',
      'circle',
      'hand_fight',
    ],
    minMinutes: 8,
    maxMinutes: 15,
    minDifficulty: 5,
    maxDifficulty: 9,
    purposeEn: 'Balanced offense, defense, motion, and handfighting.',
    purposeEs: 'Ataque, defensa, movimiento y manos balanceados.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'hand_fight': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'match_simulation',
    titleEn: 'Match Simulation',
    titleEs: 'Simulacion de Combate',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: [
      'stance',
      'circle',
      'fake',
      'level_change',
      'shot',
      'sprawl',
      'down_block',
      'hand_fight',
    ],
    minMinutes: 6,
    maxMinutes: 9,
    minDifficulty: 6,
    maxDifficulty: 10,
    purposeEn: 'Hard match-style pace.',
    purposeEs: 'Ritmo fuerte estilo combate.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'hand_fight': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'tournament_warmup',
    titleEn: 'Tournament Warmup',
    titleEs: 'Calentamiento de Torneo',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: ['stance', 'circle', 'fake', 'level_change', 'shot'],
    minMinutes: 3,
    maxMinutes: 5,
    minDifficulty: 3,
    maxDifficulty: 6,
    purposeEn: 'Pre-match warmup without exhausting the wrestler.',
    purposeEs: 'Calentamiento pre-combate sin agotarte.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'quick_sweat',
    titleEn: 'Quick Sweat',
    titleEs: 'Sudor Rapido',
    category: WorkoutPresetCategory.quick,
    calloutIds: ['high_knees', 'foot_fire', 'sprawl'],
    minMinutes: 1,
    maxMinutes: 3,
    minDifficulty: 7,
    maxDifficulty: 10,
    purposeEn: 'Very short high-intensity workout.',
    purposeEs: 'Entrenamiento corto de alta intensidad.',
    timedCalloutDurations: {
      'high_knees': WorkoutPresetTimedCallout(15),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'streak_saver',
    titleEn: 'Streak Saver',
    titleEs: 'Salva Racha',
    category: WorkoutPresetCategory.quick,
    calloutIds: ['stance', 'fake', 'shot'],
    minMinutes: 1,
    maxMinutes: 1,
    minDifficulty: 2,
    maxDifficulty: 4,
    purposeEn: 'Quick workout to keep the streak alive.',
    purposeEs: 'Drill rapido para mantener la racha.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'no_excuses_drill',
    titleEn: 'No Excuses Drill',
    titleEs: 'Sin Excusas',
    category: WorkoutPresetCategory.quick,
    calloutIds: ['stance', 'sprawl', 'shot', 'foot_fire'],
    minMinutes: 2,
    maxMinutes: 4,
    minDifficulty: 6,
    maxDifficulty: 9,
    purposeEn: 'Short but difficult workout.',
    purposeEs: 'Corto pero dificil.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'basement_grinder',
    titleEn: 'Basement Grinder',
    titleEs: 'Trabajo de Sotano',
    category: WorkoutPresetCategory.conditioning,
    calloutIds: ['stance', 'circle', 'sprawl', 'high_knees', 'foot_fire'],
    minMinutes: 8,
    maxMinutes: 15,
    minDifficulty: 7,
    maxDifficulty: 10,
    purposeEn: 'Hard solo grind session.',
    purposeEs: 'Sesion dura de entrenamiento solo.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(30),
      'high_knees': WorkoutPresetTimedCallout(45),
      'foot_fire': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'chain_wrestling_flow',
    titleEn: 'Chain Wrestling Flow',
    titleEs: 'Flujo de Cadena',
    category: WorkoutPresetCategory.offense,
    calloutIds: ['fake', 'level_change', 'shot', 'snap_down', 'circle'],
    minMinutes: 5,
    maxMinutes: 10,
    minDifficulty: 5,
    maxDifficulty: 8,
    purposeEn: 'Flow between setups and attacks.',
    purposeEs: 'Fluye entre preparaciones y ataques.',
  ),
  WorkoutPreset(
    id: 'attack_first',
    titleEn: 'Attack First',
    titleEs: 'Ataca Primero',
    category: WorkoutPresetCategory.offense,
    calloutIds: ['stance', 'fake', 'level_change', 'shot'],
    minMinutes: 3,
    maxMinutes: 8,
    minDifficulty: 5,
    maxDifficulty: 9,
    purposeEn: 'Aggressive offensive mindset.',
    purposeEs: 'Mentalidad ofensiva y agresiva.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'defense_first',
    titleEn: 'Defense First',
    titleEs: 'Defensa Primero',
    category: WorkoutPresetCategory.defense,
    calloutIds: ['stance', 'sprawl', 'down_block', 'circle'],
    minMinutes: 3,
    maxMinutes: 8,
    minDifficulty: 5,
    maxDifficulty: 9,
    purposeEn: 'Defensive focus.',
    purposeEs: 'Enfoque defensivo.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'heavy_pace',
    titleEn: 'Heavy Pace',
    titleEs: 'Ritmo Pesado',
    category: WorkoutPresetCategory.handfight,
    calloutIds: ['hand_fight', 'snap_down', 'sprawl', 'shot', 'circle'],
    minMinutes: 5,
    maxMinutes: 10,
    minDifficulty: 6,
    maxDifficulty: 9,
    purposeEn: 'Pressure wrestling and hard transitions.',
    purposeEs: 'Presion y transiciones fuertes.',
    timedCalloutDurations: {
      'hand_fight': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'freshman_builder',
    titleEn: 'Freshman Builder',
    titleEs: 'Base de Novato',
    category: WorkoutPresetCategory.beginner,
    calloutIds: ['stance', 'circle', 'fake', 'sprawl'],
    minMinutes: 2,
    maxMinutes: 5,
    minDifficulty: 2,
    maxDifficulty: 5,
    purposeEn: 'Beginner-friendly fundamentals.',
    purposeEs: 'Fundamentos amigables para principiantes.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'varsity_pace',
    titleEn: 'Varsity Pace',
    titleEs: 'Ritmo Varsity',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: [
      'stance',
      'fake',
      'level_change',
      'shot',
      'sprawl',
      'down_block'
    ],
    minMinutes: 6,
    maxMinutes: 12,
    minDifficulty: 6,
    maxDifficulty: 9,
    purposeEn: 'Serious practice-room pace.',
    purposeEs: 'Ritmo serio de sala de practica.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'captains_choice',
    titleEn: "Captain's Choice",
    titleEs: 'Eleccion del Capitan',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: [
      'stance',
      'shot',
      'sprawl',
      'hand_fight',
      'snap_down',
      'circle'
    ],
    minMinutes: 5,
    maxMinutes: 10,
    minDifficulty: 5,
    maxDifficulty: 9,
    purposeEn: 'Balanced team-leader style workout.',
    purposeEs: 'Entrenamiento balanceado estilo lider.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'hand_fight': WorkoutPresetTimedCallout(30),
    },
  ),
  WorkoutPreset(
    id: 'scramble_starter',
    titleEn: 'Scramble Starter',
    titleEs: 'Inicio de Scramble',
    category: WorkoutPresetCategory.defense,
    calloutIds: ['sprawl', 'circle', 'down_block', 'shot', 'level_change'],
    minMinutes: 3,
    maxMinutes: 7,
    minDifficulty: 5,
    maxDifficulty: 8,
    purposeEn: 'Reaction, recovery, and re-attack.',
    purposeEs: 'Reaccion, recuperacion y contraataque.',
  ),
  WorkoutPreset(
    id: 'short_offense_blast',
    titleEn: 'Short Offense Blast',
    titleEs: 'Ataque Corto',
    category: WorkoutPresetCategory.quick,
    calloutIds: ['fake', 'level_change', 'shot'],
    minMinutes: 1,
    maxMinutes: 3,
    minDifficulty: 6,
    maxDifficulty: 10,
    purposeEn: 'Quick attack-focused drill.',
    purposeEs: 'Drill rapido enfocado en ataque.',
  ),
  WorkoutPreset(
    id: 'short_defense_blast',
    titleEn: 'Short Defense Blast',
    titleEs: 'Defensa Corta',
    category: WorkoutPresetCategory.quick,
    calloutIds: ['sprawl', 'down_block', 'circle'],
    minMinutes: 1,
    maxMinutes: 3,
    minDifficulty: 6,
    maxDifficulty: 10,
    purposeEn: 'Quick defensive reaction drill.',
    purposeEs: 'Drill rapido de reaccion defensiva.',
  ),
  WorkoutPreset(
    id: 'the_grind',
    titleEn: 'The Grind',
    titleEs: 'La Rutina Dura',
    category: WorkoutPresetCategory.conditioning,
    calloutIds: ['stance', 'high_knees', 'foot_fire', 'sprawl', 'shot'],
    minMinutes: 10,
    maxMinutes: 15,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Hardest general preset.',
    purposeEs: 'Preset general mas duro.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'high_knees': WorkoutPresetTimedCallout(30),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'final_whistle',
    titleEn: 'Final Whistle',
    titleEs: 'Silbato Final',
    category: WorkoutPresetCategory.matchPrep,
    calloutIds: [
      'stance',
      'circle',
      'shot',
      'sprawl',
      'high_knees',
      'foot_fire'
    ],
    minMinutes: 3,
    maxMinutes: 6,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Push at the end of a match.',
    purposeEs: 'Empuja al final del combate.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(5),
      'high_knees': WorkoutPresetTimedCallout(15),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'neutral_assassin',
    titleEn: 'Neutral Assassin',
    titleEs: 'Asesino Neutral',
    category: WorkoutPresetCategory.offense,
    calloutIds: ['stance', 'fake', 'level_change', 'shot', 'sprawl', 'circle'],
    minMinutes: 5,
    maxMinutes: 10,
    minDifficulty: 6,
    maxDifficulty: 9,
    purposeEn: 'Neutral-position mastery.',
    purposeEs: 'Dominio de posicion neutral.',
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
    },
  ),
  WorkoutPreset(
    id: 'iron_room',
    titleEn: 'Iron Room',
    titleEs: 'Cuarto de Hierro',
    category: WorkoutPresetCategory.conditioning,
    calloutIds: [
      'stance',
      'hand_fight',
      'snap_down',
      'sprawl',
      'down_block',
      'shot',
      'high_knees',
      'foot_fire',
    ],
    minMinutes: 10,
    maxMinutes: 15,
    minDifficulty: 8,
    maxDifficulty: 10,
    purposeEn: 'Brutal full-body wrestling conditioning.',
    purposeEs: 'Condicion brutal de cuerpo completo.',
    featured: true,
    timedCalloutDurations: {
      'stance': WorkoutPresetTimedCallout(15),
      'hand_fight': WorkoutPresetTimedCallout(15),
      'high_knees': WorkoutPresetTimedCallout(30),
      'foot_fire': WorkoutPresetTimedCallout(15),
    },
  ),
];
