import 'dart:convert';

import 'package:flutter/foundation.dart';

enum BadgeCategory {
  moveMastery,
  timedMastery,
  streak,
  grind,
  combo,
  season,
  flex,
  premium,
  social,
  secret,
}

enum BadgeTier {
  bronze,
  silver,
  gold,
  platinum,
  blackBelt,
  legend,
}

extension BadgeCategoryX on BadgeCategory {
  String get id {
    switch (this) {
      case BadgeCategory.moveMastery:
        return 'move_mastery';
      case BadgeCategory.timedMastery:
        return 'timed_mastery';
      case BadgeCategory.streak:
        return 'streak';
      case BadgeCategory.grind:
        return 'grind';
      case BadgeCategory.combo:
        return 'combo';
      case BadgeCategory.season:
        return 'season';
      case BadgeCategory.flex:
        return 'flex';
      case BadgeCategory.premium:
        return 'premium';
      case BadgeCategory.social:
        return 'social';
      case BadgeCategory.secret:
        return 'secret';
    }
  }

  static BadgeCategory fromId(String id) {
    return BadgeCategory.values.firstWhere(
      (category) => category.id == id,
      orElse: () => BadgeCategory.grind,
    );
  }
}

extension BadgeTierX on BadgeTier {
  String get id {
    switch (this) {
      case BadgeTier.bronze:
        return 'bronze';
      case BadgeTier.silver:
        return 'silver';
      case BadgeTier.gold:
        return 'gold';
      case BadgeTier.platinum:
        return 'platinum';
      case BadgeTier.blackBelt:
        return 'black_belt';
      case BadgeTier.legend:
        return 'legend';
    }
  }

  String get label {
    switch (this) {
      case BadgeTier.bronze:
        return 'Bronze';
      case BadgeTier.silver:
        return 'Silver';
      case BadgeTier.gold:
        return 'Gold';
      case BadgeTier.platinum:
        return 'Platinum';
      case BadgeTier.blackBelt:
        return 'Black Belt';
      case BadgeTier.legend:
        return 'Legend';
    }
  }

  static BadgeTier fromId(String id) {
    return BadgeTier.values.firstWhere(
      (tier) => tier.id == id,
      orElse: () => BadgeTier.bronze,
    );
  }
}

@immutable
class BadgeDefinition {
  final String id;
  final String title;
  final String description;
  final BadgeCategory category;
  final BadgeTier tier;
  final int targetProgress;
  final String metricKey;
  final bool isSecret;
  final String? hint;
  final bool isPremium;
  final String iconName;

  const BadgeDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.tier,
    required this.targetProgress,
    required this.metricKey,
    required this.iconName,
    this.isSecret = false,
    this.hint,
    this.isPremium = false,
  });
}

@immutable
class BadgeProgress {
  final String id;
  final int currentProgress;
  final DateTime? unlockedAt;

  const BadgeProgress({
    required this.id,
    this.currentProgress = 0,
    this.unlockedAt,
  });

  bool get isUnlocked => unlockedAt != null;

  BadgeProgress copyWith({
    int? currentProgress,
    DateTime? unlockedAt,
  }) {
    return BadgeProgress(
      id: id,
      currentProgress: currentProgress ?? this.currentProgress,
      unlockedAt: unlockedAt ?? this.unlockedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'currentProgress': currentProgress,
      'unlockedAt': unlockedAt?.toIso8601String(),
    };
  }

  factory BadgeProgress.fromMap(Map<String, dynamic> map) {
    final rawUnlockedAt = map['unlockedAt'] as String?;
    return BadgeProgress(
      id: map['id'] as String,
      currentProgress: (map['currentProgress'] as num?)?.toInt() ?? 0,
      unlockedAt:
          rawUnlockedAt == null ? null : DateTime.tryParse(rawUnlockedAt),
    );
  }
}

@immutable
class Badge {
  final String id;
  final String title;
  final String description;
  final BadgeCategory category;
  final BadgeTier tier;
  final int currentProgress;
  final int targetProgress;
  final DateTime? unlockedAt;
  final bool isSecret;
  final String? hint;
  final bool isPremium;
  final String iconName;

  const Badge({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.tier,
    required this.currentProgress,
    required this.targetProgress,
    required this.iconName,
    this.unlockedAt,
    this.isSecret = false,
    this.hint,
    this.isPremium = false,
  });

