import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'badge_catalog.dart';
import 'badge_engine.dart';
import 'badge_models.dart';

final badgeProgressProvider =
    NotifierProvider<BadgeProgressNotifier, BadgeProgressState>(() {
  return BadgeProgressNotifier();
});

final badgeViewsProvider = Provider<List<Badge>>((ref) {
  final state = ref.watch(badgeProgressProvider);
  return state.badgesFor(BadgeCatalog.launchBadges);
});

final almostThereBadgesProvider = Provider<List<Badge>>((ref) {
  final badges = ref.watch(badgeViewsProvider).where((badge) {
    return badge.isAlmostThere && !badge.isPremium;
  }).toList()
    ..sort((a, b) => b.completionRatio.compareTo(a.completionRatio));

  return badges.take(8).toList();
});

final recentlyEarnedBadgesProvider = Provider<List<Badge>>((ref) {
  final state = ref.watch(badgeProgressProvider);
  final badgesById = {
    for (final badge in ref.watch(badgeViewsProvider)) badge.id: badge,
  };

  return state.recentUnlockedBadgeIds
      .map((id) => badgesById[id])
      .whereType<Badge>()
      .take(8)
      .toList();
});

final homeBadgeChasesProvider = Provider<List<Badge>>((ref) {
  final badges = ref.watch(badgeViewsProvider);
  Badge? nearest(Iterable<Badge> candidates) {
    final sorted = candidates
        .where((badge) => !badge.isUnlocked && !badge.isPremium)
        .toList()
      ..sort((a, b) {
        final progressCompare = b.completionRatio.compareTo(a.completionRatio);
        if (progressCompare != 0) return progressCompare;
        return _remaining(a).compareTo(_remaining(b));
      });
    return sorted.isEmpty ? null : sorted.first;
  }

  final selected = <Badge>[
    if (nearest(badges.where((badge) =>
            badge.category == BadgeCategory.moveMastery ||
            badge.category == BadgeCategory.timedMastery))
        case final badge?)
      badge,
    if (nearest(badges.where((badge) => badge.category == BadgeCategory.streak))
        case final badge?)
      badge,
    if (nearest(badges.where((badge) =>
            badge.category == BadgeCategory.grind ||
            badge.category == BadgeCategory.combo))
        case final badge?)
      badge,
  ];

  final seen = <String>{};
  return selected.where((badge) => seen.add(badge.id)).take(3).toList();
});

class BadgeProgressNotifier extends Notifier<BadgeProgressState> {
  static const _keyBadgeProgress = 'badge_progress_v1';
  static final _engine = BadgeEngine();

  @override
  BadgeProgressState build() {
    _load();
    return const BadgeProgressState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_keyBadgeProgress);
      if (jsonString == null) {
        await prefs.setString(_keyBadgeProgress, state.toJson());
        return;
      }
      state = BadgeProgressState.fromJson(jsonString);
    } catch (e) {
      debugPrint('Error loading badge progress: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBadgeProgress, state.toJson());
  }

  Future<BadgeWorkoutResult> recordWorkout(WorkoutBadgeInput input) async {
    state = _engine.recordWorkout(state, input);
    await _save();
    return state.lastWorkoutResult ?? const BadgeWorkoutResult();
  }

  Future<void> markSeasonTargetSet(DateTime targetDate) async {
    state = _engine.recordSeasonTargetSet(state, targetDate);
    await _save();
  }

  Future<void> recordCustomCalloutCreated(int customCalloutCount) async {
    state = _engine.recordCustomCalloutCreated(
      state,
      customCalloutCount: customCalloutCount,
    );
    await _save();
  }

  Future<void> recordPremiumRecordingSaved() async {
    state = _engine.recordPremiumRecordingSaved(state);
    await _save();
  }
}

int _remaining(Badge badge) {
  return (badge.targetProgress - badge.currentProgress).clamp(0, 1 << 30);
}
