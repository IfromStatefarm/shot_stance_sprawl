import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/badges/badge_catalog.dart';
import 'package:shot_stance_sprawl/features/badges/badge_engine.dart';
import 'package:shot_stance_sprawl/features/badges/badge_models.dart';

void main() {
  group('BadgeEngine', () {
    test('unlocks rep, workout, and streak badges from estimated callouts', () {
      final engine = BadgeEngine();

      final state = engine.recordWorkout(
        const BadgeProgressState(),
        WorkoutBadgeInput(
          completedAt: DateTime(2026, 6, 7, 9),
          duration: const Duration(minutes: 3),
          calloutCounts: const {'sprawl': 25},
          timedSecondsByCallout: const {},
          fullMinuteCallouts: const {},
          enabledCalloutIds: const {'sprawl'},
          difficultyScore: 5,
          hadPause: false,
          usedCustomCallouts: false,
          usedRecording: false,
          isPro: false,
        ),
      );

      final badges = state.badgesFor(BadgeCatalog.launchBadges);
      final sprawlStarter =
          badges.firstWhere((badge) => badge.id == 'sprawl_25');
      final firstSnap =
          badges.firstWhere((badge) => badge.id == 'streak_first_snap');
      final firstDrill =
          badges.firstWhere((badge) => badge.id == 'grind_first_drill');

      expect(sprawlStarter.isUnlocked, isTrue);
      expect(firstSnap.isUnlocked, isTrue);
      expect(firstDrill.isUnlocked, isTrue);
      expect(state.lastWorkoutResult?.estimatedRepsEarned, 25);
      expect(
        state.lastWorkoutResult?.newlyUnlockedBadgeIds,
        containsAll(['sprawl_25', 'streak_first_snap', 'grind_first_drill']),
      );
    });

    test('tracks timed stance minutes and full 60-second callouts', () {
      final engine = BadgeEngine();

      final state = engine.recordWorkout(
        const BadgeProgressState(),
        WorkoutBadgeInput(
          completedAt: DateTime(2026, 6, 7, 9),
          duration: const Duration(minutes: 5),
          calloutCounts: const {'stance': 5},
          timedSecondsByCallout: const {'stance': 300},
          fullMinuteCallouts: const {'stance': 1},
          enabledCalloutIds: const {'stance'},
          difficultyScore: 3,
          hadPause: false,
          usedCustomCallouts: false,
          usedRecording: false,
          isPro: false,
        ),
      );

      final badges = state.badgesFor(BadgeCatalog.launchBadges);
      expect(
        badges.firstWhere((badge) => badge.id == 'stance_5m').isUnlocked,
        isTrue,
      );
      expect(
        badges
            .firstWhere((badge) => badge.id == 'stance_60_survivor')
            .isUnlocked,
        isTrue,
      );
    });

    test('builds consecutive workout streak progress', () {
      final engine = BadgeEngine();
      var state = const BadgeProgressState();

      for (var day = 1; day <= 3; day++) {
        state = engine.recordWorkout(
          state,
          WorkoutBadgeInput(
            completedAt: DateTime(2026, 6, day, 8),
            duration: const Duration(minutes: 2),
            calloutCounts: const {'shot': 5},
            timedSecondsByCallout: const {},
            fullMinuteCallouts: const {},
            enabledCalloutIds: const {'shot'},
            difficultyScore: 3,
            hadPause: false,
            usedCustomCallouts: false,
            usedRecording: false,
            isPro: false,
          ),
        );
      }

      final streakBadge = state
          .badgesFor(BadgeCatalog.launchBadges)
          .firstWhere((badge) => badge.id == 'streak_three_day_scrapper');

      expect(state.stats.currentStreak, 3);
      expect(streakBadge.isUnlocked, isTrue);
    });

    test('unlocks overtime bonus badges from overtime presets', () {
      final engine = BadgeEngine();
      var state = engine.recordWorkout(
        const BadgeProgressState(),
        WorkoutBadgeInput(
          completedAt: DateTime(2026, 6, 7, 9),
          duration: const Duration(minutes: 10),
          calloutCounts: const {'shot': 20},
          timedSecondsByCallout: const {},
          fullMinuteCallouts: const {},
          enabledCalloutIds: const {'shot'},
          difficultyScore: 8,
          hadPause: false,
          usedCustomCallouts: false,
          usedRecording: false,
          isPro: false,
          workoutPresetId: 'the_grind',
        ),
      );

      state = engine.recordWorkout(
        state,
        WorkoutBadgeInput(
          completedAt: DateTime(2026, 6, 7, 9, 5),
          duration: const Duration(minutes: 3),
          calloutCounts: const {'stance': 2, 'shot': 6},
          timedSecondsByCallout: const {'stance': 30},
          fullMinuteCallouts: const {},
          enabledCalloutIds: const {'stance', 'shot', 'sprawl', 'circle'},
          difficultyScore: 9,
          hadPause: false,
          usedCustomCallouts: false,
          usedRecording: false,
          isPro: false,
          workoutPresetId: 'overtime_sudden_victory',
        ),
      );

      final badges = state.badgesFor(BadgeCatalog.launchBadges);
      expect(
        badges.firstWhere((badge) => badge.id == 'overtime_bonus').isUnlocked,
        isTrue,
      );
      expect(
        badges
            .firstWhere((badge) => badge.id == 'overtime_one_more_period')
            .isUnlocked,
        isTrue,
      );
      expect(state.stats.overtimeWorkoutCount, 1);
    });

    test('tracks three-day overtime streak and State Champ Overtime', () {
      final engine = BadgeEngine();
      var state = const BadgeProgressState();

      for (var day = 7; day <= 9; day++) {
        state = engine.recordWorkout(
          state,
          WorkoutBadgeInput(
            completedAt: DateTime(2026, 6, day, 8),
            duration: const Duration(minutes: 3),
            calloutCounts: const {'stance': 2, 'shot': 6},
            timedSecondsByCallout: const {'stance': 30},
            fullMinuteCallouts: const {},
            enabledCalloutIds: const {'stance', 'shot', 'sprawl', 'circle'},
            difficultyScore: 10,
            hadPause: false,
            usedCustomCallouts: false,
            usedRecording: false,
            isPro: false,
            workoutPresetId: day == 9
                ? 'overtime_state_champ_overtime'
                : 'overtime_sudden_victory',
          ),
        );
      }

      final badges = state.badgesFor(BadgeCatalog.launchBadges);
      expect(
        badges
            .firstWhere((badge) => badge.id == 'overtime_refused_to_quit')
            .isUnlocked,
        isTrue,
      );
      expect(
        badges
            .firstWhere(
              (badge) => badge.id == 'overtime_state_finals_gas_tank',
            )
            .isUnlocked,
        isTrue,
      );
      expect(state.stats.currentOvertimeStreak, 3);
    });
  });
}