  bool get isUnlocked => unlockedAt != null;

  double get completionRatio {
    if (targetProgress <= 0) return isUnlocked ? 1 : 0;
    return (currentProgress / targetProgress).clamp(0.0, 1.0).toDouble();
  }

  bool get isAlmostThere => !isUnlocked && completionRatio >= 0.7;

  String get displayTitle => isSecret && !isUnlocked ? 'Secret Badge' : title;

  String get displayDescription {
    if (isSecret && !isUnlocked) {
      return hint ?? 'Keep training to reveal this badge.';
    }
    return description;
  }

  factory Badge.fromDefinition(
    BadgeDefinition definition,
    BadgeProgress progress,
  ) {
    return Badge(
      id: definition.id,
      title: definition.title,
      description: definition.description,
      category: definition.category,
      tier: definition.tier,
      currentProgress: progress.currentProgress.clamp(
        0,
        definition.targetProgress,
      ),
      targetProgress: definition.targetProgress,
      unlockedAt: progress.unlockedAt,
      isSecret: definition.isSecret,
      hint: definition.hint,
      isPremium: definition.isPremium,
      iconName: definition.iconName,
    );
  }
}

@immutable
class BadgeStats {
  final Map<String, int> calloutTotals;
  final Map<String, int> timedSecondsByCallout;
  final Map<String, int> fullMinuteCallouts;
  final Map<String, int> fullMinuteCalloutsByWeek;
  final Map<String, int> workoutsByDate;
  final Map<String, int> oneMinuteWorkoutsByWeek;
  final Map<String, int> overtimeWorkoutsByDate;
  final int totalWorkouts;
  final int totalTrainingSeconds;
  final int currentStreak;
  final int overtimeWorkoutCount;
  final int currentOvertimeStreak;
  final int stateChampOvertimeCount;
  final int overtimeAfterTenMinuteWorkoutCount;
  final int highDifficultyWorkoutCount;
  final int noPauseWorkoutCount;
  final int customCalloutCount;
  final int customCalloutWorkoutCount;
  final int premiumRecordingSaveCount;
  final int seasonPassWorkoutCount;
  final int totalSharedWorkouts;
  final int socialProgressPoints;
  final int relayStreak;
  final int friendWorkoutStreak;
  final int bestPartnerStreak;
  final int crewStreak;
  final int totalQualifiedRelays;
  final int totalCompletedFriendWorkouts;
  final int totalCrewWeeks;
  final int lastWorkoutDurationSeconds;
  final DateTime? lastWorkoutAt;
  final DateTime? seasonTargetDate;
  final DateTime? seasonTargetSetAt;

  const BadgeStats({
    this.calloutTotals = const {},
    this.timedSecondsByCallout = const {},
    this.fullMinuteCallouts = const {},
    this.fullMinuteCalloutsByWeek = const {},
    this.workoutsByDate = const {},
    this.oneMinuteWorkoutsByWeek = const {},
    this.overtimeWorkoutsByDate = const {},
    this.totalWorkouts = 0,
    this.totalTrainingSeconds = 0,
    this.currentStreak = 0,
    this.overtimeWorkoutCount = 0,
    this.currentOvertimeStreak = 0,
    this.stateChampOvertimeCount = 0,
    this.overtimeAfterTenMinuteWorkoutCount = 0,
    this.highDifficultyWorkoutCount = 0,
    this.noPauseWorkoutCount = 0,
    this.customCalloutCount = 0,
    this.customCalloutWorkoutCount = 0,
    this.premiumRecordingSaveCount = 0,
    this.seasonPassWorkoutCount = 0,
    this.totalSharedWorkouts = 0,
    this.socialProgressPoints = 0,
    this.relayStreak = 0,
    this.friendWorkoutStreak = 0,
    this.bestPartnerStreak = 0,
    this.crewStreak = 0,
    this.totalQualifiedRelays = 0,
    this.totalCompletedFriendWorkouts = 0,
    this.totalCrewWeeks = 0,
    this.lastWorkoutDurationSeconds = 0,
    this.lastWorkoutAt,
    this.seasonTargetDate,
    this.seasonTargetSetAt,
  });

