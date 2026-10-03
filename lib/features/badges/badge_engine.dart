import 'dart:math' as math;

import 'badge_catalog.dart';
import 'badge_models.dart';

class BadgeEngine {
  final List<BadgeDefinition> catalog;

  BadgeEngine({List<BadgeDefinition>? catalog})
      : catalog = catalog ?? BadgeCatalog.launchBadges;

  BadgeProgressState recordWorkout(
    BadgeProgressState state,
    WorkoutBadgeInput input,
  ) {
    final previousStats = state.stats;
    final dateKey = _dateKey(input.completedAt);
    final weekKey = _weekKey(input.completedAt);
    final workoutsByDate = Map<String, int>.from(previousStats.workoutsByDate);
    workoutsByDate[dateKey] = (workoutsByDate[dateKey] ?? 0) + 1;

    final oneMinuteWorkoutsByWeek =
        Map<String, int>.from(previousStats.oneMinuteWorkoutsByWeek);
    if (input.duration.inSeconds <= 60) {
      oneMinuteWorkoutsByWeek[weekKey] =
          (oneMinuteWorkoutsByWeek[weekKey] ?? 0) + 1;
    }

    final overtimeWorkoutsByDate =
        Map<String, int>.from(previousStats.overtimeWorkoutsByDate);
    if (input.isOvertimeWorkout) {
      overtimeWorkoutsByDate[dateKey] =
          (overtimeWorkoutsByDate[dateKey] ?? 0) + 1;
    }

    final previousWorkout = previousStats.lastWorkoutAt;
    final followsTenMinuteWorkout = input.isOvertimeWorkout &&
        previousStats.lastWorkoutDurationSeconds >= 600 &&
        previousWorkout != null &&
        input.completedAt.difference(previousWorkout).inMinutes <= 30;

    final fullMinuteByWeek =
        Map<String, int>.from(previousStats.fullMinuteCalloutsByWeek);
    for (final entry in input.fullMinuteCallouts.entries) {
      final key = '$weekKey:${entry.key}';
      fullMinuteByWeek[key] = (fullMinuteByWeek[key] ?? 0) + entry.value;
    }

    final stats = previousStats.copyWith(
      calloutTotals: _mergeTotals(
        previousStats.calloutTotals,
        input.calloutCounts,
      ),
      timedSecondsByCallout: _mergeTotals(
        previousStats.timedSecondsByCallout,
        input.timedSecondsByCallout,
      ),
      fullMinuteCallouts: _mergeTotals(
        previousStats.fullMinuteCallouts,
        input.fullMinuteCallouts,
      ),
      fullMinuteCalloutsByWeek: fullMinuteByWeek,
      workoutsByDate: workoutsByDate,
      oneMinuteWorkoutsByWeek: oneMinuteWorkoutsByWeek,
      overtimeWorkoutsByDate: overtimeWorkoutsByDate,
      totalWorkouts: previousStats.totalWorkouts + 1,
      totalTrainingSeconds:
          previousStats.totalTrainingSeconds + input.duration.inSeconds,
      currentStreak: _currentStreak(workoutsByDate, input.completedAt),
      overtimeWorkoutCount: previousStats.overtimeWorkoutCount +
          (input.isOvertimeWorkout ? 1 : 0),
      currentOvertimeStreak: input.isOvertimeWorkout
          ? _currentStreak(overtimeWorkoutsByDate, input.completedAt)
          : previousStats.currentOvertimeStreak,
      stateChampOvertimeCount: previousStats.stateChampOvertimeCount +
          (input.isStateChampOvertime ? 1 : 0),
      overtimeAfterTenMinuteWorkoutCount:
          previousStats.overtimeAfterTenMinuteWorkoutCount +
              (followsTenMinuteWorkout ? 1 : 0),
      highDifficultyWorkoutCount: previousStats.highDifficultyWorkoutCount +
          (input.difficultyScore >= 8 ? 1 : 0),
      noPauseWorkoutCount:
          previousStats.noPauseWorkoutCount + (input.hadPause ? 0 : 1),
      customCalloutWorkoutCount: previousStats.customCalloutWorkoutCount +
          (input.usedCustomCallouts ? 1 : 0),
      seasonPassWorkoutCount: previousStats.seasonPassWorkoutCount +
          (input.isPro && input.seasonTargetDate != null ? 1 : 0),
      lastWorkoutDurationSeconds: input.duration.inSeconds,
      lastWorkoutAt: input.completedAt,
      seasonTargetDate:
          input.seasonTargetDate ?? previousStats.seasonTargetDate,
    );

    final specialMetrics = _workoutSpecialMetrics(
      state: state,
      previousStats: previousStats,
      stats: stats,
      input: input,
      dateKey: dateKey,
      weekKey: weekKey,
    );

    final evaluated = _evaluateAll(
      state.copyWith(stats: stats),
      at: input.completedAt,
      specialMetrics: specialMetrics,
    );

    return evaluated.state.copyWith(
      lastWorkoutResult: BadgeWorkoutResult(
        newlyUnlockedBadgeIds: evaluated.newlyUnlockedBadgeIds,
        updatedBadgeIds: evaluated.updatedBadgeIds,
        estimatedRepsEarned: input.estimatedRepsEarned,
        currentStreak: stats.currentStreak,
        almostThereBadgeId: _bestAlmostThere(evaluated.state)?.id,
      ),
    );
  }

