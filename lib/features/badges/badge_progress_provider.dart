import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/badge_progress_repository.dart';
import 'badge_catalog.dart';
import 'badge_engine.dart';
import 'badge_models.dart';
import '../social/social_models.dart';
import '../social/social_providers.dart';

final badgeProgressProvider =
    NotifierProvider<BadgeProgressNotifier, BadgeProgressState>(() {
  return BadgeProgressNotifier();
});

/// Mirrors server-authoritative social stats into the existing local badge
/// engine. Social streak dates and rewards are never calculated here.
final socialBadgeSyncProvider = Provider<void>((ref) {
  String? lastSignature;
  ref.listen<AsyncValue<SocialStats?>>(socialStatsProvider, (_, next) {
    final stats = next.asData?.value;
    if (stats == null) return;
    final signature = [
      stats.uid,
      stats.totalSharedWorkouts,
      stats.socialProgressPoints,
      stats.relayStreak,
      stats.friendWorkoutStreak,
      stats.bestPartnerStreak,
      stats.crewStreak,
      stats.totalQualifiedRelays,
      stats.totalCompletedFriendWorkouts,
      stats.totalCrewWeeks,
      stats.updatedAt?.microsecondsSinceEpoch ?? 0,
    ].join(':');
    if (signature == lastSignature) return;
    lastSignature = signature;
    unawaited(
      ref.read(badgeProgressProvider.notifier).recordSocialProgress(
            SocialBadgeInput(
              updatedAt:
                  stats.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              totalSharedWorkouts: stats.totalSharedWorkouts,
              socialProgressPoints: stats.socialProgressPoints,
              relayStreak: stats.relayStreak,
              friendWorkoutStreak: stats.friendWorkoutStreak,
              bestPartnerStreak: stats.bestPartnerStreak,
              crewStreak: stats.crewStreak,
              totalQualifiedRelays: stats.totalQualifiedRelays,
              totalCompletedFriendWorkouts: stats.totalCompletedFriendWorkouts,
              totalCrewWeeks: stats.totalCrewWeeks,
            ),
          ),
    );
  }, fireImmediately: true);
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
    if (nearest(badges.where((badge) =>
            badge.category == BadgeCategory.streak ||
            badge.category == BadgeCategory.social))
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
  static final _engine = BadgeEngine();
  late Future<void> _loadFuture;

  @override
  BadgeProgressState build() {
    _loadFuture = _load();
    return const BadgeProgressState();
  }

  Future<BadgeProgressRepository> _repository() async {
    return BadgeProgressRepository(await SharedPreferences.getInstance());
  }

  Future<void> _load() async {
    try {
      final repository = await _repository();
      final progress = repository.loadProgress();
      if (progress == null) {
        await repository.saveProgress(state);
        return;
      }
      state = progress;
    } catch (e) {
      debugPrint('Error loading badge progress: $e');
    }
  }

  Future<void> _save() async {
    await (await _repository()).saveProgress(state);
  }

  Future<BadgeWorkoutResult> recordWorkout(WorkoutBadgeInput input) async {
    await _loadFuture;
    state = _engine.recordWorkout(state, input);
    await _save();
    return state.lastWorkoutResult ?? const BadgeWorkoutResult();
  }

  Future<void> markSeasonTargetSet(DateTime targetDate) async {
    await _loadFuture;
    state = _engine.recordSeasonTargetSet(state, targetDate);
    await _save();
  }

  Future<void> recordCustomCalloutCreated(int customCalloutCount) async {
    await _loadFuture;
    state = _engine.recordCustomCalloutCreated(
      state,
      customCalloutCount: customCalloutCount,
    );
    await _save();
  }

  Future<void> recordPremiumRecordingSaved() async {
    await _loadFuture;
    state = _engine.recordPremiumRecordingSaved(state);
    await _save();
  }

  Future<void> recordSocialProgress(SocialBadgeInput input) async {
    await _loadFuture;
    state = _engine.recordSocialProgress(state, input);
    await _save();
  }
}

int _remaining(Badge badge) {
  return (badge.targetProgress - badge.currentProgress).clamp(0, 1 << 30);
}