  BadgeStats copyWith({
    Map<String, int>? calloutTotals,
    Map<String, int>? timedSecondsByCallout,
    Map<String, int>? fullMinuteCallouts,
    Map<String, int>? fullMinuteCalloutsByWeek,
    Map<String, int>? workoutsByDate,
    Map<String, int>? oneMinuteWorkoutsByWeek,
    Map<String, int>? overtimeWorkoutsByDate,
    int? totalWorkouts,
    int? totalTrainingSeconds,
    int? currentStreak,
    int? overtimeWorkoutCount,
    int? currentOvertimeStreak,
    int? stateChampOvertimeCount,
    int? overtimeAfterTenMinuteWorkoutCount,
    int? highDifficultyWorkoutCount,
    int? noPauseWorkoutCount,
    int? customCalloutCount,
    int? customCalloutWorkoutCount,
    int? premiumRecordingSaveCount,
    int? seasonPassWorkoutCount,
    int? totalSharedWorkouts,
    int? socialProgressPoints,
    int? relayStreak,
    int? friendWorkoutStreak,
    int? bestPartnerStreak,
    int? crewStreak,
    int? totalQualifiedRelays,
    int? totalCompletedFriendWorkouts,
    int? totalCrewWeeks,
    int? lastWorkoutDurationSeconds,
    DateTime? lastWorkoutAt,
    DateTime? seasonTargetDate,
    DateTime? seasonTargetSetAt,
  }) {
    return BadgeStats(
      calloutTotals: calloutTotals ?? this.calloutTotals,
      timedSecondsByCallout:
          timedSecondsByCallout ?? this.timedSecondsByCallout,
      fullMinuteCallouts: fullMinuteCallouts ?? this.fullMinuteCallouts,
      fullMinuteCalloutsByWeek:
          fullMinuteCalloutsByWeek ?? this.fullMinuteCalloutsByWeek,
      workoutsByDate: workoutsByDate ?? this.workoutsByDate,
      oneMinuteWorkoutsByWeek:
          oneMinuteWorkoutsByWeek ?? this.oneMinuteWorkoutsByWeek,
      overtimeWorkoutsByDate:
          overtimeWorkoutsByDate ?? this.overtimeWorkoutsByDate,
      totalWorkouts: totalWorkouts ?? this.totalWorkouts,
      totalTrainingSeconds: totalTrainingSeconds ?? this.totalTrainingSeconds,
      currentStreak: currentStreak ?? this.currentStreak,
      overtimeWorkoutCount: overtimeWorkoutCount ?? this.overtimeWorkoutCount,
      currentOvertimeStreak:
          currentOvertimeStreak ?? this.currentOvertimeStreak,
      stateChampOvertimeCount:
          stateChampOvertimeCount ?? this.stateChampOvertimeCount,
      overtimeAfterTenMinuteWorkoutCount: overtimeAfterTenMinuteWorkoutCount ??
          this.overtimeAfterTenMinuteWorkoutCount,
      highDifficultyWorkoutCount:
          highDifficultyWorkoutCount ?? this.highDifficultyWorkoutCount,
      noPauseWorkoutCount: noPauseWorkoutCount ?? this.noPauseWorkoutCount,
      customCalloutCount: customCalloutCount ?? this.customCalloutCount,
      customCalloutWorkoutCount:
          customCalloutWorkoutCount ?? this.customCalloutWorkoutCount,
      premiumRecordingSaveCount:
          premiumRecordingSaveCount ?? this.premiumRecordingSaveCount,
      seasonPassWorkoutCount:
          seasonPassWorkoutCount ?? this.seasonPassWorkoutCount,
      totalSharedWorkouts: totalSharedWorkouts ?? this.totalSharedWorkouts,
      socialProgressPoints: socialProgressPoints ?? this.socialProgressPoints,
      relayStreak: relayStreak ?? this.relayStreak,
      friendWorkoutStreak: friendWorkoutStreak ?? this.friendWorkoutStreak,
      bestPartnerStreak: bestPartnerStreak ?? this.bestPartnerStreak,
      crewStreak: crewStreak ?? this.crewStreak,
      totalQualifiedRelays: totalQualifiedRelays ?? this.totalQualifiedRelays,
      totalCompletedFriendWorkouts:
          totalCompletedFriendWorkouts ?? this.totalCompletedFriendWorkouts,
      totalCrewWeeks: totalCrewWeeks ?? this.totalCrewWeeks,
      lastWorkoutDurationSeconds:
          lastWorkoutDurationSeconds ?? this.lastWorkoutDurationSeconds,
      lastWorkoutAt: lastWorkoutAt ?? this.lastWorkoutAt,
      seasonTargetDate: seasonTargetDate ?? this.seasonTargetDate,
      seasonTargetSetAt: seasonTargetSetAt ?? this.seasonTargetSetAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'calloutTotals': calloutTotals,
      'timedSecondsByCallout': timedSecondsByCallout,
      'fullMinuteCallouts': fullMinuteCallouts,
      'fullMinuteCalloutsByWeek': fullMinuteCalloutsByWeek,
      'workoutsByDate': workoutsByDate,
      'oneMinuteWorkoutsByWeek': oneMinuteWorkoutsByWeek,
      'overtimeWorkoutsByDate': overtimeWorkoutsByDate,
      'totalWorkouts': totalWorkouts,
      'totalTrainingSeconds': totalTrainingSeconds,
      'currentStreak': currentStreak,
      'overtimeWorkoutCount': overtimeWorkoutCount,
      'currentOvertimeStreak': currentOvertimeStreak,
      'stateChampOvertimeCount': stateChampOvertimeCount,
      'overtimeAfterTenMinuteWorkoutCount': overtimeAfterTenMinuteWorkoutCount,
      'highDifficultyWorkoutCount': highDifficultyWorkoutCount,
      'noPauseWorkoutCount': noPauseWorkoutCount,
      'customCalloutCount': customCalloutCount,
      'customCalloutWorkoutCount': customCalloutWorkoutCount,
      'premiumRecordingSaveCount': premiumRecordingSaveCount,
      'seasonPassWorkoutCount': seasonPassWorkoutCount,
      'totalSharedWorkouts': totalSharedWorkouts,
      'socialProgressPoints': socialProgressPoints,
      'relayStreak': relayStreak,
      'friendWorkoutStreak': friendWorkoutStreak,
      'bestPartnerStreak': bestPartnerStreak,
      'crewStreak': crewStreak,
      'totalQualifiedRelays': totalQualifiedRelays,
      'totalCompletedFriendWorkouts': totalCompletedFriendWorkouts,
      'totalCrewWeeks': totalCrewWeeks,
      'lastWorkoutDurationSeconds': lastWorkoutDurationSeconds,
      'lastWorkoutAt': lastWorkoutAt?.toIso8601String(),
      'seasonTargetDate': seasonTargetDate?.toIso8601String(),
      'seasonTargetSetAt': seasonTargetSetAt?.toIso8601String(),
    };
  }