  BadgeProgressState recordSeasonTargetSet(
    BadgeProgressState state,
    DateTime targetDate, {
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final stats = state.stats.copyWith(
      seasonTargetDate: DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      ),
      seasonTargetSetAt: now,
    );

    return _evaluateAll(
      state.copyWith(stats: stats),
      at: now,
      specialMetrics: const {'season.target_set': 1},
    ).state;
  }

  BadgeProgressState recordSocialProgress(
    BadgeProgressState state,
    SocialBadgeInput input,
  ) {
    final stats = state.stats.copyWith(
      totalSharedWorkouts: input.totalSharedWorkouts,
      socialProgressPoints: input.socialProgressPoints,
      relayStreak: input.relayStreak,
      friendWorkoutStreak: input.friendWorkoutStreak,
      bestPartnerStreak: input.bestPartnerStreak,
      crewStreak: input.crewStreak,
      totalQualifiedRelays: input.totalQualifiedRelays,
      totalCompletedFriendWorkouts: input.totalCompletedFriendWorkouts,
      totalCrewWeeks: input.totalCrewWeeks,
    );
    return _evaluateAll(
      state.copyWith(stats: stats),
      at: input.updatedAt,
    ).state;
  }

  BadgeProgressState recordCustomCalloutCreated(
    BadgeProgressState state, {
    required int customCalloutCount,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final stats = state.stats.copyWith(
      customCalloutCount: math.max(
        state.stats.customCalloutCount,
        customCalloutCount,
      ),
    );
    return _evaluateAll(state.copyWith(stats: stats), at: now).state;
  }

  BadgeProgressState recordPremiumRecordingSaved(
    BadgeProgressState state, {
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final stats = state.stats.copyWith(
      premiumRecordingSaveCount: state.stats.premiumRecordingSaveCount + 1,
    );
    return _evaluateAll(state.copyWith(stats: stats), at: now).state;
  }

  _BadgeEvaluation _evaluateAll(
    BadgeProgressState state, {
    required DateTime at,
    Map<String, int> specialMetrics = const {},
  }) {
    final nextProgress = Map<String, BadgeProgress>.from(state.progressById);
    final newlyUnlocked = <String>[];
    final updated = <String>[];

    for (final definition in catalog) {
      final previous = state.progressFor(definition);
      final value = _metricValue(
        definition,
        state.stats,
        previous,
        specialMetrics,
      ).clamp(0, definition.targetProgress);

      final shouldUnlock =
          previous.unlockedAt == null && value >= definition.targetProgress;
      final next = BadgeProgress(
        id: definition.id,
        currentProgress: math.max(previous.currentProgress, value),
        unlockedAt: previous.unlockedAt ?? (shouldUnlock ? at : null),
      );

      if (shouldUnlock) newlyUnlocked.add(definition.id);
      if (next.currentProgress != previous.currentProgress ||
          next.unlockedAt != previous.unlockedAt) {
        updated.add(definition.id);
      }
      nextProgress[definition.id] = next;
    }

    final recent = [
      ...newlyUnlocked.reversed,
      ...state.recentUnlockedBadgeIds.where(
        (id) => !newlyUnlocked.contains(id),
      ),
    ].take(12).toList();

    return _BadgeEvaluation(
      state: state.copyWith(
        progressById: nextProgress,
        recentUnlockedBadgeIds: recent,
      ),
      newlyUnlockedBadgeIds: newlyUnlocked,
      updatedBadgeIds: updated,
    );
  }

  int _metricValue(
    BadgeDefinition definition,
    BadgeStats stats,
    BadgeProgress previous,
    Map<String, int> specialMetrics,
  ) {
    if (previous.isUnlocked && definition.targetProgress == 1) {
      return definition.targetProgress;
    }

    final special = specialMetrics[definition.metricKey];
    if (special != null) {
      return math.max(previous.currentProgress, special);
    }

    final key = definition.metricKey;
    if (key.startsWith('callout.')) {
      return stats.calloutTotals[key.substring('callout.'.length)] ?? 0;
    }
    if (key.startsWith('timed.') && key.endsWith('.minutes')) {
      final id = key.substring('timed.'.length, key.length - '.minutes'.length);
      return (stats.timedSecondsByCallout[id] ?? 0) ~/ 60;
    }
    if (key.startsWith('full60.')) {
      return stats.fullMinuteCallouts[key.substring('full60.'.length)] ?? 0;
    }
    if (key.startsWith('weekly60.')) {
      return previous.currentProgress;
    }

    switch (key) {
      case 'streak.days':
        return stats.currentStreak;
      case 'workouts.total':
        return stats.totalWorkouts;
      case 'training.minutes':
        return stats.totalTrainingSeconds ~/ 60;
      case 'difficulty.8.count':
        return stats.highDifficultyWorkoutCount;
      case 'overtime.workouts':
        return stats.overtimeWorkoutCount;
      case 'overtime.streak_days':
        return stats.currentOvertimeStreak;
      case 'overtime.state_champ':
        return stats.stateChampOvertimeCount;
      case 'overtime.after_10_min':
        return stats.overtimeAfterTenMinuteWorkoutCount;
      case 'secret.no_pause_monster':
        return stats.noPauseWorkoutCount;
      case 'premium.custom_callouts':
        return stats.customCalloutCount;
      case 'premium.custom_workouts':
        return stats.customCalloutWorkoutCount;
      case 'premium.recording_saves':
        return stats.premiumRecordingSaveCount;
      case 'premium.season_pass_workouts':
        return stats.seasonPassWorkoutCount;
      case 'season.target_set':
        return stats.seasonTargetDate == null ? 0 : 1;
      case 'season.on_clock':
        return stats.seasonTargetDate != null && stats.totalWorkouts > 0
            ? 1
            : 0;
      case 'season.on_pace':
        return stats.seasonTargetDate == null
            ? 0
            : math.min(3, stats.currentStreak);
      case 'season.ahead_pace':
        return stats.seasonTargetDate != null &&
                _totalEstimatedReps(stats) >= 1000
            ? 1
            : 0;
      case 'season.state_ready':
        return stats.seasonTargetDate != null &&
                _totalEstimatedReps(stats) >= 5000
            ? 1
            : 0;
      case 'social.points':
        return stats.socialProgressPoints;
      case 'social.shared_workouts':
        return stats.totalSharedWorkouts;
      case 'social.relay_streak':
        return stats.relayStreak;
      case 'social.friend_streak':
        return stats.friendWorkoutStreak;
      case 'social.partner_streak':
        return stats.bestPartnerStreak;
      case 'social.crew_streak':
        return stats.crewStreak;
      case 'social.qualified_relays':
        return stats.totalQualifiedRelays;
      case 'social.completed_friend_workouts':
        return stats.totalCompletedFriendWorkouts;
      case 'social.crew_weeks':
        return stats.totalCrewWeeks;
      default:
        return previous.currentProgress;
    }
  }

  Map<String, int> _workoutSpecialMetrics({
    required BadgeProgressState state,
    required BadgeStats previousStats,
    required BadgeStats stats,
    required WorkoutBadgeInput input,
    required String dateKey,
    required String weekKey,
  }) {
    final metrics = <String, int>{};
    final enabled = input.enabledCalloutIds;
    final counts = input.calloutCounts;
    final timed = input.timedSecondsByCallout;

    if (input.difficultyScore >= 5) metrics['difficulty.5.single'] = 1;
    if (input.difficultyScore >= 8) metrics['difficulty.8.single'] = 1;
    if (input.difficultyScore >= 10) metrics['difficulty.10.single'] = 1;

    if (_hasAll(
        enabled, const ['shot', 'sprawl', 'stance', 'fake', 'circle'])) {
      metrics['combo.complete_wrestler'] = 1;
    }
    if ((counts['shot'] ?? 0) >= 10 && (counts['sprawl'] ?? 0) >= 10) {
      metrics['combo.offense_defense'] = 1;
    }
    if (_hasAnyWorkoutValue(counts, 'fake') &&
        _hasAnyWorkoutValue(counts, 'level_change') &&
        _hasAnyWorkoutValue(counts, 'shot')) {
      metrics['combo.motion_creates_attacks'] = 1;
    }
    if (_hasAnyWorkoutValue(counts, 'sprawl') &&
        _hasAnyWorkoutValue(counts, 'down_block') &&
        _hasAnyWorkoutValue(counts, 'circle')) {
      metrics['combo.defense_first'] = 1;
    }
    if (_hasAnyWorkoutValue(counts, 'snap_down') &&
        (timed['hand_fight'] ?? 0) > 0) {
      metrics['combo.heavy_hands_session'] = 1;
    }
    if ((timed['high_knees'] ?? 0) > 0 &&
        (timed['foot_fire'] ?? 0) > 0 &&
        (timed['stance'] ?? 0) > 0) {
      metrics['combo.gas_tank_session'] = 1;
    }

    for (final id in const ['stance']) {
      final weekCount = stats.fullMinuteCalloutsByWeek['$weekKey:$id'] ?? 0;
      metrics['weekly60.$id'] = weekCount;
    }

    final previousWorkout = previousStats.lastWorkoutAt;
    if (previousWorkout != null) {
      final gapDays = _dateOnly(input.completedAt)
          .difference(_dateOnly(previousWorkout))
          .inDays;
      if (input.duration.inSeconds <= 60 && gapDays == 2) {
        metrics['secret.still_showed_up'] = 1;
      }
      if (gapDays >= 4) {
        metrics['secret.comeback_kid'] = 1;
      }
      if (input.completedAt.difference(previousWorkout).inMinutes <= 10) {
        metrics['secret.just_one_more'] = 1;
      }
    }

    if (input.hadPause) {
      metrics['secret.couldve_quit'] = 1;
    }
    metrics['secret.workouts_today'] = stats.workoutsByDate[dateKey] ?? 0;
    if (input.duration.inMinutes >= 15 && input.difficultyScore >= 10) {
      metrics['secret.the_hard_way'] = 1;
    }
    metrics['secret.one_minute_week'] =
        stats.oneMinuteWorkoutsByWeek[weekKey] ?? 0;
    if (input.difficultyScore >= 8 &&
        ((input.fullMinuteCallouts['high_knees'] ?? 0) > 0 ||
            (input.fullMinuteCallouts['foot_fire'] ?? 0) > 0)) {
      metrics['secret.empty_the_tank'] = 1;
    }

    final targetDate = stats.seasonTargetDate;
    if (targetDate != null) {
      metrics['season.on_clock'] = 1;
      final daysUntil =
          _dateOnly(targetDate).difference(_dateOnly(input.completedAt)).inDays;
      if (daysUntil >= 0 && daysUntil <= 7) {
        final previous =
            state.progressById['season_final_week_grinder']?.currentProgress ??
                0;
        metrics['season.final_week_workouts'] = previous + 1;
      }
    }

    return metrics;
  }

  Badge? _bestAlmostThere(BadgeProgressState state) {
    final almost = state.badgesFor(catalog).where((badge) {
      return !badge.isPremium && badge.isAlmostThere;
    }).toList()
      ..sort((a, b) => b.completionRatio.compareTo(a.completionRatio));

    return almost.isEmpty ? null : almost.first;
  }

  static int difficultyScoreFor({
    required double minIntervalSeconds,
    required double maxIntervalSeconds,
  }) {
    if (minIntervalSeconds <= 0.6 && maxIntervalSeconds <= 1.6) return 10;
    if (maxIntervalSeconds <= 2.1) return 8;
    if (maxIntervalSeconds <= 4.1) return 5;
    return 3;
  }

  static Map<String, int> _mergeTotals(
    Map<String, int> current,
    Map<String, int> update,
  ) {
    final next = Map<String, int>.from(current);
    for (final entry in update.entries) {
      next[entry.key] = (next[entry.key] ?? 0) + entry.value;
    }
    return next;
  }

  static bool _hasAnyWorkoutValue(Map<String, int> values, String key) {
    return (values[key] ?? 0) > 0;
  }

  static bool _hasAll(Set<String> values, List<String> required) {
    return required.every(values.contains);
  }

  static int _totalEstimatedReps(BadgeStats stats) {
    return stats.calloutTotals.values.fold<int>(0, (sum, value) => sum + value);
  }

  static int _currentStreak(Map<String, int> workoutsByDate, DateTime today) {
    var cursor = _dateOnly(today);
    if ((workoutsByDate[_dateKey(cursor)] ?? 0) == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
      if ((workoutsByDate[_dateKey(cursor)] ?? 0) == 0) return 0;
    }

    var streak = 0;
    while ((workoutsByDate[_dateKey(cursor)] ?? 0) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static String _dateKey(DateTime date) {
    final local = _dateOnly(date);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String _weekKey(DateTime date) {
    final local = _dateOnly(date);
    final monday = local.subtract(Duration(days: local.weekday - 1));
    return _dateKey(monday);
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}

class _BadgeEvaluation {
  final BadgeProgressState state;
  final List<String> newlyUnlockedBadgeIds;
  final List<String> updatedBadgeIds;

  const _BadgeEvaluation({
    required this.state,
    required this.newlyUnlockedBadgeIds,
    required this.updatedBadgeIds,
  });
}