  factory BadgeStats.fromMap(Map<String, dynamic> map) {
    return BadgeStats(
      calloutTotals: _decodeIntMap(map['calloutTotals']),
      timedSecondsByCallout: _decodeIntMap(map['timedSecondsByCallout']),
      fullMinuteCallouts: _decodeIntMap(map['fullMinuteCallouts']),
      fullMinuteCalloutsByWeek: _decodeIntMap(map['fullMinuteCalloutsByWeek']),
      workoutsByDate: _decodeIntMap(map['workoutsByDate']),
      oneMinuteWorkoutsByWeek: _decodeIntMap(map['oneMinuteWorkoutsByWeek']),
      overtimeWorkoutsByDate: _decodeIntMap(map['overtimeWorkoutsByDate']),
      totalWorkouts: (map['totalWorkouts'] as num?)?.toInt() ?? 0,
      totalTrainingSeconds: (map['totalTrainingSeconds'] as num?)?.toInt() ?? 0,
      currentStreak: (map['currentStreak'] as num?)?.toInt() ?? 0,
      overtimeWorkoutCount: (map['overtimeWorkoutCount'] as num?)?.toInt() ?? 0,
      currentOvertimeStreak:
          (map['currentOvertimeStreak'] as num?)?.toInt() ?? 0,
      stateChampOvertimeCount:
          (map['stateChampOvertimeCount'] as num?)?.toInt() ?? 0,
      overtimeAfterTenMinuteWorkoutCount:
          (map['overtimeAfterTenMinuteWorkoutCount'] as num?)?.toInt() ?? 0,
      highDifficultyWorkoutCount:
          (map['highDifficultyWorkoutCount'] as num?)?.toInt() ?? 0,
      noPauseWorkoutCount: (map['noPauseWorkoutCount'] as num?)?.toInt() ?? 0,
      customCalloutCount: (map['customCalloutCount'] as num?)?.toInt() ?? 0,
      customCalloutWorkoutCount:
          (map['customCalloutWorkoutCount'] as num?)?.toInt() ?? 0,
      premiumRecordingSaveCount:
          (map['premiumRecordingSaveCount'] as num?)?.toInt() ?? 0,
      seasonPassWorkoutCount:
          (map['seasonPassWorkoutCount'] as num?)?.toInt() ?? 0,
      totalSharedWorkouts: (map['totalSharedWorkouts'] as num?)?.toInt() ?? 0,
      socialProgressPoints: (map['socialProgressPoints'] as num?)?.toInt() ?? 0,
      relayStreak: (map['relayStreak'] as num?)?.toInt() ?? 0,
      friendWorkoutStreak: (map['friendWorkoutStreak'] as num?)?.toInt() ?? 0,
      bestPartnerStreak: (map['bestPartnerStreak'] as num?)?.toInt() ?? 0,
      crewStreak: (map['crewStreak'] as num?)?.toInt() ?? 0,
      totalQualifiedRelays: (map['totalQualifiedRelays'] as num?)?.toInt() ?? 0,
      totalCompletedFriendWorkouts:
          (map['totalCompletedFriendWorkouts'] as num?)?.toInt() ?? 0,
      totalCrewWeeks: (map['totalCrewWeeks'] as num?)?.toInt() ?? 0,
      lastWorkoutDurationSeconds:
          (map['lastWorkoutDurationSeconds'] as num?)?.toInt() ?? 0,
      lastWorkoutAt: _decodeDate(map['lastWorkoutAt']),
      seasonTargetDate: _decodeDate(map['seasonTargetDate']),
      seasonTargetSetAt: _decodeDate(map['seasonTargetSetAt']),
    );
  }
}

@immutable
class WorkoutBadgeInput {
  final DateTime completedAt;
  final Duration duration;
  final Map<String, int> calloutCounts;
  final Map<String, int> timedSecondsByCallout;
  final Map<String, int> fullMinuteCallouts;
  final Set<String> enabledCalloutIds;
  final int difficultyScore;
  final bool hadPause;
  final bool usedCustomCallouts;
  final bool usedRecording;
  final bool isPro;
  final String? workoutPresetId;
  final DateTime? seasonTargetDate;

  const WorkoutBadgeInput({
    required this.completedAt,
    required this.duration,
    required this.calloutCounts,
    required this.timedSecondsByCallout,
    required this.fullMinuteCallouts,
    required this.enabledCalloutIds,
    required this.difficultyScore,
    required this.hadPause,
    required this.usedCustomCallouts,
    required this.usedRecording,
    required this.isPro,
    this.workoutPresetId,
    this.seasonTargetDate,
  });

  int get estimatedRepsEarned =>
      calloutCounts.values.fold<int>(0, (sum, value) => sum + value);

  bool get isOvertimeWorkout =>
      workoutPresetId?.startsWith('overtime_') ?? false;

  bool get isStateChampOvertime =>
      workoutPresetId == 'overtime_state_champ_overtime';
}

@immutable
class SocialBadgeInput {
  const SocialBadgeInput({
    required this.updatedAt,
    required this.totalSharedWorkouts,
    required this.socialProgressPoints,
    required this.relayStreak,
    required this.friendWorkoutStreak,
    required this.bestPartnerStreak,
    required this.crewStreak,
    required this.totalQualifiedRelays,
    required this.totalCompletedFriendWorkouts,
    required this.totalCrewWeeks,
  });

  final DateTime updatedAt;
  final int totalSharedWorkouts;
  final int socialProgressPoints;
  final int relayStreak;
  final int friendWorkoutStreak;
  final int bestPartnerStreak;
  final int crewStreak;
  final int totalQualifiedRelays;
  final int totalCompletedFriendWorkouts;
  final int totalCrewWeeks;
}

@immutable
class BadgeWorkoutResult {
  final List<String> newlyUnlockedBadgeIds;
  final List<String> updatedBadgeIds;
  final int estimatedRepsEarned;
  final int currentStreak;
  final String? almostThereBadgeId;

  const BadgeWorkoutResult({
    this.newlyUnlockedBadgeIds = const [],
    this.updatedBadgeIds = const [],
    this.estimatedRepsEarned = 0,
    this.currentStreak = 0,
    this.almostThereBadgeId,
  });

  Map<String, dynamic> toMap() {
    return {
      'newlyUnlockedBadgeIds': newlyUnlockedBadgeIds,
      'updatedBadgeIds': updatedBadgeIds,
      'estimatedRepsEarned': estimatedRepsEarned,
      'currentStreak': currentStreak,
      'almostThereBadgeId': almostThereBadgeId,
    };
  }

  factory BadgeWorkoutResult.fromMap(Map<String, dynamic> map) {
    return BadgeWorkoutResult(
      newlyUnlockedBadgeIds:
          List<String>.from(map['newlyUnlockedBadgeIds'] ?? const []),
      updatedBadgeIds: List<String>.from(map['updatedBadgeIds'] ?? const []),
      estimatedRepsEarned: (map['estimatedRepsEarned'] as num?)?.toInt() ?? 0,
      currentStreak: (map['currentStreak'] as num?)?.toInt() ?? 0,
      almostThereBadgeId: map['almostThereBadgeId'] as String?,
    );
  }
}

@immutable
class BadgeProgressState {
  final Map<String, BadgeProgress> progressById;
  final BadgeStats stats;
  final List<String> recentUnlockedBadgeIds;
  final BadgeWorkoutResult? lastWorkoutResult;

  const BadgeProgressState({
    this.progressById = const {},
    this.stats = const BadgeStats(),
    this.recentUnlockedBadgeIds = const [],
    this.lastWorkoutResult,
  });

  BadgeProgress progressFor(BadgeDefinition definition) {
    return progressById[definition.id] ??
        BadgeProgress(id: definition.id, currentProgress: 0);
  }

  BadgeProgressState copyWith({
    Map<String, BadgeProgress>? progressById,
    BadgeStats? stats,
    List<String>? recentUnlockedBadgeIds,
    BadgeWorkoutResult? lastWorkoutResult,
  }) {
    return BadgeProgressState(
      progressById: progressById ?? this.progressById,
      stats: stats ?? this.stats,
      recentUnlockedBadgeIds:
          recentUnlockedBadgeIds ?? this.recentUnlockedBadgeIds,
      lastWorkoutResult: lastWorkoutResult ?? this.lastWorkoutResult,
    );
  }

  List<Badge> badgesFor(List<BadgeDefinition> definitions) {
    return definitions
        .map((definition) => Badge.fromDefinition(
              definition,
              progressFor(definition),
            ))
        .toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'progressById':
          progressById.map((key, value) => MapEntry(key, value.toMap())),
      'stats': stats.toMap(),
      'recentUnlockedBadgeIds': recentUnlockedBadgeIds,
      'lastWorkoutResult': lastWorkoutResult?.toMap(),
    };
  }

  String toJson() => jsonEncode(toMap());

  factory BadgeProgressState.fromJson(String source) {
    return BadgeProgressState.fromMap(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  factory BadgeProgressState.fromMap(Map<String, dynamic> map) {
    final rawProgress = map['progressById'];
    final progress = <String, BadgeProgress>{};
    if (rawProgress is Map) {
      for (final entry in rawProgress.entries) {
        if (entry.value is Map) {
          progress[entry.key.toString()] = BadgeProgress.fromMap(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    final rawStats = map['stats'];
    final rawResult = map['lastWorkoutResult'];
    return BadgeProgressState(
      progressById: progress,
      stats: rawStats is Map
          ? BadgeStats.fromMap(Map<String, dynamic>.from(rawStats))
          : const BadgeStats(),
      recentUnlockedBadgeIds:
          List<String>.from(map['recentUnlockedBadgeIds'] ?? const []),
      lastWorkoutResult: rawResult is Map
          ? BadgeWorkoutResult.fromMap(Map<String, dynamic>.from(rawResult))
          : null,
    );
  }
}

DateTime? _decodeDate(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw);
}

Map<String, int> _decodeIntMap(Object? source) {
  if (source is! Map) return {};
  return source.map(
    (key, value) => MapEntry(
      key.toString(),
      (value as num?)?.toInt() ?? 0,
    ),
  );
}
